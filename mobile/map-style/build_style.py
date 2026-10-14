#!/usr/bin/env python3
"""Build the "SIGAP Banjir Light" Mapbox style from mapbox/streets-v12.

Usage: python3 build_style.py [out.json]
Reads MAPBOX_TOKEN from ../env.json at runtime, fetches streets-v12,
recolors it to a calm low-saturation palette, trims POI clutter and writes
sigap-light.json next to this script (or to the given path).
"""
import colorsys
import json
import re
import ssl
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE_URL = "https://api.mapbox.com/styles/v1/mapbox/streets-v12?access_token="

# Top-level keys tied to the Mapbox account / API response; Studio upload rejects them.
DROP_KEYS = ("owner", "id", "created", "modified", "visibility", "draft")

# ---- palette ---------------------------------------------------------------
BG = "#F0F3F7"
WATER = "#C9DDF5"
WATER_EDGE = "#B7CFEE"   # water-shadow / waterway outline, keeps rivers crisp
WATER_TEXT = "#6A8BB8"
PARK = "#DDEFD9"
WOOD = "#DBEAD5"
BUILDING = "#E9ECF1"
BUILDING_EDGE = "#DCE0E7"
ROAD = "#FFFFFF"
ROAD_CASE = "#D5DAE2"
MOTORWAY = "#F8E2A8"
TRUNK = "#FBEBC2"
MOTORWAY_CASE = "#E4D6B0"
TEXT = "#4A5160"
TEXT_STRONG = "#353B47"
TEXT_SOFT = "#6B7385"
HALO = "#FFFFFF"

# POIs that matter during a flood stay at their default zoom; the rest only from z17.
KEEP_MAKI = ["hospital", "doctor", "school", "college", "police", "fire-station", "town-hall"]
OTHER_POI_MINZOOM = 17

HSL_RE = re.compile(r"^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$")


def soften(color, text=False):
    """Desaturate (and for fills lighten) an hsl/hsla string; warm neutrals become cool neutrals."""
    m = HSL_RE.match(color)
    if not m:
        return color  # ponytail: streets-v12 only uses hsl/hsla; add rgb/hex parsing if base changes
    h, s, l = (float(m.group(i)) for i in (1, 2, 3))
    a = m.group(4)
    if s <= 25:            # near-neutral grays (streets uses warm hue 20) -> cool gray
        h, s = 220, min(s, 14)
    elif text:
        s *= 0.6
        l = min(l, 45)     # keep coloured labels legible
    else:
        s *= 0.45
        l += (100 - l) * 0.12
    out = f"hsl({h:.0f}, {s:.0f}%, {l:.0f}%)" if a is None else f"hsla({h:.0f}, {s:.0f}%, {l:.0f}%, {a})"
    return out


def walk(value, fn):
    if isinstance(value, list):
        return [walk(v, fn) for v in value]
    if isinstance(value, str):
        return fn(value)
    return value


def road_override(lid):
    """Explicit road colors by layer id (road-*, bridge-*; tunnels keep the softened defaults)."""
    m = re.match(r"^(road|bridge)-(.+?)(-2)?(-case)?$", lid)
    if not m:
        return None
    kind, case = m.group(2), m.group(4)
    if kind == "motorway-trunk":
        return MOTORWAY_CASE if case else ["match", ["get", "class"], "motorway", MOTORWAY, TRUNK]
    if kind == "major-link":
        return MOTORWAY_CASE if case else ["match", ["get", "class"], "motorway_link", MOTORWAY, TRUNK]
    if kind in ("minor", "minor-link", "street", "street-low", "secondary-tertiary", "primary"):
        return ROAD_CASE if case else ROAD
    return None


LANDUSE = ["match", ["get", "class"],
           ["park", "grass", "cemetery", "pitch"], PARK,
           ["wood", "scrub", "agriculture"], WOOD,
           "hospital", "#F5E7EA",
           "school", "#F2EEE4",
           "airport", "#E6EAF3",
           "sand", "#F1EDDF",
           "glacier", "#E8F1F8",
           "commercial_area", "#F1F1EE",
           "residential", "#EEF1F5",
           ["facility", "industrial"], "#E9EBF0",
           "#EDEFF3"]

# layer id -> {paint prop: value}
OVERRIDES = {
    "land": {"background-color": BG},
    "land-structure-polygon": {"fill-color": BG},
    "landcover": {"fill-color": ["match", ["get", "class"], "wood", WOOD, "snow", "#E8F1F8", PARK]},
    "landuse": {"fill-color": LANDUSE},
    "national-park": {"fill-color": PARK},
    "water": {"fill-color": WATER},
    "water-shadow": {"fill-color": WATER_EDGE},
    "waterway": {"line-color": WATER},
    "waterway-shadow": {"line-color": WATER_EDGE},
    "building": {"fill-color": BUILDING, "fill-outline-color": BUILDING_EDGE},
    "road-polygon": {"fill-color": ROAD, "fill-outline-color": ROAD_CASE},
    "road-label": {"text-color": TEXT, "text-halo-color": HALO},
    "path-pedestrian-label": {"text-color": TEXT_SOFT, "text-halo-color": HALO},
    "settlement-major-label": {"text-color": TEXT_STRONG, "text-halo-color": HALO},
    "settlement-minor-label": {"text-color": TEXT_STRONG, "text-halo-color": HALO},
    "settlement-subdivision-label": {"text-color": TEXT_SOFT, "text-halo-color": HALO},
    "state-label": {"text-color": TEXT_SOFT, "text-halo-color": HALO},
    "country-label": {"text-color": TEXT, "text-halo-color": HALO},
    "water-line-label": {"text-color": WATER_TEXT, "text-halo-color": "hsla(214, 70%, 92%, 0.6)"},
    "water-point-label": {"text-color": WATER_TEXT, "text-halo-color": "hsla(214, 70%, 92%, 0.6)"},
    "waterway-label": {"text-color": WATER_TEXT, "text-halo-color": "hsla(214, 70%, 92%, 0.6)"},
    "natural-point-label": {"text-color": TEXT_SOFT, "text-halo-color": HALO},
    "natural-line-label": {"text-color": TEXT_SOFT, "text-halo-color": HALO},
    "airport-label": {"text-color": TEXT, "text-halo-color": HALO},
    "transit-label": {"text-halo-color": HALO},
    "poi-label": {"text-halo-color": HALO, "text-halo-width": 1},
}


def transform(style):
    for k in DROP_KEYS:
        style.pop(k, None)
    style["name"] = "SIGAP Banjir Light"
    style["fog"]["high-color"] = "hsl(214, 50%, 85%)"
    style["fog"]["space-color"] = ["interpolate", ["exponential", 1.2], ["zoom"],
                                   5, "hsl(214, 25%, 40%)", 7, "hsl(214, 50%, 85%)"]

    for layer in style["layers"]:
        lid, paint = layer["id"], layer.get("paint", {})
        is_text = layer["type"] == "symbol"
        for prop in paint:
            if prop.endswith("-color"):
                paint[prop] = walk(paint[prop], lambda c: soften(c, text=is_text and prop.startswith("text")))
        road = road_override(lid)
        if road is not None and "line-color" in paint:
            paint["line-color"] = road
        paint.update(OVERRIDES.get(lid, {}))

        if lid == "poi-label":
            keep = ["match", ["get", "maki"], KEEP_MAKI, True, False]
            layer["filter"] = ["all", layer["filter"],
                               ["step", ["zoom"], keep, OTHER_POI_MINZOOM, True]]
    return local_names(style)


EN_NAME = ["coalesce", ["get", "name_en"], ["get", "name"]]


def local_names(node):
    """Label pakai nama lokal (Indonesia), bukan name_en: "Pademangan Barat", bukan "West Pademangan"."""
    if node == EN_NAME:
        return ["get", "name"]
    if isinstance(node, list):
        return [local_names(x) for x in node]
    if isinstance(node, dict):
        return {k: local_names(v) for k, v in node.items()}
    return node


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "sigap-light.json"
    token = json.loads((HERE.parent / "env.json").read_text())["MAPBOX_TOKEN"]
    try:  # python.org builds on macOS ship without a CA bundle
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        ctx = ssl.create_default_context()
    with urllib.request.urlopen(BASE_URL + token, context=ctx) as r:
        style = json.load(r)
    out.write_text(json.dumps(transform(style), indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {out}")


if __name__ == "__main__":
    assert soften("hsl(20, 20%, 95%)") == "hsl(220, 14%, 95%)"
    assert soften("hsla(200, 100%, 80%, 0.35)") == "hsla(200, 45%, 82%, 0.35)"
    assert road_override("bridge-motorway-trunk-2-case") == MOTORWAY_CASE
    assert road_override("road-primary") == ROAD and road_override("road-path") is None
    main()
