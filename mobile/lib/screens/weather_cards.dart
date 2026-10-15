import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../art.dart';
import '../data.dart';
import '../theme.dart';

// Kartu gaya aplikasi Cuaca iPhone di atas langit beranimasi. Data inti BMKG; kartu bertanda
// Open-Meteo hanya untuk yang tidak disediakan BMKG (UV, tekanan, jarak pandang, 10 hari, rata-rata).

const _white = Colors.white;
final _dim = Colors.white.withValues(alpha: .72);
TextStyle _label() => t(12, w6, _dim).copyWith(letterSpacing: .4);

/// Kartu kaca: buram + tint gelap tipis supaya teks putih tetap terbaca di langit cerah.
class WxCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  final String? source;
  final EdgeInsets padding;
  const WxCard({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
    this.source,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 14),
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFF0B1B3F).withValues(alpha: .22),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: _dim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
            if (source != null) ...[
              const SizedBox(height: 8),
              Text(
                source!,
                style: t(10, w5, Colors.white.withValues(alpha: .55)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Kartu persegi untuk grid 2 kolom: angka besar + kalimat penjelas di bawah.
class WxTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final String? sub, note, source;
  final Widget? art;
  const WxTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.note,
    this.art,
    this.source,
  });

  @override
  Widget build(BuildContext context) => WxCard(
    icon: icon,
    label: label,
    source: source,
    child: SizedBox(
      height: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t(32, w5, _white, 1.1)),
          ),
          if (sub != null)
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t(14, w6, _white),
            ),
          if (art != null) ...[const SizedBox(height: 8), art!],
          const Spacer(),
          if (note != null)
            Text(
              note!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t(12, w5, _white, 1.35),
            ),
        ],
      ),
    ),
  );
}

/// Dua kartu sejajar (grid iPhone).
Widget wxPair(Widget? a, Widget? b) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(child: a ?? const SizedBox.shrink()),
    const SizedBox(width: 12),
    Expanded(child: b ?? const SizedBox.shrink()),
  ],
);

// ---------------------------------------------------------------------------
// Per jam (BMKG, per 3 jam) + matahari terbit/terbenam disisipkan di urutannya
// ---------------------------------------------------------------------------
class HourlyCard extends StatelessWidget {
  final Forecast f;
  const HourlyCard(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final e = f.extra;
    final items = <({String top, Widget icon, String bottom})>[];
    int? mins(String? hhmm) => hhmm == null
        ? null
        : int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3));
    final sunEvents = [
      if (mins(e?.sunrise) != null)
        (mins(e!.sunrise)!, e.sunrise!, 'Terbit', Icons.wb_twilight_rounded),
      if (mins(e?.sunset) != null)
        (mins(e!.sunset)!, e.sunset!, 'Terbenam', Icons.nights_stay_rounded),
    ];
    final today = f.local(DateTime.now());
    for (final (i, s) in f.slots.take(16).indexed) {
      items.add((
        top: i == 0 ? 'Kini' : f.at(s.time),
        icon: Wx(s.kind, size: 34),
        bottom: '${s.temp}°',
      ));
      // Sisipkan terbit/terbenam hari ini yang jatuh sebelum slot berikutnya.
      if (i + 1 < f.slots.length) {
        final a = f.local(s.time), b = f.local(f.slots[i + 1].time);
        for (final ev in sunEvents) {
          final at = DateTime(
            today.year,
            today.month,
            today.day,
            ev.$1 ~/ 60,
            ev.$1 % 60,
          );
          if (at.isAfter(a) && !at.isAfter(b)) {
            items.add((
              top: ev.$2.replaceAll(':', '.'),
              icon: Icon(ev.$4, size: 26, color: const Color(0xFFFFD36B)),
              bottom: ev.$3,
            ));
          }
        }
      }
    }
    return WxCard(
      icon: Icons.schedule_rounded,
      label: 'Per 3 jam',
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              f.rainLine ??
                  '${f.slots.first.desc} sekarang. Prakiraan per 3 jam dari BMKG.',
              style: t(13, w5, _white, 1.4),
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: .18), height: 18),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final it in items)
                  SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(it.top, style: t(13, w6, _white)),
                        ),
                        SizedBox(height: 36, child: Center(child: it.icon)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(it.bottom, style: t(16, w6, _white)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 10 hari (Open-Meteo): bar suhu berwarna rendah→tinggi, rentang dibanding semua hari
// ---------------------------------------------------------------------------
class DailyCard extends StatelessWidget {
  final List<WxDay> days;
  final int? nowTemp;
  const DailyCard(this.days, {super.key, this.nowTemp});

  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final lo = days.map((d) => d.tmin).reduce(math.min);
    final hi = days.map((d) => d.tmax).reduce(math.max);
    return WxCard(
      icon: Icons.calendar_month_rounded,
      label: 'Prakiraan ${days.length} hari',
      source: 'Sumber: Open-Meteo (model global, bukan BMKG)',
      child: Column(
        children: [
          for (final (i, d) in days.indexed) ...[
            if (i > 0)
              Divider(color: Colors.white.withValues(alpha: .18), height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      i == 0 ? 'Hari ini' : _days[d.date.weekday - 1],
                      style: t(15, w6, _white),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wx(d.kind, size: 26),
                        if (d.rainMm >= 1)
                          Text(
                            '${d.rainMm.round()} mm',
                            style: t(9, w6, const Color(0xFF8FD3FF)),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${d.tmin}°',
                      textAlign: TextAlign.right,
                      style: t(15, w6, _dim),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TempBar(
                      lo,
                      hi,
                      d.tmin,
                      d.tmax,
                      i == 0 ? nowTemp : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 36,
                    child: Text('${d.tmax}°', style: t(15, w6, _white)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TempBar extends StatelessWidget {
  final int lo, hi, a, b;
  final int? now;
  const _TempBar(this.lo, this.hi, this.a, this.b, this.now);

  // Biru (sejuk) → hijau → kuning → oranye (panas), seperti iPhone.
  static Color _c(int v) {
    const stops = [
      (20, Color(0xFF6FC3FF)),
      (25, Color(0xFF7ED957)),
      (30, Color(0xFFF7C948)),
      (34, Color(0xFFF58A2C)),
    ];
    if (v <= stops.first.$1) return stops.first.$2;
    for (var i = 1; i < stops.length; i++) {
      if (v <= stops[i].$1) {
        final (x0, c0) = stops[i - 1];
        final (x1, c1) = stops[i];
        return Color.lerp(c0, c1, (v - x0) / (x1 - x0))!;
      }
    }
    return stops.last.$2;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final span = math.max(1, hi - lo), w = c.maxWidth;
      final l = (a - lo) / span * w, r = (b - lo) / span * w;
      return SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Positioned(
              left: l,
              width: math.max(6, r - l),
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_c(a), _c(b)]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (now != null && now! >= a && now! <= b)
              Positioned(
                left: ((now! - lo) / span * w - 3).clamp(0, w - 6),
                top: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black.withValues(alpha: .25),
                      width: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Kartu kecil
// ---------------------------------------------------------------------------
String feelsNote(int feels, int temp) => feels >= temp + 2
    ? 'Terasa lebih panas dari suhu sebenarnya karena lembap.'
    : feels <= temp - 2
    ? 'Terasa lebih sejuk dari suhu sebenarnya.'
    : 'Mirip dengan suhu sebenarnya.';

/// Titik embun (rumus Magnus).
int dewPoint(int t, int rh) {
  const a = 17.62, b = 243.12;
  final g = math.log(math.max(1, rh) / 100) + a * t / (b + t);
  return (b * g / (a - g)).round();
}

({String level, String note}) uvLevel(int uv) => uv <= 2
    ? (level: 'Rendah', note: 'Aman di luar ruangan.')
    : uv <= 5
    ? (level: 'Sedang', note: 'Pakai pelindung saat siang.')
    : uv <= 7
    ? (level: 'Tinggi', note: 'Kurangi terik pukul 10–15.')
    : uv <= 10
    ? (level: 'Sangat tinggi', note: 'Hindari terik siang hari.')
    : (level: 'Ekstrem', note: 'Hindari berada di bawah matahari.');

class UvBar extends StatelessWidget {
  final int uv;
  const UvBar(this.uv, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SizedBox(
      height: 6,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF6DD46B),
                  Color(0xFFF7E04A),
                  Color(0xFFF58A2C),
                  Color(0xFFE5484D),
                  Color(0xFFB45BDB),
                ],
              ),
            ),
          ),
          Positioned(
            left: (uv.clamp(0, 11) / 11 * c.maxWidth - 3).clamp(
              0,
              c.maxWidth - 6,
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withValues(alpha: .3)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

const _compassNames = [
  'Utara',
  'Timur Laut',
  'Timur',
  'Tenggara',
  'Selatan',
  'Barat Daya',
  'Barat',
  'Barat Laut',
];
String compassName(int deg) => _compassNames[((deg % 360) / 45).round() % 8];

/// Angin: kecepatan & arah asal (BMKG) + kompas dengan panah ke arah angin bertiup.
class WindCard extends StatelessWidget {
  final Slot s;
  const WindCard(this.s, {super.key});

  @override
  Widget build(BuildContext context) => WxCard(
    icon: Icons.air_rounded,
    label: 'Angin',
    child: Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _row('Kecepatan', '${s.wind} km/j'),
              Divider(color: Colors.white.withValues(alpha: .18), height: 1),
              _row('Dari arah', compassName(s.windDir!)),
              Divider(color: Colors.white.withValues(alpha: .18), height: 1),
              _row('Derajat', '${s.windDir}°'),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 118,
          height: 118,
          child: CustomPaint(
            painter: _CompassPainter(s.windDir!.toDouble()),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${s.wind}', style: t(22, w6, _white, 1)),
                  Text('km/j', style: t(11, w5, _dim)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(String a, String b) => SizedBox(
    height: 38,
    child: Row(
      children: [
        Expanded(child: Text(a, style: t(14, w5, _white))),
        Text(b, style: t(14, w5, _dim)),
      ],
    ),
  );
}

class _CompassPainter extends CustomPainter {
  final double from; // derajat asal angin
  _CompassPainter(this.from);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: .45)
      ..strokeWidth = 1;
    for (var i = 0; i < 72; i++) {
      final a = i * math.pi / 36,
          len = i % 18 == 0 ? 0.0 : (i % 2 == 0 ? 7.0 : 4.0);
      if (len == 0) continue;
      final d = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(c + d * (r - 2), c + d * (r - 2 - len), tick);
    }
    for (final (i, n) in ['U', 'T', 'S', 'B'].indexed) {
      final a = i * math.pi / 2, d = Offset(math.sin(a), -math.cos(a));
      final tp = TextPainter(
        text: TextSpan(text: n, style: t(11, w6, Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + d * (r - 8) - Offset(tp.width / 2, tp.height / 2));
    }
    // Panah dari arah asal menembus ke arah tujuan.
    final a = from * math.pi / 180, d = Offset(math.sin(a), -math.cos(a));
    final tail = c + d * (r - 18), head = c - d * (r - 18);
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, c + d * 26, p);
    canvas.drawLine(c - d * 26, head, p);
    canvas.drawCircle(tail, 4, Paint()..color = Colors.white);
    final side = Offset(-d.dy, d.dx);
    canvas.drawPath(
      Path()
        ..moveTo(head.dx - d.dx * 2, head.dy - d.dy * 2)
        ..lineTo(
          head.dx + d.dx * 9 + side.dx * 6,
          head.dy + d.dy * 9 + side.dy * 6,
        )
        ..lineTo(
          head.dx + d.dx * 9 - side.dx * 6,
          head.dy + d.dy * 9 - side.dy * 6,
        )
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.from != from;
}

/// Matahari: jam terbit/terbenam (Open-Meteo) + busur siang dengan posisi matahari sekarang.
class SunCard extends StatelessWidget {
  final String sunrise, sunset; // "HH:MM" waktu lokal lokasi
  final DateTime nowLocal;
  const SunCard(this.sunrise, this.sunset, this.nowLocal, {super.key});

  int _m(String s) =>
      int.parse(s.substring(0, 2)) * 60 + int.parse(s.substring(3));

  @override
  Widget build(BuildContext context) {
    final now = nowLocal.hour * 60 + nowLocal.minute;
    final up = _m(sunrise), down = _m(sunset);
    final day = now >= up && now < down;
    return WxTile(
      icon: day ? Icons.wb_twilight_rounded : Icons.wb_sunny_outlined,
      label: day ? 'Terbenam' : 'Terbit',
      value: (day || now < up ? (day ? sunset : sunrise) : sunrise).replaceAll(
        ':',
        '.',
      ),
      art: SizedBox(
        height: 34,
        width: double.infinity,
        child: CustomPaint(
          painter: _SunArc((now - up) / math.max(1, down - up)),
        ),
      ),
      note: day
          ? 'Terbit: ${sunrise.replaceAll(':', '.')}'
          : 'Terbenam: ${sunset.replaceAll(':', '.')}',
      source: 'Sumber: Open-Meteo',
    );
  }
}

class _SunArc extends CustomPainter {
  final double p; // 0 = terbit, 1 = terbenam
  _SunArc(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, base = h * .78;
    double y(double x) => base - math.sin(x * math.pi) * h * .7; // siang
    final path = Path()..moveTo(0, base + 6);
    for (var i = 0; i <= 60; i++) {
      final x = i / 60;
      // Busur siang di atas garis cakrawala, lengkung malam tipis di bawahnya.
      path.lineTo(x * w, x < 0 || x > 1 ? base + 6 : y(x));
    }
    canvas.drawLine(
      Offset(0, base),
      Offset(w, base),
      Paint()..color = Colors.white.withValues(alpha: .35),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    if (p >= 0 && p <= 1) {
      final o = Offset(p * w, y(p));
      canvas.drawCircle(
        o,
        7,
        Paint()..color = const Color(0xFFFFE08A).withValues(alpha: .35),
      );
      canvas.drawCircle(o, 4.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_SunArc old) => old.p != p;
}

/// Fase bulan dihitung di HP (bulan sinodis 29,53 hari dari bulan baru 6 Jan 2000 18.14 UTC).
({String name, int illum, int toFull, double age}) moonPhase(DateTime t) {
  const syn = 29.530588853;
  final days =
      t.toUtc().difference(DateTime.utc(2000, 1, 6, 18, 14)).inMinutes / 1440;
  final age = days % syn;
  final illum = ((1 - math.cos(2 * math.pi * age / syn)) / 2 * 100).round();
  final toFull = ((syn / 2 - age) % syn).round();
  final name = age < 1.85
      ? 'Bulan baru'
      : age < 5.54
      ? 'Sabit awal'
      : age < 9.23
      ? 'Paruh awal'
      : age < 12.92
      ? 'Cembung awal'
      : age < 16.61
      ? 'Purnama'
      : age < 20.3
      ? 'Cembung akhir'
      : age < 23.99
      ? 'Paruh akhir'
      : age < 27.68
      ? 'Sabit akhir'
      : 'Bulan baru';
  return (name: name, illum: illum, toFull: toFull, age: age);
}

class MoonCard extends StatelessWidget {
  final DateTime now;
  const MoonCard(this.now, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = moonPhase(now);
    Widget row(String a, String b) => SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(child: Text(a, style: t(14, w5, _white))),
          Text(b, style: t(14, w5, _dim)),
        ],
      ),
    );
    return WxCard(
      icon: Icons.dark_mode_rounded,
      label: m.name,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                row('Terang', '${m.illum}%'),
                Divider(color: Colors.white.withValues(alpha: .18), height: 1),
                row(
                  'Purnama berikutnya',
                  m.toFull == 0 ? 'Malam ini' : '${m.toFull} hari',
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _MoonPhasePainter(m.age / 29.530588853),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoonPhasePainter extends CustomPainter {
  final double phase; // 0 baru, .5 purnama
  _MoonPhasePainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()..color = const Color(0xFF2A3550).withValues(alpha: .55),
    );
    // Bagian terang: setengah lingkaran + elips terminator.
    final waxing = phase < .5;
    final k = math.cos(2 * math.pi * phase); // 1 baru → -1 purnama
    final lit = Path()
      ..addArc(rect, -math.pi / 2, waxing ? math.pi : -math.pi)
      ..arcTo(
        Rect.fromCenter(center: c, width: (r * 2 * k).abs(), height: r * 2),
        math.pi / 2,
        (waxing ? 1 : -1) * (k > 0 ? -math.pi : math.pi),
        false,
      )
      ..close();
    canvas.drawPath(lit, Paint()..color = const Color(0xFFE9EEF7));
  }

  @override
  bool shouldRepaint(_MoonPhasePainter old) => old.phase != phase;
}

/// Tekanan udara: busur gauge 960–1060 hPa.
class PressureArt extends StatelessWidget {
  final int hpa;
  const PressureArt(this.hpa, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    width: double.infinity,
    child: CustomPaint(
      painter: _Gauge(((hpa - 960) / 100).clamp(0, 1).toDouble()),
    ),
  );
}

class _Gauge extends CustomPainter {
  final double v;
  _Gauge(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, y = size.height / 2;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: .25)
      ..strokeWidth = 2;
    for (var i = 0; i <= 30; i++) {
      final x = i / 30 * w;
      canvas.drawLine(
        Offset(x, y - (i % 5 == 0 ? 6 : 3)),
        Offset(x, y + (i % 5 == 0 ? 6 : 3)),
        track,
      );
    }
    canvas.drawLine(
      Offset(v * w, y - 10),
      Offset(v * w, y + 10),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Gauge old) => old.v != v;
}
