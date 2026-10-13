import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final sheet = app.selPoint != null || app.selShelter != null;
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
                child: KeyedSubtree(key: ValueKey(s), child: page),
              ),
              if (tabs)
                Positioned(left: 0, right: 0, bottom: 0, child: TabBar5()),
              if (sheet)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: app.back,
                    child: const ColoredBox(color: Color(0x471A1D26)),
                  ),
                ),
              if (app.selPoint != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PointSheet(app.selPoint!),
                ),
              if (app.selShelter != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ShelterSheet(app.selShelter!),
                ),
              if (app.toast != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 104 + bottomInset(context),
                  child: IgnorePointer(
                    child: Center(
                      child: Semantics(
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
                            style: t(13, FontWeight.w400, Colors.white, 1.4),
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

/// Tab bar: Peta, Prakiraan, Lapor (tengah, menonjol), Akun, Darurat.
class TabBar5 extends StatelessWidget {
  const TabBar5({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = tabOf[app.screen];
    Color c(int i) =>
        tab == i ? const Color(0xFF3F7FF0) : const Color(0xFF757C90);
    Widget item(int i, IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: Semantics(
            selected: tab == i,
            child: Tap(
              onTap: onTap,
              height: 60,
              radius: 16,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: c(i)),
                  const SizedBox(height: 2),
                  Text(label, style: t(11, w6, c(i))),
                ],
              ),
            ),
          ),
        );
    final sos = tab == 4;
    return Container(
      height: 86 + bottomInset(context),
      padding: EdgeInsets.fromLTRB(6, 0, 6, 14 + bottomInset(context)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: soft(.10, 30, -10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          item(0, Icons.map_outlined, 'Peta', () => app.go(Scr.map)),
          item(
            1,
            Icons.umbrella_outlined,
            'Prakiraan',
            () => app.go(Scr.forecast),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Lapor genangan',
              child: GestureDetector(
                onTap: app.openReport,
                behavior: HitTestBehavior.opaque,
                child: OverflowBox(
                  maxHeight: 120,
                  child: Transform.translate(
                    offset: const Offset(0, -14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: gViolet,
                            borderRadius: BorderRadius.circular(21),
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x73806EF8),
                                blurRadius: 22,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: Text('Lapor', style: t(11, w6, c(2))),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          item(
            3,
            Icons.person_outline_rounded,
            'Akun',
            () => app.go(Scr.account),
          ),
          Expanded(
            child: Semantics(
              selected: sos,
              child: Tap(
                onTap: () => app.go(Scr.emergency),
                height: 60,
                radius: 16,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 28,
                      decoration: BoxDecoration(
                        color: sos ? C.red : C.redTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.sos_rounded,
                        size: 20,
                        color: sos ? Colors.white : C.red,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Darurat', style: t(11, w6, C.red)),
                  ],
                ),
              ),
            ),
          ),
        ],
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
