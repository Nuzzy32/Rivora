import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../art.dart';
import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

/// M02: peta beranda.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final _ctl = MapController();
  late final AnimationController _fly;

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  /// Tombol + / − untuk yang memegang HP satu tangan atau tidak terbiasa mencubit layar.
  void _zoomBy(double d) =>
      _flyTo(_ctl.camera.center, (_ctl.camera.zoom + d).clamp(10, 18));

  /// Geser + zoom peta secara halus (bukan meloncat), supaya pengguna tetap paham posisinya.
  void _flyTo(LatLng to, double zoom) {
    if (reduced(context)) {
      _ctl.move(to, zoom);
      return;
    }
    final from = _ctl.camera;
    final lat = Tween(begin: from.center.latitude, end: to.latitude);
    final lng = Tween(begin: from.center.longitude, end: to.longitude);
    final z = Tween(begin: from.zoom, end: zoom);
    final a = CurvedAnimation(parent: _fly, curve: easeOut);
    void step() =>
        _ctl.move(LatLng(lat.evaluate(a), lng.evaluate(a)), z.evaluate(a));
    _fly
      ..stop()
      ..reset();
    _fly.addListener(step);
    _fly.forward().whenCompleteOrCancel(() => _fly.removeListener(step));
  }

  Future<void> _locateMe() async {
    if (app.locDenied) return app.showToast('Izin lokasi belum aktif');
    await app.locate();
    _flyTo(app.center, 15);
    app.showToast(
      app.userPos == null
          ? 'Kamu di luar Surabaya. Peta dipusatkan di Balai Kota.'
          : 'Peta dipusatkan ke lokasimu',
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = topInset(context), base = tabTop(context) + 14;
    final flood = app.layers.contains('flood') && !app.pointsLoading;
    final radarOn = app.layers.contains('radar');
    final rainLine = app.forecast?.rainLine;
    final ctrlBottom =
        base +
        (radarOn
            ? 230.0
            : rainLine != null
            ? 140.0
            : 104.0);
    final empty = flood && app.nearby.isEmpty;
    if (app.userPos != null && !app.centeredOnUser) {
      app.centeredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _flyTo(app.userPos!, 14.5),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _ctl,
          options: MapOptions(
            initialCenter: app.mapCenter ?? app.center,
            initialZoom: app.mapZoom,
            minZoom: 10,
            maxZoom: 18,
            backgroundColor: const Color(0xFFE7EEF9),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onPositionChanged: (cam, _) {
              app.mapCenter = cam.center;
              app.mapZoom = cam.zoom;
            },
            onMapEvent: (e) {
              if (e is MapEventMoveEnd) app.mapMoved(e.camera.center);
            },
            onTap: (_, _) =>
                app.legend ? app.set(() => app.legend = false) : null,
          ),
          children: [
            baseTiles(context),
            if (app.layers.contains('risk'))
              PolygonLayer(
                polygons: [for (final r in app.risk) _riskPolygon(r)],
              ),
            if (radarOn && app.radarState == 'ready')
              Opacity(
                opacity: .55,
                child: TileLayer(
                  urlTemplate: app.radar!.url(app.radarFrame),
                  maxNativeZoom: 7,
                  userAgentPackageName: 'com.rivora.sigap_banjir',
                  // Frame radar berganti tiap 10 menit; tidak berguna disimpan.
                  tileProvider: NetworkTileProvider(
                    cachingProvider: const DisabledMapCachingProvider(),
                  ),
                ),
              ),
            if (flood)
              PolylineLayer(
                polylines: [
                  for (final p in app.points)
                    if (p.segment != null) _segment(p),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final s in app.shelters)
                  if (app.layers.contains(s.type))
                    Marker(
                      point: s.pos,
                      width: 48,
                      height: 48,
                      child: _ShelterMarker(s),
                    ),
                if (app.userPos != null)
                  Marker(
                    point: app.userPos!,
                    width: 64,
                    height: 64,
                    child: const _UserDot(),
                  ),
                if (app.locDenied)
                  Marker(
                    point: balaiKota,
                    width: 90,
                    height: 64,
                    alignment: Alignment.topCenter,
                    child: const _CityHall(),
                  ),
                if (flood)
                  for (final p in app.points)
                    Marker(
                      point: p.pos,
                      width: 52,
                      height: 52,
                      child: Appear(
                        index: app.points.indexOf(p),
                        dy: 0,
                        scale: .6,
                        child: _FloodMarker(p),
                      ),
                    ),
              ],
            ),
          ],
        ),

        Positioned.fill(
          child: IgnorePointer(
            ignoring: !app.pointsLoading,
            child: AnimatedSwitcher(
              duration: dur(context, 300),
              child: !app.pointsLoading
                  ? const SizedBox.shrink()
                  : ColoredBox(
                      color: const Color(0xB8F4F7FD),
                      child: Center(
                        child: Box(
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(
                            width: 230,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: C.blue,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Memuat kondisi terbaru…',
                                        style: t(14, w6),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Shimmer(
                                  child: Column(
                                    children: [
                                      _bar(1),
                                      const SizedBox(height: 8),
                                      _bar(.7),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),

        if (empty)
          Positioned(
            left: 36,
            right: 36,
            top: top + 250,
            child: Appear(
              child: EmptyCard(
                Icons.sentiment_satisfied_rounded,
                'Belum ada laporan di sekitarmu',
                'Dalam radius 5 km belum ada genangan yang dilaporkan. Kalau kamu melihat genangan, bantu warga lain dengan melapor.',
                iconColor: C.green,
                action: Btn.violet(
                  'Lapor genangan',
                  height: 48,
                  fontSize: 14,
                  onTap: app.openReport,
                ),
              ),
            ),
          ),

        // Pencarian + notifikasi
        Positioned(
          top: top + 8,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: Tap(
                  onTap: () => app.go(Scr.search),
                  height: 52,
                  radius: 18,
                  color: Colors.white,
                  shadow: soft(.14, 24, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: 22, color: C.ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cari jalan atau lokasi…',
                          overflow: TextOverflow.ellipsis,
                          style: t(14, FontWeight.w400, C.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SquareBtn(
                    Icons.notifications_none_rounded,
                    size: 52,
                    label: 'Notifikasi',
                    onTap: () => app.set(() {
                      app.notifReturn = Scr.map;
                      app.go(Scr.notif);
                    }),
                  ),
                  if (app.unread > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IgnorePointer(
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: gBlueSoft,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${app.unread}',
                              style: t(9, w7, Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Chip lapisan
        Positioned(
          top: top + 68,
          left: 0,
          right: 0,
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            children: [
              for (final (k, label, icon) in const [
                ('flood', 'Genangan', Icons.water_rounded),
                ('posko', 'Posko', Icons.night_shelter_rounded),
                ('faskes', 'Faskes', Icons.local_hospital_rounded),
                ('radar', 'Radar hujan', Icons.radar),
                ('risk', 'Rawan', Icons.texture_rounded),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    toggled: app.layers.contains(k),
                    child: Tap(
                      onTap: () => app.toggleLayer(k),
                      height: 48,
                      radius: 15,
                      color: app.layers.contains(k) ? C.blueInk : Colors.white,
                      shadow: soft(.14, 18, 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          end: app.layers.contains(k) ? Colors.white : C.ink,
                        ),
                        duration: dur(context, 200),
                        builder: (context, c, _) => Row(
                          children: [
                            Icon(icon, size: 18, color: c),
                            const SizedBox(width: 6),
                            Text(label, style: t(13, w5, c!)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        Positioned(
          top: top + 126,
          left: 16,
          right: 16,
          child: AnimatedSize(
            duration: dur(context, 260),
            curve: easeOut,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                if (app.offline && app.pointsFetchedAt != null) ...[
                  Appear(
                    child: Note(
                      'Data terakhir: ${_when(app.pointsFetchedAt!)}',
                      bold: 'Offline.',
                      icon: Icons.cloud_off_rounded,
                      bg: C.ink,
                      fg: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (app.locDenied)
                  Appear(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: soft(.14, 18, 8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_off_rounded,
                            size: 20,
                            color: C.redBright,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Lokasi belum aktif. Peta dipusatkan di Balai Kota.',
                              style: t(13, FontWeight.w400, C.ink, 1.4),
                            ),
                          ),
                          Tap(
                            onTap: app.enableLocation,
                            height: 44,
                            radius: 12,
                            color: C.blueTint,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Center(
                              child: Text(
                                'Aktifkan',
                                style: t(13, w6, C.blueMid),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (app.layers.contains('risk')) ...[
                  const SizedBox(height: 8),
                  const Appear(child: _RiskLegend()),
                ],
              ],
            ),
          ),
        ),

        // Legenda + lokasi saya
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          right: 16,
          bottom: ctrlBottom,
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: soft(.12, 20, 8),
                ),
                child: Column(
                  children: [
                    SquareBtn(
                      Icons.add_rounded,
                      label: 'Perbesar peta',
                      shadowed: false,
                      onTap: () => _zoomBy(1),
                    ),
                    Container(width: 28, height: 1, color: C.line),
                    SquareBtn(
                      Icons.remove_rounded,
                      label: 'Perkecil peta',
                      shadowed: false,
                      onTap: () => _zoomBy(-1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SquareBtn(
                Icons.format_list_bulleted_rounded,
                label: 'Legenda ketinggian air',
                onTap: () => app.set(() => app.legend = !app.legend),
              ),
              const SizedBox(height: 10),
              SquareBtn(
                Icons.my_location_rounded,
                fg: C.blue,
                label: 'Lokasi saya',
                onTap: _locateMe,
              ),
            ],
          ),
        ),
        Positioned(
          right: 74,
          bottom: ctrlBottom,
          child: AnimatedSwitcher(
            duration: dur(context, 260),
            reverseDuration: dur(context, 150),
            switchInCurve: easeOut,
            // Membesar dari pojok kanan-bawah, dekat tombol legenda (bukan dari tengah).
            transitionBuilder: (child, a) => ScaleTransition(
              alignment: Alignment.bottomRight,
              scale: Tween(begin: .9, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: app.legend ? const _Legend() : const SizedBox.shrink(),
          ),
        ),

        Positioned(
          left: 16,
          bottom: ctrlBottom,
          child: GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(mapCredit, style: t(10, w5, C.sub)),
            ),
          ),
        ),

        Positioned(
          left: 16,
          right: 16,
          bottom: base,
          child: AnimatedSwitcher(
            duration: dur(context, 360),
            reverseDuration: dur(context, 160),
            transitionBuilder: materialize(from: const Offset(0, 16)),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomCenter,
              children: [...previous, ?current],
            ),
            child: radarOn
                ? _RadarCard(key: const ValueKey('radar'))
                : _ForecastCard(rainLine, key: const ValueKey('fc')),
          ),
        ),
      ],
    );
  }

  Widget _bar(double f) => FractionallySizedBox(
    widthFactor: f,
    child: Container(
      height: 10,
      decoration: BoxDecoration(
        color: C.line,
        borderRadius: BorderRadius.circular(5),
      ),
    ),
  );

  Polyline _segment(FloodPoint p) {
    final d = depths[p.depth];
    return Polyline(
      points: p.segment!,
      strokeWidth: 9,
      color: d.color.withValues(alpha: p.stale ? .4 : .92),
      borderStrokeWidth: 2.5,
      borderColor: Colors.white,
      strokeCap: StrokeCap.round,
      // US-01: putus-putus jika belum terverifikasi.
      pattern: p.verification == 'unverified'
          ? StrokePattern.dashed(segments: const [12, 7])
          : const StrokePattern.solid(),
    );
  }

  Polygon _riskPolygon(RiskArea r) {
    // US-13: warna netral, beda dari skala ketinggian air.
    final a = {'kadang': .10, 'sering': .18, 'sangat_sering': .28}[r.level]!;
    return Polygon(
      points: r.polygon,
      color: C.grayInk.withValues(alpha: a),
      borderColor: C.grayInk.withValues(alpha: .6),
      borderStrokeWidth: 1.5,
      pattern: StrokePattern.dashed(segments: const [6, 5]),
    );
  }
}

class _FloodMarker extends StatelessWidget {
  final FloodPoint p;
  const _FloodMarker(this.p);

  @override
  Widget build(BuildContext context) {
    final d = depths[p.depth],
        v = vers[p.verification]!,
        sel = app.selPoint == p.id;
    final (badgeBg, badge) = switch (p.verification) {
      'official' => (
        C.violetMid,
        const Icon(Icons.shield_rounded, size: 11, color: Colors.white),
      ),
      'verified' => (
        C.blueMid,
        const Icon(Icons.check_rounded, size: 12, color: Colors.white),
      ),
      _ => (const Color(0xFF5E6478), Text('?', style: t(10, w7, Colors.white))),
    };
    return Semantics(
      button: true,
      label: '${p.name}, ${p.receded ? 'sudah surut' : d.label}, ${v.label}',
      child: GestureDetector(
        onTap: () => app.set(() {
          app.selPoint = p.id;
          app.legend = false;
        }),
        child: Center(
          child: AnimatedScale(
            scale: sel ? 1.25 : 1,
            duration: dur(context, 280),
            curve: Curves
                .easeOutBack, // sedikit memantul: penanda terpilih terasa diangkat
            child: Opacity(
              opacity: p.stale ? .45 : 1,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    foregroundPainter: p.verification == 'unverified'
                        ? const _DashedRing()
                        : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.color,
                        border: p.verification == 'unverified'
                            ? null
                            : Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: d.color.withValues(alpha: .4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: p.receded
                            ? Icon(Icons.check_rounded, size: 20, color: d.fg)
                            : Text(d.mark, style: t(11, w7, d.fg)),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -7,
                    right: -7,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: badgeBg,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(child: badge),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Garis tepi putus-putus untuk penanda laporan belum terverifikasi.
class _DashedRing extends CustomPainter {
  const _DashedRing();

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final rect = Rect.fromLTWH(1.25, 1.25, s.width - 2.5, s.height - 2.5);
    const n = 10;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(
        rect,
        i * 2 * math.pi / n,
        math.pi / n * 1.2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ShelterMarker extends StatelessWidget {
  final Shelter s;
  const _ShelterMarker(this.s);

  @override
  Widget build(BuildContext context) {
    final posko = s.type == 'posko';
    return Semantics(
      button: true,
      label: '${posko ? 'Posko' : 'Faskes'} ${s.name}',
      child: GestureDetector(
        onTap: () => app.set(() {
          app.selShelter = s.id;
          app.legend = false;
        }),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              boxShadow: soft(.25, 14, 6),
            ),
            child: Icon(
              posko
                  ? Icons.night_shelter_rounded
                  : Icons.local_hospital_rounded,
              size: 21,
              color: posko ? C.violetMid : C.blueInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Lokasimu',
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: C.blue.withValues(alpha: .18),
      ),
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.blue,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: soft(.5, 10, 4, C.blue),
          ),
        ),
      ),
    ),
  );
}

class _CityHall extends StatelessWidget {
  const _CityHall();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: C.ink,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text('Balai Kota', style: t(11, w6, Colors.white)),
      ),
      const Icon(Icons.location_on_rounded, size: 30, color: C.ink),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Container(
    width: 230,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: soft(.18, 36, 18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KETINGGIAN AIR',
          style: t(12, w6, C.muted).copyWith(letterSpacing: .4),
        ),
        const SizedBox(height: 4),
        for (final d in depths)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d.color,
                  ),
                  child: Center(child: Text(d.mark, style: t(9, w7, d.fg))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(d.label, style: t(13, w5))),
                Text(d.cm, style: t(12, FontWeight.w400, C.muted)),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: C.line),
        ),
        _row(
          const SizedBox(
            width: 18,
            height: 18,
            child: CustomPaint(
              painter: _DashedRing(),
              child: ColoredBox(color: Colors.transparent),
            ),
          ),
          'Putus-putus: belum terverifikasi',
          dashedGray: true,
        ),
        _row(
          Container(
            width: 18,
            height: 6,
            decoration: BoxDecoration(
              color: depths[2].color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          'Garis: ruas jalan tergenang',
        ),
        _row(
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x99C9CEDA),
            ),
          ),
          'Pudar: perlu konfirmasi',
        ),
      ],
    ),
  );

  Widget _row(Widget icon, String text, {bool dashedGray = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        dashedGray
            ? Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF8A90A2),
                ),
                child: icon,
              )
            : icon,
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: t(12, FontWeight.w400, C.body))),
      ],
    ),
  );
}

class _RiskLegend extends StatelessWidget {
  const _RiskLegend();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      boxShadow: soft(.14, 18, 8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final (a, label) in const [
              (.10, 'Kadang (3–5)'),
              (.18, 'Sering (6–10)'),
              (.28, 'Sangat sering (>10)'),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 12,
                    decoration: BoxDecoration(
                      color: C.grayInk.withValues(alpha: a + .1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(label, style: t(12, w5, C.sub)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Kejadian dalam 12 bulan. Berdasarkan kejadian tercatat di SIGAP Banjir${Api.riskSince.isEmpty ? '' : ' sejak ${Api.riskSince}'}.',
          style: t(11, FontWeight.w400, C.muted, 1.4),
        ),
      ],
    ),
  );
}

class _ForecastCard extends StatelessWidget {
  final String? rainLine;
  const _ForecastCard(this.rainLine, {super.key});

  @override
  Widget build(BuildContext context) {
    final f = app.forecast;
    final now = f?.slots.first;
    return Tap(
      onTap: () => app.go(Scr.forecast),
      radius: 26,
      gradient: gBlueSoft,
      shadow: soft(.35, 30, 18, C.blue),
      label: 'Buka prakiraan',
      padding: const EdgeInsets.fromLTRB(8, 6, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 76,
            child: Row(
              children: [
                WxAnim(now?.kind ?? 'cloud', size: 76),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        now == null
                            ? 'Memuat prakiraan…'
                            : '${now.desc} · ${now.temp}°',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t(17, w6, Colors.white),
                      ),
                      Text(
                        'Kec. ${app.district} · ${f == null
                            ? 'BMKG'
                            : app.fcStale
                            ? 'Data tersimpan ${hm(f.fetchedAt)}'
                            : 'BMKG, diambil ${hm(f.fetchedAt)}'}',
                        maxLines: 2,
                        style: t(12, FontWeight.w400, Colors.white),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: Colors.white.withValues(alpha: .4),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${app.nearby.length}',
                        style: t(26, w7, Colors.white, 1),
                      ),
                      Text(
                        'titik\ntergenang',
                        textAlign: TextAlign.center,
                        style: t(10, FontWeight.w400, Colors.white, 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (rainLine != null)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 4, 0, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .95),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: C.violetInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(rainLine!, style: t(12, w5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// US-11: radar 2 jam terakhir, slider + putar, keterangan + kredit Rain Viewer.
class _RadarCard extends StatelessWidget {
  const _RadarCard({super.key});

  @override
  Widget build(BuildContext context) {
    final st = app.radarState, r = app.radar;
    final ready = st == 'ready' && r != null;
    final last = ready ? r.frames.length - 1 : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: soft(.22, 30, 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 20, color: C.violetInk),
              const SizedBox(width: 8),
              Expanded(child: Text('Radar hujan', style: t(14, w6))),
              if (ready)
                Pill(
                  '${hm(r.frames[app.radarFrame].time)}${app.radarFrame == last ? ' · terbaru' : ''}',
                  C.violetTint,
                  C.violetInk,
                  size: 12,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (ready)
            Row(
              children: [
                SquareBtn(
                  app.radarPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  bg: C.violetInk,
                  fg: Colors.white,
                  shadowed: false,
                  label: app.radarPlaying ? 'Jeda radar' : 'Putar radar',
                  onTap: app.toggleRadarPlay,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Slider(
                        value: app.radarFrame.toDouble(),
                        max: last.toDouble(),
                        divisions: math.max(1, last),
                        label: hm(r.frames[app.radarFrame].time),
                        onChanged: (v) {
                          app.stopRadar();
                          app.set(() => app.radarFrame = v.round());
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              hm(r.frames.first.time),
                              style: t(
                                11,
                                FontWeight.w400,
                                const Color(0xFF5E6478),
                              ),
                            ),
                            Text(
                              hm(r.frames.last.time),
                              style: t(
                                11,
                                FontWeight.w400,
                                const Color(0xFF5E6478),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else if (st == 'unavailable')
            Row(
              children: [
                const IconTile(
                  Icons.cloud_off_rounded,
                  C.grayTint,
                  C.grayInk,
                  size: 48,
                  iconSize: 24,
                  radius: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Radar sedang tidak tersedia. Peta lain tetap berjalan.',
                    style: t(13, FontWeight.w400, C.ink, 1.45),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: C.line,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: C.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Memuat radar…',
                        style: t(13, FontWeight.w400, C.body),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            'Menunjukkan hujan yang sudah terjadi, bukan perkiraan ke depan.',
            style: t(12, FontWeight.w400, C.body, 1.45),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: C.line),
          Row(
            children: [
              if (ready)
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    children: [
                      for (final (c, l) in const [
                        (C.blueLight, 'Ringan'),
                        (C.blue, 'Sedang'),
                        (C.violet, 'Lebat'),
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(l, style: t(12, FontWeight.w400, C.sub)),
                          ],
                        ),
                    ],
                  ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.rainviewer.com'),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  'Weather data by Rain Viewer',
                  style: t(11, w5, C.blueInk),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// M03: detail lokasi (bottom sheet).
class PointSheet extends StatelessWidget {
  final int id;
  const PointSheet(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = app.points.firstWhere((x) => x.id == id);
    final d = depths[p.depth],
        v = vers[p.verification]!,
        rec = p.receded,
        watched = app.watchOf(p) != null;
    final extent = p.segmentLengthM != null
        ? 'Ruas ± ${p.segmentLengthM} m'
        : 'Titik laporan';
    return _Sheet(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: t(20, w7, C.ink, 1.25)),
                  const SizedBox(height: 2),
                  Text(
                    'Kec. ${p.district} · $extent',
                    style: t(13, FontWeight.w400, C.muted),
                  ),
                ],
              ),
            ),
            SquareBtn(
              Icons.close_rounded,
              size: 44,
              bg: C.bg,
              shadowed: false,
              label: 'Tutup',
              onTap: app.back,
            ),
          ],
        ),
        if (p.stale)
          Note(
            'Belum ada pembaruan lebih dari ${Api.staleHours} jam. Kondisi bisa sudah berubah.',
            bold: 'Perlu Konfirmasi.',
            icon: Icons.schedule_rounded,
          ),
        if (rec)
          Note(
            'sejak pukul ${hm(p.recededAt!)}. Jalan bisa dilalui lagi.',
            bold: 'Sudah Surut',
            icon: Icons.check_circle_rounded,
            bg: C.greenTint,
            fg: C.green,
          ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: d.tint,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              DepthFig(p.depth, size: 78),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: d.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(d.level, style: t(12, w6, d.ink)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rec ? 'Sudah Surut' : d.label,
                      style: t(24, w7, d.ink, 1.15),
                    ),
                    Text(rec ? 'Genangan 0 cm' : d.cm, style: t(14, w5, d.ink)),
                    const SizedBox(height: 4),
                    Text(
                      rec ? 'Jalan bisa dilalui lagi' : d.meaning,
                      style: t(13, FontWeight.w400, C.sub, 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _Info(
                'Diperbarui',
                rec ? 'Surut ${hm(p.recededAt!)}' : ago(p.updatedAt),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Info(
                'Sumber',
                '${p.source}${p.reportCount > 0 ? ' (${p.reportCount} laporan)' : ''}',
              ),
            ),
          ],
        ),
        // US-12: hanya jika ≥ 5 kejadian; tidak pernah mengubah status.
        if (p.estimate != null && !rec)
          _Row(
            Icons.hourglass_bottom_rounded,
            'Biasanya surut dalam ±${p.estimate!.medianHours} jam',
            'dari ${p.estimate!.sample} kejadian sebelumnya di titik ini',
            note:
                'Perkiraan dari riwayat, bukan prediksi resmi. Cek status terbaru sebelum melintas.',
          ),
        _History(p),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: v.tint, width: 1.5),
          ),
          child: Row(
            children: [
              IconTile(
                v.icon,
                v.tint,
                v.color,
                size: 36,
                iconSize: 20,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.label, style: t(14, w6, v.color)),
                    Text(v.desc, style: t(12, FontWeight.w400, C.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Photos(p.id),
        if (p.depth >= 3 && !rec)
          Tap(
            onTap: () => app.openGuide(1),
            radius: 18,
            color: C.redTint,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.menu_book_rounded, size: 20, color: C.redInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lihat panduan saat banjir',
                    style: t(14, w6, C.redInk),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: C.redInk),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 10,
              child: Btn(
                watched ? 'Dipantau' : 'Pantau',
                icon: watched
                    ? Icons.notifications_active_rounded
                    : Icons.notification_add_rounded,
                height: 52,
                radius: 18,
                fontSize: 14,
                color: watched ? C.violetTint : C.bg,
                fg: watched ? C.violetInk : C.ink,
                onTap: () => app.toggleWatchPoint(p),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 13,
              child: Btn(
                'Buka di Google Maps',
                icon: Icons.open_in_new_rounded,
                height: 52,
                radius: 18,
                fontSize: 14,
                gradient: gBlue,
                shadow: soft(.3, 20, 10, C.blue),
                onTap: () => app.directions(p.pos),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Btn(
                'Bagikan',
                icon: Icons.share_rounded,
                height: 48,
                fontSize: 14,
                fg: C.blueInk,
                onTap: () => app.share(p),
              ),
            ),
            Expanded(
              flex: 2,
              child: Btn(
                'Laporkan kondisi terbaru',
                icon: Icons.add_a_photo_rounded,
                height: 48,
                fontSize: 14,
                fg: C.violetMid,
                onTap: () => app.openReport(p),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  final String label, value;
  const _Info(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.bg,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t(11, w5, C.muted)),
        const SizedBox(height: 4),
        Text(value, style: t(14, w6, C.ink, 1.3)),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final String? note;
  final Widget? extra;
  const _Row(this.icon, this.title, this.sub, {this.note, this.extra});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: C.bg,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(
          icon,
          C.violetTint,
          C.violetInk,
          size: 36,
          iconSize: 20,
          radius: 12,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t(14, w6)),
              Text(sub, style: t(12, FontWeight.w400, C.sub)),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    note!,
                    style: t(
                      11,
                      FontWeight.w400,
                      const Color(0xFF5E6478),
                      1.45,
                    ),
                  ),
                ),
              ?extra,
            ],
          ),
        ),
      ],
    ),
  );
}

/// US-13: ringkasan riwayat + grafik batang per bulan.
class _History extends StatelessWidget {
  final FloodPoint p;
  const _History(this.p);

  @override
  Widget build(BuildContext context) {
    final h = p.history;
    if (h == null) {
      return const _Row(
        Icons.bar_chart_rounded,
        'Riwayat',
        'Belum ada riwayat tercatat',
      );
    }
    final top = h.monthly.reduce(math.max).clamp(1, 99);
    final now = DateTime.now();
    final first = months[(now.month - 12) % 12];
    return _Row(
      Icons.bar_chart_rounded,
      'Riwayat 12 bulan',
      'Terakhir tergenang ${ago(h.last)} · ${h.count12m} kali dalam 12 bulan',
      extra: Semantics(
        label: 'Grafik kejadian per bulan, total ${h.count12m} kejadian',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final c in h.monthly)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            height: c == 0 ? 3 : 6 + 30 * c / top,
                            decoration: BoxDecoration(
                              color: c == 0 ? C.field : C.violet,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(first, style: t(10, FontWeight.w400, C.muted)),
                    Text('Bulan ini', style: t(10, FontWeight.w400, C.muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Foto dari laporan yang sudah disetujui saja (privasi pelapor).
class _Photos extends StatelessWidget {
  final int pointId;
  const _Photos(this.pointId);

  static final _cache = <int, Future<List<String>>>{};

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _cache[pointId] ??= Api.pointPhotos(
      pointId,
    ).catchError((_) => <String>[]),
    builder: (context, snap) {
      final urls = snap.data ?? const <String>[];
      if (urls.isEmpty) return const SizedBox.shrink();
      return Row(
        children: [
          for (final u in urls.take(2)) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  u,
                  height: 84,
                  fit: BoxFit.cover,
                  semanticLabel: 'Foto laporan',
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: urls.length > 2
                ? Container(
                    height: 84,
                    decoration: BoxDecoration(
                      color: C.bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        '+${urls.length - 2}',
                        style: t(13, w6, C.body),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    },
  );
}

/// Detail posko / faskes.
class ShelterSheet extends StatelessWidget {
  final String id;
  const ShelterSheet(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = app.shelters.firstWhere((x) => x.id == id);
    final posko = s.type == 'posko', full = s.status == 'full';
    return _Sheet(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              posko
                  ? Icons.night_shelter_rounded
                  : Icons.local_hospital_rounded,
              posko ? C.violetTint : C.blueTint2,
              posko ? C.violetMid : C.blueInk,
              size: 52,
              iconSize: 26,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    posko ? 'Posko pengungsian' : 'Fasilitas kesehatan',
                    style: t(12, w5, C.muted),
                  ),
                  Text(s.name, style: t(19, w7, C.ink, 1.25)),
                ],
              ),
            ),
            SquareBtn(
              Icons.close_rounded,
              size: 44,
              bg: C.bg,
              shadowed: false,
              label: 'Tutup',
              onTap: app.back,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(
              full ? 'Penuh' : 'Buka',
              full ? C.redTint : C.greenTint,
              full ? C.redInk : C.green,
              size: 12,
            ),
            Pill(
              '${km(meters(app.center, s.pos))} dari ${app.userPos == null ? 'Balai Kota' : 'lokasimu'}',
              C.bg,
              C.sub,
              size: 12,
            ),
            if (s.note != null) Pill(s.note!, C.bg, C.sub, size: 12),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_rounded, size: 20, color: C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.address, style: t(13, FontWeight.w400, C.sub, 1.5)),
            ),
          ],
        ),
        Row(
          children: [
            if (s.phone != null) ...[
              Expanded(
                flex: 10,
                child: Btn(
                  'Telepon',
                  icon: Icons.call_rounded,
                  height: 52,
                  radius: 18,
                  fontSize: 14,
                  color: C.greenTint,
                  fg: C.green,
                  onTap: () => app.call(s.phone!),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 13,
              child: Btn(
                'Arahkan',
                icon: Icons.directions_rounded,
                height: 52,
                radius: 18,
                fontSize: 14,
                gradient: gBlue,
                shadow: soft(.3, 20, 10, C.blue),
                onTap: () => app.directions(s.pos),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  final List<Widget> children;
  const _Sheet({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .88,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      boxShadow: soft(.15, 40, -20, C.ink),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Area gagang di luar scroll: tarik ke bawah untuk menutup (lihat DragToDismiss di Shell).
        Semantics(
          label: 'Tarik ke bawah untuk menutup',
          child: SizedBox(
            height: 24,
            child: Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3EE),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + bottomInset(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in children.indexed) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Appear(index: i, child: c),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Jam saja untuk hari ini; tanggal ikut jika data dari hari sebelumnya (cache setelah aplikasi ditutup).
String _when(DateTime d) {
  final n = DateTime.now();
  final today = d.year == n.year && d.month == n.month && d.day == n.day;
  return today ? hm(d) : '${d.day} ${months[d.month - 1]} ${hm(d)}';
}
