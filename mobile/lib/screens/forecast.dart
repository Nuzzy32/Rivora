import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../art.dart';
import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

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

/// Kartu kaca kartu cuaca utama (kartu info di bawahnya tetap putih solid).
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final bool shadow;
  const _Glass({
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: .42),
          Colors.white.withValues(alpha: .12),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .55)),
      boxShadow: shadow ? soft(.25, 40, 24, const Color(0xFF325AC8)) : null,
    ),
    child: child,
  );
}

/// M08: prakiraan BMKG per 3 jam untuk kecamatan terpilih.
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  final _chips = ScrollController();
  int _dir = 1; // arah geser isi kartu: 1 = slot ke kanan, -1 = ke kiri

  @override
  void dispose() {
    _chips.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == app.fcSlot) return;
    _dir = i > app.fcSlot ? 1 : -1;
    HapticFeedback.selectionClick();
    app.set(() => app.fcSlot = i);
    // Bawa chip terpilih ke tengah layar.
    if (_chips.hasClients) {
      final target =
          i * 76.0 - (MediaQuery.sizeOf(context).width - 66) / 2 + 20;
      _chips.animateTo(
        target.clamp(0, _chips.position.maxScrollExtent),
        duration: dur(context, 380),
        curve: easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = app.forecast;
    final loading = app.fcLoading || f == null || f.slots.isEmpty;
    final cur = loading
        ? null
        : f.slots[app.fcSlot.clamp(0, f.slots.length - 1)];
    final now = DateTime.now();
    final src = f == null
        ? 'Sumber: BMKG'
        : 'Sumber: BMKG · ${app.fcStale ? 'data tersimpan' : 'diambil'} ${hm(f.fetchedAt)} WIB';
    final key = '${app.district}-${app.fcSlot}';
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
          // Langit bergerak sesuai cuaca slot terpilih (matahari, awan, bintang, hujan, kilat).
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
          // Isi bergulir di bawah status bar (terpotong di sana), langit tetap tampil di belakangnya.
          Padding(
            padding: EdgeInsets.only(top: topInset(context)),
            child: ListView(
              padding: const EdgeInsets.only(top: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Prakiraan', style: t(24, w7, Colors.white)),
                            Text(
                              '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} · per 3 jam',
                              style: t(13, w5, Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Tap(
                        onTap: () => _pickDistrict(context),
                        height: 48,
                        radius: 15,
                        color: Colors.white.withValues(alpha: .22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .55),
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                        label: 'Pilih kecamatan',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            AnimatedSwitcher(
                              duration: dur(context, 260),
                              transitionBuilder: materialize(
                                from: const Offset(0, 6),
                              ),
                              child: Text(
                                'Kec. ${app.district}',
                                key: ValueKey(app.district),
                                style: t(13, w6, Colors.white),
                              ),
                            ),
                            const Icon(
                              Icons.expand_more_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 130,
                  child: ListView(
                    key: ValueKey(
                      app.district,
                    ), // ganti kecamatan → chip masuk ulang bertahap
                    controller: _chips,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                    children: [
                      for (final (i, s)
                          in (loading ? const <Slot>[] : f.slots).indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Appear(
                            index: i,
                            dy: 14,
                            child: _SlotChip(
                              s,
                              selected: i == app.fcSlot,
                              onTap: () => _select(i),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Glass(
                    radius: 34,
                    padding: const EdgeInsets.all(22),
                    shadow: true,
                    child: AnimatedSwitcher(
                      duration: dur(context, 360),
                      transitionBuilder: materialize(),
                      child: cur == null ? _loadingCard() : _card(f!, cur, key),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                // Langit menerus sampai bawah; kartu info tetap putih solid supaya mudah dibaca.
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, tabSpace(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (app.fcStale) ...[
                        Appear(
                          child: Note(
                            'Gagal memuat data terbaru. Menampilkan prakiraan tersimpan pukul ${hm(f!.fetchedAt)} WIB.',
                            icon: Icons.cloud_off_rounded,
                            bg: C.ink,
                            fg: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (f?.warning != null && !app.fcStale) ...[
                        Appear(
                          child: Box(
                            radius: 22,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const IconTile(
                                  Icons.thunderstorm_rounded,
                                  C.violet,
                                  Colors.white,
                                  gradient: gViolet,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Peringatan dini BMKG',
                                        style: t(14, w6),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        f!.warning!,
                                        style: t(
                                          13,
                                          FontWeight.w400,
                                          C.body,
                                          1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Appear(
                        index: 1,
                        child: Box(
                          radius: 22,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.shield_rounded,
                                    size: 20,
                                    color: C.violetMid,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(src, style: t(13, w6))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Prakiraan ini bukan prediksi banjir. Untuk kondisi jalan saat ini, lihat laporan di Peta.',
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
          app.fcLoading
              ? 'Memuat prakiraan Kec. ${app.district}…'
              : 'Prakiraan Kec. ${app.district} belum tersedia. Coba lagi sebentar lagi.',
          style: t(13, w5, Colors.white),
        ),
      ],
    ),
  );

  /// Isi kartu: ilustrasi berganti dengan scale+blur, angka bergulir, teks bergeser searah pilihan.
  Widget _card(Forecast f, Slot cur, String key) => Column(
    key: const ValueKey('card'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(-14, -18),
            child: SizedBox(
              width: 150,
              height: 150,
              child: AnimatedSwitcher(
                duration: dur(context, 420),
                reverseDuration: dur(context, 200),
                transitionBuilder: (child, a) => AnimatedBuilder(
                  animation: a,
                  child: child,
                  builder: (context, child) {
                    final v = easeOut.transform(a.value);
                    return Opacity(
                      opacity: v,
                      child: Transform.scale(
                        scale: .85 + .15 * v,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 6 * (1 - v),
                            sigmaY: 6 * (1 - v),
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
                child: WxAnim(
                  cur.kind,
                  key: ValueKey('${cur.kind}-$key'),
                  size: 150,
                ),
              ),
            ),
          ),
          // Angka besar mengecil sendiri kalau layar sempit / huruf sistem diperbesar.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CountTo(
                    cur.temp,
                    suffix: '°',
                    style: t(
                      68,
                      w6,
                      Colors.white,
                      1,
                    ).copyWith(letterSpacing: -2),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Terasa ', style: t(13, w5, Colors.white)),
                      CountTo(
                        cur.feels,
                        suffix: '°',
                        style: t(13, w5, Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      Transform.translate(
        offset: const Offset(0, -14),
        child: AnimatedSwitcher(
          duration: dur(context, 340),
          reverseDuration: dur(context, 160),
          transitionBuilder: materialize(from: Offset(_dir * 24, 0)),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey(key),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cur.desc, style: t(26, w7, Colors.white)),
              Text('Pukul ${hm(cur.time)} WIB', style: t(14, w5, Colors.white)),
              if (f.rainLine != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: C.violetInk,
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: Text(f.rainLine!, style: t(12, w6))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          _stat(
            Icons.umbrella_rounded,
            AnimatedSwitcher(
              duration: dur(context, 260),
              transitionBuilder: materialize(from: const Offset(0, 6)),
              child: Text(
                '${cur.rainMm.toStringAsFixed(1).replaceAll('.', ',')} mm',
                key: ValueKey(cur.rainMm),
                style: t(15, w6, Colors.white),
              ),
            ),
            'Curah hujan',
          ),
          const SizedBox(width: 10),
          _stat(
            Icons.air_rounded,
            CountTo(cur.wind, suffix: ' km/j', style: t(15, w6, Colors.white)),
            'Angin',
          ),
          const SizedBox(width: 10),
          _stat(
            Icons.water_drop_outlined,
            CountTo(cur.hum, suffix: '%', style: t(15, w6, Colors.white)),
            'Kelembapan',
          ),
        ],
      ),
    ],
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

  Widget _stat(IconData icon, Widget value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: Colors.white),
          const SizedBox(height: 4),
          value,
          Text(
            label,
            textAlign: TextAlign.center,
            style: t(11, w5, Colors.white),
          ),
        ],
      ),
    ),
  );

  void _pickDistrict(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3EE),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
              child: Text('Pilih kecamatan', style: t(17, w7)),
            ),
            for (final (i, d) in Api.districts.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Appear(
                  index: i,
                  child: Tap(
                    onTap: () {
                      Navigator.pop(ctx);
                      app.loadForecast(d);
                    },
                    height: 52,
                    radius: 16,
                    color: d == app.district ? C.blueTint : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text('Kec. $d', style: t(14, w5))),
                        if (d == app.district)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 22,
                            color: C.blue,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Chip slot 3 jam. Yang terpilih "terangkat": putih, bayangan, sedikit lebih besar.
class _SlotChip extends StatelessWidget {
  final Slot s;
  final bool selected;
  final VoidCallback onTap;
  const _SlotChip(this.s, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? C.violetMid : Colors.white;
    return Semantics(
      selected: selected,
      label: 'Pukul ${hm(s.time)}, ${s.desc}, ${s.temp} derajat',
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: dur(context, 260),
        curve: easeOut,
        child: Tap(
          onTap: onTap,
          width: 66,
          height: 120,
          radius: 33,
          pressScale: .94,
          // Biru muda, bukan putih: ilustrasi awan putih tetap terlihat di chip terpilih.
          color: selected ? C.blueTint2 : Colors.white.withValues(alpha: .18),
          border: Border.all(color: Colors.white.withValues(alpha: .4)),
          shadow: selected
              ? soft(.25, 24, 14, const Color(0xFF325AC8))
              : soft(0, 24, 14, const Color(0xFF325AC8)),
          child: ExcludeSemantics(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: fg),
              duration: dur(context, 200),
              builder: (context, c, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(hm(s.time), style: t(12, w6, c!)),
                  WxAnim(s.kind, size: 44, live: selected),
                  Text('${s.temp}°', style: t(18, w6, c)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
