import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'motion.dart';

/// Warna dari desain Claude Design (SIGAP Banjir.dc.html).
class C {
  static const ink = Color(0xFF1A1D26);
  static const body = Color(0xFF565D73);
  static const muted = Color(0xFF6B7286);
  static const sub = Color(0xFF3B4157);
  static const faint = Color(0xFF9AA1B4);
  static const bg = Color(0xFFF4F7FD);
  static const line = Color(0xFFEDF1F9);
  static const field = Color(0xFFE3E8F2);
  static const blue = Color(0xFF5896FD);
  static const blueLight = Color(0xFFAECDFF);
  static const blueInk = Color(0xFF2462D0);
  static const blueMid = Color(0xFF2F6FE0);
  static const blueTint = Color(0xFFEEF4FF);
  static const blueTint2 = Color(0xFFE6EFFF);
  static const violet = Color(0xFF806EF8);
  static const violetLight = Color(0xFFB0A4FF);
  static const violetInk = Color(0xFF5B47E0);
  static const violetMid = Color(0xFF6F5CF0);
  static const violetTint = Color(0xFFEEEBFF);
  static const red = Color(0xFFC4282E);
  static const redBright = Color(0xFFE5484D);
  static const redTint = Color(0xFFFDE3E4);
  static const redInk = Color(0xFF9C161C);
  static const green = Color(0xFF0B6640);
  static const greenTint = Color(0xFFE2F5EB);
  static const amberTint = Color(0xFFFFF3D3);
  static const amberInk = Color(0xFF6E4E00);
  static const grayTint = Color(0xFFEEF0F4);
  static const grayInk = Color(0xFF4A5068);
}

const gBlue = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF7FB0FF), C.blue],
);
const gBlueSoft = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [C.blueLight, C.blue],
);
const gViolet = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [C.violetLight, C.violet],
);
const gRed = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF2777B), Color(0xFFD93439)],
);

List<BoxShadow> soft([
  double a = .10,
  double blur = 22,
  double y = 8,
  Color c = const Color(0xFF466EC8),
]) => [
  BoxShadow(
    color: c.withValues(alpha: a),
    blurRadius: blur,
    offset: Offset(0, y),
  ),
];

/// Skala ketinggian air PRD §8: teks + ilustrasi + warna, tidak pernah warna saja.
class Depth {
  final String label, cm, mark, level, meaning;
  final Color color, tint, ink, fg;
  const Depth(
    this.label,
    this.cm,
    this.mark,
    this.level,
    this.meaning,
    this.color,
    this.tint,
    this.ink,
    this.fg,
  );
}

const depths = [
  Depth(
    'Aman / Surut',
    '0 cm',
    '0',
    'Aman',
    'Bisa dilalui',
    Color(0xFF1FA36A),
    C.greenTint,
    C.green,
    Colors.white,
  ),
  Depth(
    'Semata kaki',
    '± 10 cm',
    '10',
    'Waspada',
    'Hati-hati, motor masih bisa lewat',
    Color(0xFFF4B92F),
    C.amberTint,
    C.amberInk,
    Color(0xFF3D2B00),
  ),
  Depth(
    'Selutut',
    '± 40 cm',
    '40',
    'Bahaya rendah',
    'Motor berisiko mogok, sebaiknya hindari',
    Color(0xFFF27A2C),
    Color(0xFFFFE8D9),
    Color(0xFF8F3A05),
    Colors.white,
  ),
  Depth(
    'Sepinggang',
    '± 80 cm',
    '80',
    'Bahaya',
    'Jangan dilalui',
    C.redBright,
    C.redTint,
    C.redInk,
    Colors.white,
  ),
  Depth(
    'Sedada ke atas',
    '> 100 cm',
    '100+',
    'Bahaya tinggi',
    'Pertimbangkan mengungsi sekarang',
    Color(0xFF9B1C50),
    Color(0xFFF6E0E9),
    Color(0xFF74103A),
    Colors.white,
  ),
];

class VerStyle {
  final String label, desc;
  final IconData icon;
  final Color color, tint;
  const VerStyle(this.label, this.icon, this.color, this.tint, this.desc);
}

const vers = {
  'official': VerStyle(
    'Resmi',
    Icons.shield_rounded,
    C.violetInk,
    C.violetTint,
    'Dari kanal resmi Pemkot / BPBD',
  ),
  'verified': VerStyle(
    'Terverifikasi',
    Icons.check_circle_rounded,
    C.blueInk,
    C.blueTint2,
    'Laporan warga, sudah dicek verifikator',
  ),
  'unverified': VerStyle(
    'Belum Terverifikasi',
    Icons.help_rounded,
    C.grayInk,
    C.grayTint,
    'Laporan warga, belum dicek. Nilai sendiri.',
  ),
};

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: C.blue,
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: GoogleFonts.poppinsTextTheme(
      base.textTheme,
    ).apply(bodyColor: C.ink, displayColor: C.ink),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.violetInk,
      thumbColor: C.violetInk,
      inactiveTrackColor: C.violetTint,
    ),
  );
}

TextStyle t(
  double size, [
  FontWeight w = FontWeight.w400,
  Color c = C.ink,
  double? h,
]) => TextStyle(fontSize: size, fontWeight: w, color: c, height: h);

const w5 = FontWeight.w500, w6 = FontWeight.w600, w7 = FontWeight.w700;

/// Area ketuk dengan ripple; semua tombol di desain lewat sini supaya target ≥ 48 dp konsisten.
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final double? width, height;
  final String? label;
  final double pressScale; // umpan balik tekan; 1 = tanpa
  const Tap({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 16,
    this.color,
    this.gradient,
    this.shadow,
    this.border,
    this.padding,
    this.width,
    this.height,
    this.label,
    this.pressScale = .97,
  });

  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget, r = BorderRadius.circular(w.radius);
    return Semantics(
      button: true,
      label: w.label,
      child: AnimatedScale(
        scale: _down ? w.pressScale : 1,
        // Tekan cepat, lepas sedikit lebih lambat supaya terasa memantul.
        duration: dur(context, _down ? 90 : 220),
        curve: easeOut,
        child: AnimatedContainer(
          // Perubahan warna/bayangan (chip terpilih, slot aktif) berpindah halus, tidak meloncat.
          duration: dur(context, 200),
          curve: easeOut,
          width: w.width,
          height: w.height,
          decoration: BoxDecoration(
            color: w.gradient == null ? w.color : null,
            gradient: w.gradient,
            borderRadius: r,
            boxShadow: w.shadow,
            border: w.border,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: w.onTap,
              onHighlightChanged: w.onTap == null
                  ? null
                  : (v) => setState(() => _down = v),
              child: Padding(
                padding: w.padding ?? EdgeInsets.zero,
                child: w.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol penuh: utama (gradien), sekunder (putih), atau teks.
class Btn extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final Color fg;
  final double height, radius;
  final List<BoxShadow>? shadow;
  final BoxBorder? border;
  final double fontSize;
  const Btn(
    this.text, {
    super.key,
    this.icon,
    this.onTap,
    this.gradient,
    this.color,
    this.fg = Colors.white,
    this.height = 56,
    this.radius = 20,
    this.shadow,
    this.border,
    this.fontSize = 15,
  });

  const Btn.primary(
    this.text, {
    super.key,
    this.icon,
    this.onTap,
    this.height = 56,
    this.fontSize = 15,
  }) : gradient = gBlue,
       color = null,
       fg = Colors.white,
       radius = 20,
       border = null,
       shadow = const [
         BoxShadow(
           color: Color(0x4D5896FD),
           blurRadius: 24,
           offset: Offset(0, 12),
         ),
       ];

  const Btn.violet(
    this.text, {
    super.key,
    this.icon,
    this.onTap,
    this.height = 56,
    this.fontSize = 15,
  }) : gradient = gViolet,
       color = null,
       fg = Colors.white,
       radius = 20,
       border = null,
       shadow = const [
         BoxShadow(
           color: Color(0x59806EF8),
           blurRadius: 24,
           offset: Offset(0, 12),
         ),
       ];

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    height: height,
    radius: radius,
    gradient: gradient,
    color: color,
    shadow: shadow,
    border: border,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    // scaleDown: tombol sempit atau huruf sistem 130% tidak overflow.
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 8),
          ],
          Text(text, style: t(fontSize, w6, fg)),
        ],
      ),
    ),
  );
}

/// Kotak ikon putih (kembali, tutup, lonceng).
class SquareBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color fg, bg;
  final String label;
  final bool shadowed;
  const SquareBtn(
    this.icon, {
    super.key,
    this.onTap,
    this.size = 48,
    this.fg = C.ink,
    this.bg = Colors.white,
    required this.label,
    this.shadowed = true,
  });

  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    width: size,
    height: size,
    radius: size / 3,
    color: bg,
    label: label,
    shadow: shadowed ? soft(.12, 20, 8) : null,
    child: Center(child: Icon(icon, size: 22, color: fg)),
  );
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final IconData? icon;
  final double size;
  const Pill(
    this.text,
    this.bg,
    this.fg, {
    super.key,
    this.icon,
    this.size = 11,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(icon == null ? 9 : 6, 4, 9, 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
        ],
        Flexible(child: Text(text, style: t(size, w6, fg))),
      ],
    ),
  );
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color bg, fg;
  final double size, iconSize, radius;
  final Gradient? gradient;
  const IconTile(
    this.icon,
    this.bg,
    this.fg, {
    super.key,
    this.size = 44,
    this.iconSize = 22,
    this.radius = 14,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: gradient == null ? bg : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Icon(icon, size: iconSize, color: fg),
  );
}

class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final List<BoxShadow>? shadow;
  const Box({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 24,
    this.color = Colors.white,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow ?? soft(.08, 20, 8),
    ),
    child: child,
  );
}

/// Pesan berwarna (peringatan, error, info) dengan ikon.
class Note extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color bg, fg;
  final String? bold;
  const Note(
    this.text, {
    super.key,
    this.icon,
    this.bg = C.amberTint,
    this.fg = C.amberInk,
    this.bold,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (bold != null)
                  TextSpan(text: '$bold ', style: t(13, w6, fg, 1.5)),
                TextSpan(text: text),
              ],
            ),
            style: t(13, FontWeight.w400, fg, 1.5),
          ),
        ),
      ],
    ),
  );
}

class EmptyCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, body;
  final Widget? action;
  const EmptyCard(
    this.icon,
    this.title,
    this.body, {
    super.key,
    this.iconColor = C.blueLight,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        Icon(icon, size: 38, color: iconColor),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: t(16, w6)),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: t(13, FontWeight.w400, C.muted, 1.55),
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

/// Judul layar: tombol kembali + judul + subjudul opsional.
class Header extends StatelessWidget {
  final String title;
  final String? sub;
  final VoidCallback onBack;
  final IconData icon;
  final Widget? trailing;
  const Header(
    this.title, {
    super.key,
    this.sub,
    required this.onBack,
    this.icon = Icons.arrow_back_rounded,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SquareBtn(
        icon,
        onTap: onBack,
        label: icon == Icons.close_rounded ? 'Tutup' : 'Kembali',
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t(20, w7)),
            if (sub != null) Text(sub!, style: t(12, FontWeight.w400, C.muted)),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// Input berlabel dengan pesan error di bawahnya.
class Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctl;
  final String? error;
  final bool obscure;
  final TextInputType? type;
  final Widget? suffix;
  final Iterable<String>? autofill;
  final ValueChanged<String>? onChanged;
  const Field(
    this.label,
    this.ctl, {
    super.key,
    this.hint = '',
    this.error,
    this.obscure = false,
    this.type,
    this.suffix,
    this.autofill,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: t(13, w6)),
      const SizedBox(height: 6),
      TextField(
        controller: ctl,
        obscureText: obscure,
        keyboardType: type,
        autofillHints: autofill,
        onChanged: onChanged,
        style: t(14),
        decoration: inputDeco(hint, error != null).copyWith(suffixIcon: suffix),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(error!, style: t(12, FontWeight.w400, C.red)),
        ),
    ],
  );
}

InputDecoration inputDeco(String hint, [bool err = false]) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: 1.5),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: t(14, FontWeight.w400, C.faint),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: b(err ? C.redBright : C.field),
    focusedBorder: b(err ? C.redBright : C.blue),
    border: b(C.field),
  );
}

/// Pilihan segmen (radius, label lokasi).
class Choice extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  final Color active;
  const Choice(
    this.text,
    this.on,
    this.onTap, {
    super.key,
    this.active = C.violet,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    child: Tap(
      onTap: onTap,
      height: 44,
      radius: 13,
      color: on ? active : C.bg,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(
        child: Text(text, style: t(13, w5, on ? Colors.white : C.ink)),
      ),
    ),
  );
}

double topInset(BuildContext c) => MediaQuery.paddingOf(c).top;
double bottomInset(BuildContext c) => MediaQuery.paddingOf(c).bottom;

/// Tinggi tab bar + inset bawah; konten diberi ruang sebesar ini.
double tabSpace(BuildContext c) => 86 + bottomInset(c) + 24;
