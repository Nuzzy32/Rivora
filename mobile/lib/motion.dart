import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Kurva & durasi gerak bersama. Semua animasi lewat sini supaya "Kurangi Gerakan" di HP dihormati.
const easeOut = Cubic(
  0.22,
  1,
  0.36,
  1,
); // ease-out kuat: cepat terasa responsif, berhenti lembut
const easeIn = Cubic(0.55, 0, 1, 0.45);

bool reduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);

Duration dur(BuildContext c, int ms) =>
    reduced(c) ? Duration.zero : Duration(milliseconds: ms);

/// Masuk sekali saat pertama tampil: fade + naik 8 px + blur 4 → 0 (bertahap per [index]).
class Appear extends StatefulWidget {
  final Widget child;
  final int index;
  final double dy,
      scale; // scale < 1 = efek "pop" (mis. penanda peta); jangan dari 0
  const Appear({
    super.key,
    required this.child,
    this.index = 0,
    this.dy = 8,
    this.scale = 1,
  });

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _a = CurvedAnimation(parent: _c, curve: easeOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (reduced(context)) {
      _c.value = 1;
    } else {
      // Maksimal ±8 item bertahap; sisanya ikut item ke-8 supaya daftar panjang tidak lambat.
      Future.delayed(
        Duration(milliseconds: 40 * math.min(widget.index, 8)),
        () => mounted ? _c.forward() : null,
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    child: widget.child,
    builder: (context, child) {
      final v = _a.value;
      if (v == 1) return child!;
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, widget.dy * (1 - v)),
          child: Transform.scale(
            scale: widget.scale + (1 - widget.scale) * v,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 4 * (1 - v),
                sigmaY: 4 * (1 - v),
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Transisi untuk AnimatedSwitcher: yang masuk fade + geser + blur, yang keluar cukup memudar (lebih halus).
Widget Function(Widget, Animation<double>) materialize({
  Offset from = const Offset(0, 8),
  bool blur = true,
}) =>
    (child, anim) => AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, child) {
        final entering =
            anim.status == AnimationStatus.forward ||
            anim.status == AnimationStatus.completed;
        final v = (entering ? easeOut : easeIn).transform(anim.value);
        final shift = entering ? from * (1 - v) : -from * .4 * (1 - v);
        Widget w = Transform.translate(offset: shift, child: child);
        if (blur && v < 1) {
          w = ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 4 * (1 - v),
              sigmaY: 4 * (1 - v),
            ),
            child: w,
          );
        }
        return Opacity(opacity: v, child: w);
      },
    );

/// Kilau berjalan di skeleton saat memuat. Berhenti otomatis saat "Kurangi Gerakan".
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color base, glow;
  const Shimmer({
    super.key,
    required this.child,
    this.base = const Color(0xFFEDF1F9),
    this.glow = Colors.white,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (r) => LinearGradient(
        colors: [widget.base, widget.glow, widget.base],
        stops: const [.35, .5, .65],
        begin: Alignment(-2 + 4 * _c.value, 0),
        end: Alignment(-1 + 4 * _c.value, 0),
      ).createShader(r),
      child: child,
    ),
  );
}

/// Sheet bawah yang bisa ditarik turun untuk menutup; keputusan pakai kecepatan, bukan jarak saja.
class DragToDismiss extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  const DragToDismiss({
    super.key,
    required this.child,
    required this.onDismiss,
  });

  @override
  State<DragToDismiss> createState() => _DragToDismissState();
}

class _DragToDismissState extends State<DragToDismiss>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (v > 700 || _c.value > 140) {
      widget.onDismiss();
    } else {
      _c.animateTo(
        0,
        duration: dur(context, 260),
        curve: easeOut,
      ); // pegas balik
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragUpdate: (d) =>
        _c.value = math.max(0, _c.value + d.delta.dy * (_c.value < 0 ? .3 : 1)),
    onVerticalDragEnd: _end,
    child: AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _c.value), child: child),
    ),
  );
}

/// Angka yang bergulir halus ke nilai baru (suhu, jumlah titik).
class CountTo extends StatelessWidget {
  final int value;
  final TextStyle style;
  final String suffix;
  const CountTo(this.value, {super.key, required this.style, this.suffix = ''});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: dur(context, 500),
    curve: easeOut,
    builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
  );
}

/// Isi layar masuk bertahap saat pertama dibuka.
List<Widget> stagger(List<Widget> children) => [
  for (final (i, w) in children.indexed) Appear(index: i, child: w),
];
