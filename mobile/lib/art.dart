import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ilustrasi cuaca 3D lembut dari Wx.dc.html. Digambar di kanvas 100x100 lalu diskalakan.
/// [phase] 0..1 menggerakkan awan mengambang, tetes jatuh, petir berkedip (dipakai [LiveWx]).
class Wx extends StatelessWidget {
  final String
  kind; // sun, partly, cloud, rain, heavy, storm, nightcloud, nightrain
  final double size;
  final double? phase;
  const Wx(this.kind, {super.key, this.size = 100, this.phase});

  @override
  Widget build(BuildContext context) {
    final k = kind, ph = phase;
    final drops = {'rain': 2, 'nightrain': 2, 'heavy': 3}[k] ?? 0;
    final pos = drops == 3
        ? const [Offset(30, 86), Offset(49, 90), Offset(68, 86)]
        : const [Offset(38, 86), Offset(60, 88)];
    final light = const [
      'partly',
      'cloud',
      'rain',
      'nightcloud',
      'nightrain',
    ].contains(k);
    final dark = k == 'heavy' || k == 'storm';
    // Awan dan benda langit bergerak dengan fase berbeda: kesan kedalaman yang sangat halus.
    final float = ph == null ? 0.0 : math.sin(ph * 2 * math.pi) * 2.5;
    final skyFloat = ph == null ? 0.0 : math.sin(ph * 2 * math.pi + 1.2) * 1.5;
    Widget drop(int i, Offset p) {
      if (ph == null) {
        return Positioned(left: p.dx, top: p.dy, child: const _Drop());
      }
      final f = (ph * 2 + i / drops) % 1; // dua siklus jatuh per siklus awan
      return Positioned(
        left: p.dx,
        top: p.dy - 4 + f * 12,
        child: Opacity(
          opacity: f < .75 ? 1 : (1 - f) / .25,
          child: const _Drop(),
        ),
      );
    }

    final bolt =
        ph == null || (ph % .5) < .06 || (ph % .5 > .1 && ph % .5 < .13)
        ? 1.0
        : .35;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: FittedBox(
          child: SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Transform.translate(
                  offset: Offset(0, skyFloat),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (k == 'sun') _sun(18, 64, big: true),
                      if (k == 'partly' || k == 'rain') _sun(8, 46),
                      if (k.startsWith('night'))
                        const Positioned(left: 50, top: 4, child: _Moon()),
                    ],
                  ),
                ),
                for (final (i, p) in pos.take(drops).indexed) drop(i, p),
                if (k == 'storm')
                  Positioned(
                    left: 42,
                    top: 72,
                    child: Opacity(opacity: bolt, child: const _Bolt()),
                  ),
                if (light || dark)
                  Positioned(
                    left: 10,
                    top: 34 + float,
                    child: light
                        ? const _Cloud(
                            Colors.white,
                            Color(0xFFE3EAF7),
                            Color(0x475896FD),
                          )
                        : const _Cloud(
                            Color(0xFFF3F5FA),
                            Color(0xFFC3CDE4),
                            Color(0x4D3C508C),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sun(double at, double d, {bool big = false}) => Positioned(
    left: at,
    top: at,
    child: Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-.32, -.4),
          colors: [Color(0xFFFFF4C2), Color(0xFFFFD24D), Color(0xFFF5A524)],
          stops: [0, .45, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF5A524).withValues(alpha: big ? .45 : .4),
            blurRadius: big ? 26 : 18,
            offset: Offset(0, big ? 12 : 8),
          ),
        ],
      ),
    ),
  );
}

class _Cloud extends StatelessWidget {
  final Color top, bottom, shadow;
  const _Cloud(this.top, this.bottom, this.shadow);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 80,
    height: 50,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          right: 4,
          top: 26,
          height: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
        ),
        Positioned(left: 10, top: 6, child: _circle(32, top)),
        Positioned(left: 30, top: -6, child: _circle(42, top)),
        Positioned(
          left: 0,
          top: 20,
          child: Container(
            width: 80,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _circle(double d, Color c) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
  );
}

class _Drop extends StatelessWidget {
  const _Drop();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi / 4,
    child: Container(
      width: 11,
      height: 11,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(5.5),
          bottomLeft: Radius.circular(5.5),
          bottomRight: Radius.circular(5.5),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA6CAFF), Color(0xFF3C7BF0)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x593C7BF0),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
    ),
  );
}

class _Moon extends StatelessWidget {
  const _Moon();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -15 * math.pi / 180,
    child: const CustomPaint(size: Size(40, 40), painter: _MoonPainter()),
  );
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2;
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset(r, r), radius: r));
    final cut = Path()
      ..addOval(Rect.fromCircle(center: Offset(r - 11, r + 5), radius: r));
    final moon = Path.combine(PathOperation.difference, outer, cut);
    canvas.drawShadow(moon, const Color(0xFF806EF8), 4, false);
    canvas.drawPath(moon, Paint()..color = const Color(0xFF8F7DFA));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Bolt extends StatelessWidget {
  const _Bolt();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(size: Size(18, 26), painter: _BoltPainter());
}

class _BoltPainter extends CustomPainter {
  const _BoltPainter();

  @override
  void paint(Canvas canvas, Size s) {
    Offset p(double x, double y) => Offset(s.width * x, s.height * y);
    final path = Path()
      ..addPolygon([
        p(.45, 0),
        p(1, 0),
        p(.68, .42),
        p(1, .42),
        p(.22, 1),
        p(.42, .55),
        p(.08, .55),
      ], true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE27A), Color(0xFFF5B000)],
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Figur orang dengan tinggi air (DepthFig.dc.html). level 0..4 = aman..sedada.
class DepthFig extends StatelessWidget {
  final int level;
  final double size;
  const DepthFig(this.level, {super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    final water = const [0.0, 20.0, 36.0, 52.0, 76.0][level.clamp(0, 4)];
    const dark = Color(0xFF474E6B), arm = Color(0xFF5A6283);
    Widget part(
      double l,
      double tp,
      double w,
      double h,
      double r,
      Color c, [
      double rot = 0,
    ]) => Positioned(
      left: l,
      top: tp,
      child: Transform.rotate(
        angle: rot * math.pi / 180,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(r),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size * 110 / 80,
        child: FittedBox(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 80,
              height: 110,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7F9FE), Color(0xFFE6EDFA)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 8,
                    child: Container(color: const Color(0xFFCBD5E8)),
                  ),
                  Positioned(
                    left: 32,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: dark,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 27,
                    top: 27,
                    child: Container(
                      width: 26,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: dark,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(12),
                          bottom: Radius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  part(22, 30, 7, 30, 4, arm, 8),
                  part(51, 30, 7, 30, 4, arm, -8),
                  part(29, 62, 9, 40, 5, dark),
                  part(42, 62, 9, 40, 5, dark),
                  // Air naik dari dasar ke tinggi sebenarnya: memperagakan arti kategori ketinggian.
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: water),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 900),
                      curve: const Cubic(0.22, 1, 0.36, 1),
                      builder: (context, h, _) => Align(
                        alignment: Alignment.bottomCenter,
                        child: h < .5
                            ? const SizedBox.shrink()
                            : Container(
                                height: h,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x9E6EA5FF),
                                      Color(0xD14682F0),
                                    ],
                                  ),
                                  border: Border(
                                    top: BorderSide(
                                      color: Color(0xD9FFFFFF),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (level == 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF1FA36A),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
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

/// [Wx] yang hidup: siklus 4 detik. Diam saat "Kurangi Gerakan" aktif.
/// Hanya dipakai untuk ilustrasi besar (hero) supaya tidak boros baterai.
class LiveWx extends StatefulWidget {
  final String kind;
  final double size;
  const LiveWx(this.kind, {super.key, this.size = 100});

  @override
  State<LiveWx> createState() => _LiveWxState();
}

class _LiveWxState extends State<LiveWx> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Wx(
        widget.kind,
        size: widget.size,
        phase: _c.isAnimating ? _c.value : null,
      ),
    ),
  );
}
