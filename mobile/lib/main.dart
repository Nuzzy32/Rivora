import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/account.dart';
import 'screens/auth.dart';
import 'screens/emergency.dart';
import 'screens/forecast.dart';
import 'screens/map.dart';
import 'screens/onboarding.dart';
import 'screens/report.dart';
import 'screens/search.dart';
import 'state.dart';
import 'motion.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Diisi lewat: flutter run --dart-define-from-file=env.json (lihat env.example.json).
  const url = String.fromEnvironment('SUPABASE_URL'),
      key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  assert(
    url.isNotEmpty && key.isNotEmpty,
    'Jalankan dengan --dart-define-from-file=env.json',
  );
  await Supabase.initialize(
    url: url,
    publishableKey: key,
    authOptions: const FlutterAuthClientOptions(localStorage: _SecureSession()),
  );
  // Tile yang pernah dilihat dianggap segar 30 hari: tetap tampil saat offline, juga setelah
  // aplikasi ditutup (tile basi tidak dipakai flutter_map tanpa jaringan). Unduh massal dilarang OSM.
  // ponytail: peta baru diperbarui tiap 30 hari; buat MapCachingProvider "offline-first" kalau perlu lebih segar.
  BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: 300000000,
    overrideFreshAge: const Duration(days: 30),
  );
  await app.init();
  runApp(const SigapApp());
}

class SigapApp extends StatelessWidget {
  const SigapApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SIGAP Banjir',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    // PRD §9: ukuran huruf sistem didukung sampai 130%.
    builder: (context, child) =>
        MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
    home: ListenableBuilder(
      listenable: app,
      builder: (context, _) => Shell(),
    ), // tanpa const: harus rebuild tiap state berubah
  );
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = app.screen;
    // Sengaja tanpa const: halaman harus di-build ulang setiap state berubah.
    final page = switch (s) {
      Scr.onboarding => OnboardingScreen(),
      Scr.permission => PermissionScreen(),
      Scr.map => MapScreen(),
      Scr.search => SearchScreen(),
      Scr.forecast => ForecastScreen(),
      Scr.report => ReportScreen(),
      Scr.reportSent => SentScreen(),
      Scr.login => LoginScreen(),
      Scr.account => AccountScreen(),
      Scr.watch => WatchScreen(),
      Scr.notif => NotifScreen(),
      Scr.history => HistoryScreen(),
      Scr.emergency => EmergencyScreen(),
      Scr.profile => ProfileScreen(),
      Scr.forgot => ForgotScreen(),
      Scr.guide => GuideScreen(),
    };
    final tabs = s != Scr.onboarding && s != Scr.permission;
    final sheet = app.selPoint != null
        ? PointSheet(app.selPoint!, key: ValueKey('p${app.selPoint}'))
        : app.selShelter != null
        ? ShelterSheet(app.selShelter!, key: ValueKey('s${app.selShelter}'))
        : null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !app.back()) SystemNavigator.pop();
      },
      child: AnnotatedRegion(
        value: s == Scr.forecast
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: dur(context, 380),
                  reverseDuration: dur(context, 200),
                  transitionBuilder: (child, a) => _PageTransition(
                    animation: a,
                    incoming: child.key == ValueKey(s),
                    dir: app.navDir,
                    child: child,
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: KeyedSubtree(key: ValueKey(s), child: page),
                ),
              ),
              if (tabs)
                Positioned(left: 0, right: 0, bottom: 0, child: TabBar5()),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: sheet == null,
                  child: AnimatedOpacity(
                    opacity: sheet == null ? 0 : 1,
                    duration: dur(context, sheet == null ? 200 : 300),
                    curve: easeOut,
                    child: GestureDetector(
                      onTap: app.back,
                      child: const ColoredBox(color: Color(0x471A1D26)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSwitcher(
                  duration: dur(context, 420),
                  reverseDuration: dur(context, 220),
                  switchInCurve: easeOut,
                  switchOutCurve: easeIn,
                  // Sheet naik dari bawah (asal sentuhan), turun lebih cepat saat ditutup.
                  transitionBuilder: (child, a) => SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                  child: sheet == null
                      ? const SizedBox.shrink()
                      : DragToDismiss(
                          key: sheet.key,
                          onDismiss: app.back,
                          child: sheet,
                        ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: tabTop(context) + 18,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: dur(context, 320),
                      reverseDuration: dur(context, 160),
                      transitionBuilder: materialize(
                        from: const Offset(0, 14),
                        blur: false,
                      ),
                      child: app.toast == null
                          ? const SizedBox.shrink()
                          : Semantics(
                              key: ValueKey(app.toast),
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: C.ink,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: soft(.3, 24, 12, C.ink),
                                ),
                                child: Text(
                                  app.toast!,
                                  textAlign: TextAlign.center,
                                  style: t(
                                    13,
                                    FontWeight.w400,
                                    Colors.white,
                                    1.4,
                                  ),
                                ),
                              ),
                            ),
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
}

/// Transisi halaman. Pindah tab = fade-through (tidak ada arah ruang);
/// masuk sub-layar = geser dari kanan, kembali = dari kiri. Yang keluar hanya memudar & bergeser sedikit.
/// Tanpa blur: blur satu layar penuh (apalagi peta) terlalu berat untuk HP 2 GB RAM.
class _PageTransition extends StatelessWidget {
  final Animation<double> animation;
  final bool incoming;
  final int dir;
  final Widget child;
  const _PageTransition({
    required this.animation,
    required this.incoming,
    required this.dir,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = animation.value;
      if (!incoming) {
        // t berjalan 1 → 0.
        return IgnorePointer(
          child: Opacity(
            opacity: easeOut.transform(t),
            child: Transform.translate(
              offset: Offset(-dir * 24 * (1 - t), 0),
              child: child,
            ),
          ),
        );
      }
      final v = easeOut.transform(t);
      final opacity = dir == 0 ? const Interval(.25, 1).transform(t) : v;
      return Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(dir * 36 * (1 - v), 0),
          child: dir == 0
              ? Transform.scale(scale: .97 + .03 * v, child: child)
              : child,
        ),
      );
    },
  );
}

/// Tab bar mengambang: kapsul biru berisi tombol bulat putih; tab aktif melebar jadi pil
/// berlabel dengan ikon dalam lingkaran berwarna. Lapor selalu menonjol (lingkaran ungu besar),
/// Darurat dikenali dari ikon SOS merah.
class TabBar5 extends StatelessWidget {
  const TabBar5({super.key});

  static const _d = 50.0, _gap = 4.0, _report = 60.0;

  @override
  Widget build(BuildContext context) {
    final tab = tabOf[app.screen];
    final items = [
      (Icons.map_outlined, 'Peta', C.blue, () => app.go(Scr.map)),
      (Icons.cloud_outlined, 'Prakiraan', C.blue, () => app.go(Scr.forecast)),
      (Icons.add_rounded, 'Lapor', C.violet, app.openReport),
      (Icons.person_outline_rounded, 'Akun', C.blue, () => app.go(Scr.account)),
      (Icons.sos_rounded, 'Darurat', C.red, () => app.go(Scr.emergency)),
    ];
    return Container(
      height: tabBarH,
      margin: EdgeInsets.fromLTRB(16, 0, 16, tabGap(context)),
      padding: const EdgeInsets.all((tabBarH - _d) / 2),
      decoration: BoxDecoration(
        color: C.blue,
        borderRadius: BorderRadius.circular(tabBarH / 2),
        boxShadow: soft(.30, 24, 10, C.blue),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Pil aktif mengisi sisa lebar setelah 3 tombol bulat + tombol Lapor.
          final pill = box.maxWidth - 3 * (_d + _gap) - (_report + _gap);
          return Row(
            spacing: _gap,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (i, (icon, label, color, onTap)) in items.indexed)
                i == 2
                    ? _reportBtn(context, tab == i)
                    : _tabItem(
                        context,
                        tab == i && tab != 2,
                        icon,
                        label,
                        color,
                        onTap,
                        // Saat di layar Lapor tidak ada pil; semua tab lain tetap bulat.
                        tab == 2 ? _d : pill,
                      ),
            ],
          );
        },
      ),
    );
  }

  /// Lapor: aksi utama, selalu ditonjolkan (lebih besar, gradien ungu, sedikit keluar kapsul).
  Widget _reportBtn(BuildContext context, bool on) => SizedBox(
    width: _report,
    height: _d,
    child: OverflowBox(maxHeight: _report, child: _reportCircle(context, on)),
  );

  Widget _reportCircle(BuildContext context, bool on) => Tap(
    onTap: app.openReport,
    label: 'Lapor genangan',
    radius: _report / 2,
    pressScale: .9,
    child: AnimatedScale(
      duration: dur(context, 260),
      curve: easeOut,
      scale: on ? 1.06 : 1,
      child: Container(
        width: _report,
        height: _report,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gViolet,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73806EF8),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
      ),
    ),
  );

  Widget _tabItem(
    BuildContext context,
    bool on,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
    double pill,
  ) {
    // Ikon tab biasa gelap; Lapor & Darurat tetap berwarna supaya menonjol.
    final idle = color == C.blue ? C.ink : color;
    return Semantics(
      selected: on,
      child: Tap(
        onTap: onTap,
        label: label,
        radius: _d / 2,
        pressScale: .92,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: dur(context, 320),
            curve: easeOut,
            width: on ? pill : _d,
            height: _d,
            padding: const EdgeInsets.all(4),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_d / 2),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: dur(context, 260),
                  width: _d - 8,
                  height: _d - 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? color : Colors.white,
                  ),
                  child: Icon(icon, size: 22, color: on ? Colors.white : idle),
                ),
                // Label diukur pada lebar akhir pil, lalu tersingkap saat pil melebar.
                Expanded(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: pill - _d,
                    child: AnimatedOpacity(
                      duration: dur(context, on ? 260 : 120),
                      opacity: on ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10, right: 12),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: t(15, w5, C.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Token sesi disimpan di Keychain/Keystore, bukan SharedPreferences (PRD §9).
class _SecureSession extends LocalStorage {
  const _SecureSession();

  static const _store = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() =>
      _store.containsKey(key: supabasePersistSessionKey);

  @override
  Future<String?> accessToken() => _store.read(key: supabasePersistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _store.delete(key: supabasePersistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(key: supabasePersistSessionKey, value: persistSessionString);
}
