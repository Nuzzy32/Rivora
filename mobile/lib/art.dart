import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ilustrasi cuaca 3D lembut dari Wx.dc.html. Digambar di kanvas 100x100 lalu diskalakan.
class Wx extends StatelessWidget {
  final String
  kind; // sun, partly, cloud, rain, heavy, storm, nightcloud, nightrain
  final double size;
  const Wx(this.kind, {super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    final k = kind;
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
                if (k == 'sun') _sun(18, 64, big: true),
                if (k == 'partly' || k == 'rain') _sun(8, 46),
                if (k.startsWith('night'))
                  const Positioned(left: 50, top: 4, child: _Moon()),
                for (final p in pos.take(drops))
                  Positioned(left: p.dx, top: p.dy, child: const _Drop()),
                if (k == 'storm')
                  const Positioned(left: 42, top: 72, child: _Bolt()),
                if (light)
                  const Positioned(
                    left: 10,
                    top: 34,
                    child: _Cloud(
                      Colors.white,
                      Color(0xFFE3EAF7),
                      Color(0x475896FD),
                    ),
                  ),
                if (dark)
                  const Positioned(
                    left: 10,
                    top: 34,
                    child: _Cloud(
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
                  if (water > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: water,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x9E6EA5FF), Color(0xD14682F0)],
                          ),
                          border: Border(
                            top: BorderSide(color: Color(0xD9FFFFFF), width: 2),
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
