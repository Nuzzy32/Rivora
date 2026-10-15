import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';
import 'weather_cards.dart';

/// Latar mengikuti suasana slot terpilih (dekoratif; berpindah pelan).
/// Hujan: langit gelap berawan (badai paling gelap), kartu kaca tetap terbaca dengan teks putih.
List<Color> _mood(String kind) => switch (kind) {
  'heavy' ||
  'storm' => const [Color(0xFF3A4152), Color(0xFF232836), Color(0xFF14171F)],
  'rain' || 'nightrain' => const [
    Color(0xFF5B6679),
    Color(0xFF3B4456),
    Color(0xFF272D3A),
  ],
  'nightcloud' => const [
    Color(0xFF41509A),
    Color(0xFF283574),
    Color(0xFF1B2151),
  ],
  'sun' ||
  'partly' => const [Color(0xFFA9D0FF), Color(0xFF5DA0FD), Color(0xFF7C9BF7)],
  _ => const [Color(0xFF9FC3FF), C.blue, Color(0xFF6C86F6)],
};

/// M08: prakiraan BMKG per 3 jam untuk kecamatan terpilih.
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  final _sc = ScrollController();

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  // Header ikut membesar bila ukuran huruf sistem diperbesar.
  double get _heroMax =>
      280 + (MediaQuery.textScalerOf(context).scale(10) / 10 - 1) * 320;
  double get _heroMin =>
      96 + (MediaQuery.textScalerOf(context).scale(10) / 10 - 1) * 60;

  @override
  Widget build(BuildContext context) {
    final f = app.forecast;
    final loading = app.fcLoading || f == null || f.slots.isEmpty;
    final cur = loading ? null : f.slots.first;
    final top = topInset(context);
    return AnimatedContainer(
      duration: dur(context, 700),
      curve: easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-.3, -1),
          end: const Alignment(.3, 1),
          colors: _mood(cur?.kind ?? 'cloud'),
          stops: const [0, .52, 1],
        ),
      ),
      child: Stack(
        children: [
          // Langit bergerak sesuai cuaca sekarang (matahari, awan, bintang, hujan, kilat).
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: dur(context, 700),
                child: cur == null
                    ? const SizedBox.shrink()
                    : _Sky(key: ValueKey(cur.kind), kind: cur.kind),
              ),
            ),
          ),
          // Kartu bergulir di bawah header dan terpotong tepat di tepi bawahnya (gaya Cuaca iPhone).
          AnimatedBuilder(
            animation: _sc,
            builder: (context, child) {
              final o = _sc.hasClients ? _sc.offset : 0.0;
              final h = top + math.max(_heroMin, _heroMax - o);
              return ClipRect(clipper: _Below(h), child: child);
            },
            child: ListView(
              controller: _sc,
              padding: EdgeInsets.fromLTRB(
                16,
                top + _heroMax,
                16,
                tabSpace(context),
              ),
              children: loading ? [_loadingCard()] : _cards(f, cur!),
            ),
          ),
          // Header: menyusut dari besar ke satu baris saat digulir; seret header ikut menggulir.
          AnimatedBuilder(
            animation: _sc,
            builder: (context, _) {
              final o = _sc.hasClients ? _sc.offset : 0.0;
              final p = (o / (_heroMax - _heroMin)).clamp(0.0, 1.0);
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top + math.max(_heroMin, _heroMax - o),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (d) {
                    if (!_sc.hasClients) return;
                    _sc.jumpTo(
                      (_sc.offset - d.delta.dy).clamp(
                        0,
                        _sc.position.maxScrollExtent,
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(top: top + 6),
                    child: _hero(f, cur, p),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Tertinggi/terendah hari ini dari slot BMKG hari ini (cadangan: Open-Meteo).
  ({int hi, int lo})? _range(Forecast f) {
    final today = f.local(DateTime.now()).day;
    final t = [
      for (final s in f.slots)
        if (f.local(s.time).day == today) s.temp,
    ];
    final d0 = f.extra?.days.firstOrNull;
    if (d0 != null) t.addAll([d0.tmin, d0.tmax]);
    return t.isEmpty ? null : (hi: t.reduce(math.max), lo: t.reduce(math.min));
  }

  Widget _hero(Forecast? f, Slot? cur, double p) {
    final place = app.fcPlace;
    final caption = place == null
        ? 'PRAKIRAAN BMKG'
        : app.fcAuto
        ? 'LOKASIKU'
        : (place.tag ?? 'Lokasi pilihan').toUpperCase();
    final full = 1 - (p / .55).clamp(0.0, 1.0);
    final mini = ((p - .6) / .4).clamp(0.0, 1.0);
    final r = f == null ? null : _range(f);
    final shadow = [
      Shadow(color: Colors.black.withValues(alpha: .18), blurRadius: 12),
    ];
    TextStyle s(double size, FontWeight w) =>
        t(size, w, Colors.white, 1.1).copyWith(shadows: shadow);
    // Isi melebihi tinggi header saat menyusut: dipotong, bukan meluap.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Pilih lokasi prakiraan',
            child: GestureDetector(
              onTap: () => _pickPlace(context),
              child: Column(
                children: [
                  Opacity(
                    opacity: full,
                    child: Text(
                      caption,
                      style: s(13, w6).copyWith(letterSpacing: .6),
                    ),
                  ),
                  // Nama tepat di tengah; panah "menggantung" di kanan (penyeimbang tak terlihat di kiri).
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 24),
                      Flexible(
                        child: Text(
                          place?.name ?? 'Pilih lokasi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: s(lerpDouble(34, 26, p)!, FontWeight.w500),
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (cur != null && full > 0)
            Opacity(
              opacity: full,
              child: Column(
                children: [
                  // Angka di tengah, ° menggantung di kanan seperti iPhone.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '°',
                        style: s(96, FontWeight.w300).copyWith(
                          height: 1.05,
                          color: Colors.transparent,
                          shadows: const [],
                        ),
                      ),
                      Text(
                        '${cur.temp}°',
                        style: s(96, FontWeight.w300).copyWith(height: 1.05),
                      ),
                    ],
                  ),
                  Text(cur.desc, style: s(20, FontWeight.w500)),
                  if (r != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'T: ${r.hi}°   R: ${r.lo}°',
                        style: s(18, FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
          if (cur != null && mini > 0)
            Opacity(
              opacity: mini,
              child: Text(
                '${cur.temp}°  |  ${cur.desc}',
                style: s(
                  18,
                  FontWeight.w500,
                ).copyWith(color: Colors.white.withValues(alpha: .85)),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _cards(Forecast f, Slot cur) {
    final e = f.extra;
    final rain24 = f.slots.take(8).fold(0.0, (a, s) => a + s.rainMm);
    String mm(double v) =>
        '${v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',')} mm';
    final range = _range(f);
    const om = 'Sumber: Open-Meteo';
    final gap = const SizedBox(height: 12);
    return [
      if (app.fcStale) ...[
        Note(
          'Gagal memuat data terbaru. Menampilkan prakiraan tersimpan pukul ${f.at(f.fetchedAt)} ${f.zone}.',
          icon: Icons.cloud_off_rounded,
          bg: C.ink,
          fg: Colors.white,
        ),
        gap,
      ],
      if (f.warning != null && !app.fcStale) ...[
        WxCard(
          icon: Icons.warning_amber_rounded,
          label: 'Peringatan dini BMKG',
          child: Text(f.warning!, style: t(14, w5, Colors.white, 1.45)),
        ),
        gap,
      ],
      HourlyCard(f),
      gap,
      if (e != null && e.days.isNotEmpty) ...[
        DailyCard(e.days, nowTemp: cur.temp),
        gap,
      ],
      wxPair(
        WxTile(
          icon: Icons.water_drop_rounded,
          label: 'Curah hujan',
          value: mm(rain24),
          sub: '24 jam ke depan',
          note: rain24 < .5
              ? 'Tidak diperkirakan hujan berarti.'
              : f.rainLine ?? 'Waspadai genangan di titik rawan.',
        ),
        WxTile(
          icon: Icons.thermostat_rounded,
          label: 'Terasa seperti',
          value: '${cur.feels}°',
          note: feelsNote(cur.feels, cur.temp),
        ),
      ),
      gap,
      if (e?.uv != null || e?.sunrise != null) ...[
        wxPair(
          e?.uv == null
              ? null
              : WxTile(
                  icon: Icons.wb_sunny_rounded,
                  label: 'Indeks UV',
                  value: '${e!.uv}',
                  sub: uvLevel(e.uv!).level,
                  art: UvBar(e.uv!),
                  note: uvLevel(e.uv!).note,
                  source: om,
                ),
          e?.sunrise == null || e?.sunset == null
              ? null
              : SunCard(e!.sunrise!, e.sunset!, f.local(DateTime.now())),
        ),
        gap,
      ],
      if (cur.windDir != null) ...[WindCard(cur), gap],
      wxPair(
        WxTile(
          icon: Icons.water_rounded,
          label: 'Kelembapan',
          value: '${cur.hum}%',
          note: 'Titik embun ${dewPoint(cur.temp, cur.hum)}° saat ini.',
        ),
        e?.visibilityM == null
            ? null
            : WxTile(
                icon: Icons.visibility_rounded,
                label: 'Jarak pandang',
                value: '${(e!.visibilityM! / 1000).round()} km',
                note: e.visibilityM! >= 10000
                    ? 'Pandangan sangat jelas.'
                    : e.visibilityM! >= 4000
                    ? 'Pandangan cukup jelas.'
                    : 'Pandangan terbatas, hati-hati berkendara.',
                source: om,
              ),
      ),
      gap,
      wxPair(
        e?.pressure == null
            ? null
            : WxTile(
                icon: Icons.speed_rounded,
                label: 'Tekanan udara',
                value: '${e!.pressure}',
                sub: 'hPa',
                art: PressureArt(e.pressure!),
                source: om,
              ),
        e?.avgHigh == null || range == null
            ? null
            : WxTile(
                icon: Icons.show_chart_rounded,
                label: 'Rata-rata',
                value:
                    '${range.hi - e!.avgHigh! >= 0 ? '+' : ''}${range.hi - e.avgHigh!}°',
                sub: range.hi > e.avgHigh!
                    ? 'di atas rata-rata'
                    : range.hi < e.avgHigh!
                    ? 'di bawah rata-rata'
                    : 'sama dengan rata-rata',
                note:
                    'Hari ini T: ${range.hi}°\nRata-rata 10 thn T: ${e.avgHigh}°',
                source: om,
              ),
      ),
      gap,
      if (cur.cloud != null) ...[
        wxPair(
          WxTile(
            icon: Icons.cloud_rounded,
            label: 'Tutupan awan',
            value: '${cur.cloud}%',
            note: cur.cloud! >= 75
                ? 'Langit tertutup awan.'
                : cur.cloud! >= 40
                ? 'Berawan sebagian.'
                : 'Langit cenderung cerah.',
          ),
          null,
        ),
        gap,
      ],
      MoonCard(DateTime.now()),
      gap,
      Box(
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_rounded, size: 20, color: C.violetMid),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sumber: BMKG · ${app.fcStale ? 'data tersimpan' : 'diambil'} ${f.at(f.fetchedAt)} ${f.zone}',
                    style: t(13, w6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Suhu, hujan, angin, kelembapan, awan, dan peringatan dari BMKG. UV, tekanan, jarak pandang, matahari, '
              '10 hari, dan rata-rata dari Open-Meteo (CC BY 4.0). Fase bulan dihitung di perangkat. '
              'Prakiraan ini bukan prediksi banjir: untuk kondisi jalan, lihat laporan di Peta.',
              style: t(13, FontWeight.w400, C.body, 1.55),
            ),
            const SizedBox(height: 12),
            Btn(
              'Cek genangan di Peta',
              icon: Icons.map_outlined,
              height: 48,
              radius: 16,
              fontSize: 14,
              color: C.blueTint,
              fg: C.blueMid,
              onTap: () => app.go(Scr.map),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _loadingCard() => SizedBox(
    key: const ValueKey('loading'),
    height: 262,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Shimmer(
          base: Colors.white.withValues(alpha: .35),
          glow: Colors.white.withValues(alpha: .75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_skel(.6), const SizedBox(height: 14), _skel(.4)],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          app.fcPlace == null
              ? 'Pilih lokasi untuk melihat prakiraan BMKG di mana pun di Indonesia.'
              : app.fcLoading
              ? 'Memuat prakiraan ${app.fcPlace!.name}…'
              : 'Prakiraan ${app.fcPlace!.name} belum tersedia. Coba lagi sebentar lagi.',
          style: t(13, w5, Colors.white),
        ),
        if (app.fcPlace == null && !app.fcLoading) ...[
          const SizedBox(height: 12),
          Btn(
            'Gunakan lokasi saat ini',
            icon: Icons.near_me_rounded,
            height: 44,
            radius: 14,
            fontSize: 14,
            color: Colors.white,
            fg: C.blueMid,
            onTap: app.useMyLocation,
          ),
        ],
      ],
    ),
  );

  Widget _skel(double w) => FractionallySizedBox(
    widthFactor: w,
    child: Container(
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );

  void _pickPlace(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (_) => const _PlaceSheet(),
  );
}

/// Potong isi gulir di atas tepi bawah header.
class _Below extends CustomClipper<Rect> {
  final double top;
  _Below(this.top);
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);
  @override
  bool shouldReclip(_Below old) => old.top != top;
}

/// Langit di belakang layar Prakiraan, sesuai jenis cuaca BMKG (lihat `kind` di bmkg-forecast):
/// sun, partly, cloud, nightcloud, rain, nightrain, heavy, storm.
/// "Kurangi Gerakan" aktif = gambar diam tanpa kilat.
class _Sky extends StatefulWidget {
  final String kind;
  const _Sky({super.key, required this.kind});

  @override
  State<_Sky> createState() => _SkyState();
}

// Waktu berjalan terus (detik), bukan siklus yang diulang: tidak ada titik "lompat" saat loop.
class _SkyState extends State<_Sky> with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final _ticker = createTicker(
    (e) => _time.value = e.inMicroseconds / 1e6,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduced(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _SkyPainter(_time, widget.kind),
      size: Size.infinite,
    ),
  );
}

/// Tampilan awan per cuaca: jumlah lapis, warna lapis belakang → depan, posisi atas, kepekatan.
typedef _Clouds = (
  int layers,
  Color back,
  Color front,
  double top,
  double alpha,
);

class _SkyPainter extends CustomPainter {
  final ValueListenable<double> time;
  final String kind;
  _SkyPainter(this.time, this.kind) : super(repaint: time);

  // Kilat badai (detik dalam tiap 14 detik): dua kedipan beruntun lalu satu kedipan.
  static const _flashes = [(4.2, 4.37), (4.56, 4.7), (10.9, 11.06)];

  // Awan cerah sengaja kebiruan & mulai di bawah chip jam (di belakang kartu kaca), supaya
  // judul dan angka putih di atasnya tetap terbaca.
  static const _fair = Color(0xFFB9CDF0), _fairBack = Color(0xFFDCE7FA);

  _Clouds? get _clouds => switch (kind) {
    'partly' => (2, _fairBack, _fair, 330.0, .4),
    'cloud' => (3, _fairBack, _fair, 310.0, .42),
    'nightcloud' => (
      2,
      const Color(0xFF7D8CC4),
      const Color(0xFF46538C),
      330.0,
      .45,
    ),
    'rain' || 'nightrain' => (
      4,
      const Color(0xFF7A8496),
      const Color(0xFF2A303C),
      10.0,
      .8,
    ),
    'heavy' ||
    'storm' => (4, const Color(0xFF6B7588), const Color(0xFF1B2029), 10.0, .85),
    _ => null, // sun: langit bersih
  };

  @override
  void paint(Canvas canvas, Size size) {
    final v = time.value, w = size.width;
    if (kind == 'sun' || kind == 'partly') _sun(canvas, size, v);
    if (kind == 'nightcloud' || kind == 'nightrain') _night(canvas, size, v);
    if (_clouds case final c?) _drawClouds(canvas, w, v, c);
    switch (kind) {
      case 'rain' || 'nightrain':
        _rain(canvas, size, v, 60);
      case 'heavy':
        _rain(canvas, size, v, 110);
      case 'storm':
        _rain(canvas, size, v, 110);
        _lightning(canvas, size, v);
    }
  }

  /// Cahaya matahari di kanan atas: pancaran hangat yang berdenyut + sinar berputar pelan.
  void _sun(Canvas canvas, Size size, double v) {
    final c = Offset(size.width * .82, 110);
    final pulse = 1 + .05 * math.sin(v * .9);
    canvas.drawCircle(
      c,
      240 * pulse,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF4C9).withValues(alpha: .75),
            const Color(0xFFFFE08A).withValues(alpha: .25),
            const Color(0x00FFE08A),
          ],
          stops: const [0, .35, 1],
        ).createShader(Rect.fromCircle(center: c, radius: 240 * pulse)),
    );
    final ray = Paint()..color = Colors.white.withValues(alpha: .10);
    for (var i = 0; i < 10; i++) {
      final a = v * .06 + i * math.pi / 5;
      final p = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - .05) * 420, c.dy + math.sin(a - .05) * 420)
        ..lineTo(c.dx + math.cos(a + .05) * 420, c.dy + math.sin(a + .05) * 420)
        ..close();
      canvas.drawPath(p, ray);
    }
  }

  /// Malam: bintang berkelip (posisi tetap) dan cahaya bulan di kanan atas.
  void _night(Canvas canvas, Size size, double v) {
    final moon = Offset(size.width * .82, 120);
    canvas.drawCircle(
      moon,
      170,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE4E9FF).withValues(alpha: .45),
            const Color(0x00E4E9FF),
          ],
        ).createShader(Rect.fromCircle(center: moon, radius: 170)),
    );
    if (kind == 'nightrain') return; // hujan: bintang tertutup awan
    final rnd = math.Random(3);
    for (var i = 0; i < 55; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height * .6,
      );
      final phase = rnd.nextDouble() * math.pi * 2;
      final speed = 1.2 + rnd.nextDouble() * 1.6;
      final tw = .35 + .55 * (.5 + .5 * math.sin(v * speed + phase));
      canvas.drawCircle(
        p,
        .7 + rnd.nextDouble() * 1.1,
        Paint()..color = Colors.white.withValues(alpha: tw),
      );
    }
  }

  /// Lapis belakang lebih terang & lambat, lapis depan lebih gelap & cepat. Tiap gumpalan
  /// digambar dua kali: tepi atas terang (kena cahaya) lalu badan awan di atasnya.
  void _drawClouds(Canvas canvas, double w, double v, _Clouds c) {
    final (layers, back, front, top, alpha) = c;
    for (var layer = 0; layer < layers; layer++) {
      final body = Color.lerp(
        back,
        front,
        layers == 1 ? 0 : layer / (layers - 1),
      )!;
      final rim = Paint()
        ..color = Color.lerp(
          body,
          Colors.white,
          .45,
        )!.withValues(alpha: alpha * .65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      final fill = Paint()
        ..color = body.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 - layer * 2.0);
      // Gumpalan selebar ±3r; muncul ulang di kiri hanya setelah keluar penuh di kanan.
      const edge = 340.0;
      final span = w + edge * 2;
      final shift = v * (9 + layer * 6);
      for (var i = 0; i < 3; i++) {
        final x = (i * span / 3 + layer * 110 + shift) % span - edge;
        final y = top + layer * 120 + (i.isEven ? 0 : 50);
        final r = 70 + layer * 12.0;
        _cloud(canvas, Offset(x, y - r * .12), r, rim);
        _cloud(canvas, Offset(x, y), r, fill);
      }
    }
  }

  /// Hujan: posisi acak tetap (seed sama) yang turun miring.
  void _rain(Canvas canvas, Size size, double v, int count) {
    final rnd = math.Random(7);
    final rain = Paint()
      ..color = Colors.white.withValues(alpha: .22)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final speed = 420 + rnd.nextDouble() * 260; // px/detik
      final len = 12 + rnd.nextDouble() * 12;
      final y =
          (rnd.nextDouble() * size.height + v * speed) % (size.height + 40) -
          40;
      canvas.drawLine(Offset(x, y), Offset(x - len * .25, y + len), rain);
    }
  }

  void _lightning(Canvas canvas, Size size, double v) {
    final w = size.width;
    final at = v % 14;
    for (final (a, b) in _flashes) {
      if (at < a || at > b) continue;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: .14),
      );
      final bolt = Path()
        ..moveTo(w * .72, 70)
        ..lineTo(w * .66, 150)
        ..lineTo(w * .71, 150)
        ..lineTo(w * .63, 250);
      canvas.drawPath(
        bolt,
        Paint()
          ..color = const Color(0xFFFFF3C4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4),
      );
    }
  }

  void _cloud(Canvas c, Offset o, double r, Paint p) {
    c.drawCircle(o, r, p);
    c.drawCircle(o + Offset(r * .9, -r * .38), r * .82, p);
    c.drawCircle(o + Offset(r * 1.8, 0), r * .9, p);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx - r * .6, o.dy, r * 3, r * .8),
        Radius.circular(r * .4),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.kind != kind;
}

/// Pilih lokasi prakiraan se-Indonesia: lokasi saat ini (GPS), cari kelurahan/kecamatan/kota, atau favorit.
class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet();

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  final _q = TextEditingController();
  Timer? _wait;
  List<Place>? _hits;
  String? _err;

  @override
  void dispose() {
    _wait?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _wait?.cancel();
    if (q.trim().length < 3) {
      _hits = _err = null;
      return;
    }
    _wait = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Api.searchRegions(q);
        if (mounted && _q.text == q) {
          setState(() {
            _hits = r;
            _err = null;
          });
        }
      } on ApiError catch (e) {
        if (mounted) {
          setState(() {
            _hits = null;
            _err = e.message;
          });
        }
      }
    });
  }

  void _pick(Place p) {
    Navigator.pop(context);
    app.loadForecast(app.favs.where((f) => f.adm4 == p.adm4).firstOrNull ?? p);
  }

  Future<void> _star(Place p) async {
    if (app.isFav(p)) return setState(() => app.toggleFav(p));
    final tag = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Simpan sebagai favorit', style: t(17, w7)),
              const SizedBox(height: 2),
              Text(
                p.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t(13, FontWeight.w400, C.muted),
              ),
              const SizedBox(height: 12),
              for (final l in const [
                'Rumah',
                'Kantor',
                'Kampus',
                'Sekolah',
                'Lainnya',
              ])
                Tap(
                  onTap: () => Navigator.pop(ctx, l),
                  height: 56,
                  radius: 16,
                  label: 'Simpan sebagai $l',
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconTile(
                        _tagIcon(l),
                        C.blueTint,
                        C.blueInk,
                        size: 40,
                        iconSize: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l, style: t(15, w6))),
                      const Icon(Icons.chevron_right_rounded, color: C.faint),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (tag != null) {
      setState(() => app.toggleFav(p, tag == 'Lainnya' ? null : tag));
    }
  }

  Widget _tile(
    Place p, {
    IconData icon = Icons.location_on_outlined,
    String? title,
  }) {
    final on = app.fcPlace?.adm4 == p.adm4;
    final fav = app.isFav(p);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tap(
        onTap: () => _pick(p),
        radius: 16,
        color: on ? C.blueTint : Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        label: '${title ?? p.name}, ${p.sub}',
        child: Row(
          children: [
            Icon(icon, size: 22, color: on ? C.blue : C.sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title ?? p.name, style: t(14, w6)),
                  Text(
                    p.sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t(12, FontWeight.w400, C.muted),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: fav ? 'Hapus dari favorit' : 'Simpan sebagai favorit',
              child: IconButton(
                onPressed: () => _star(p),
                icon: Icon(
                  fav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: fav ? const Color(0xFFF4B92F) : C.faint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.text.trim().length >= 3;
    final here = app.fcAuto ? app.fcPlace : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE3EE),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                child: Text('Lokasi prakiraan', style: t(17, w7)),
              ),
              Container(
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: C.bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 22, color: C.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _q,
                        onChanged: (v) => setState(() => _search(v)),
                        textInputAction: TextInputAction.search,
                        style: t(14),
                        decoration: InputDecoration.collapsed(
                          hintText: 'Cari kelurahan, kecamatan, atau kota',
                          hintStyle: t(14, FontWeight.w400, C.faint),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: searching
                      ? [
                          if (_err != null)
                            Note(_err!, icon: Icons.cloud_off_rounded)
                          else if (_hits == null)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_hits!.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Tidak ditemukan. Coba nama kelurahan, kecamatan, atau kota lain.',
                                textAlign: TextAlign.center,
                                style: t(13, FontWeight.w400, C.muted),
                              ),
                            ),
                          for (final p in _hits ?? const <Place>[]) _tile(p),
                        ]
                      : [
                          // Lokasi saat ini: mengikuti GPS sampai pengguna memilih lokasi lain.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Tap(
                              onTap: () {
                                Navigator.pop(context);
                                app.useMyLocation();
                              },
                              radius: 16,
                              color: app.fcAuto ? C.blueTint : Colors.white,
                              padding: const EdgeInsets.all(12),
                              label: 'Gunakan lokasi saat ini',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.near_me_rounded,
                                    size: 22,
                                    color: app.fcAuto ? C.blue : C.sub,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Lokasi saat ini',
                                          style: t(14, w6),
                                        ),
                                        Text(
                                          here != null
                                              ? '${here.label} · bisa meleset di perbatasan, pilih manual bila perlu'
                                              : app.locDenied
                                              ? 'Izinkan akses lokasi untuk memakai GPS'
                                              : 'Desa/kelurahan terdekat dari GPS',
                                          style: t(
                                            12,
                                            FontWeight.w400,
                                            C.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (app.favs.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                              child: Text('Favorit', style: t(13, w6, C.sub)),
                            ),
                            for (final p in app.favs)
                              _tile(
                                p,
                                icon: _tagIcon(p.tag),
                                title: p.tag == null
                                    ? p.name
                                    : '${p.tag} · ${p.name}',
                              ),
                          ],
                          // Lokasi yang sedang dipakai tapi belum favorit: tawarkan untuk disimpan.
                          if (app.fcPlace != null &&
                              !app.fcAuto &&
                              !app.isFav(app.fcPlace!)) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                              child: Text(
                                'Sedang dipakai',
                                style: t(13, w6, C.sub),
                              ),
                            ),
                            _tile(app.fcPlace!),
                          ],
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _tagIcon(String? tag) => switch (tag) {
  'Rumah' => Icons.home_rounded,
  'Kantor' => Icons.work_rounded,
  'Kampus' => Icons.school_rounded,
  'Sekolah' => Icons.backpack_rounded,
  _ => Icons.star_rounded,
};
