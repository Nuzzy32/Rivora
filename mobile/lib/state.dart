import 'package:flutter/services.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, Supabase;
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'theme.dart';

enum Scr {
  onboarding,
  permission,
  map,
  search,
  forecast,
  report,
  reportSent,
  login,
  account,
  watch,
  notif,
  history,
  emergency,
  profile,
  forgot,
  guide,
}

/// Tab aktif per layar (tab bar 5 item, PRD §7).
const tabOf = {
  Scr.map: 0,
  Scr.search: 0,
  Scr.forecast: 1,
  Scr.report: 2,
  Scr.reportSent: 2,
  Scr.login: 3,
  Scr.account: 3,
  Scr.watch: 3,
  Scr.notif: 3,
  Scr.history: 3,
  Scr.profile: 3,
  Scr.forgot: 3,
  Scr.emergency: 4,
  Scr.guide: 4,
};

/// Kedalaman layar untuk arah transisi: 0 = akar tab, 1 = sub-layar, 2 = sub-sub.
const depthOf = {
  Scr.onboarding: 0,
  Scr.permission: 1,
  Scr.map: 0,
  Scr.forecast: 0,
  Scr.report: 0,
  Scr.account: 0,
  Scr.emergency: 0,
  Scr.search: 1,
  Scr.reportSent: 1,
  Scr.login: 1,
  Scr.watch: 1,
  Scr.notif: 1,
  Scr.history: 1,
  Scr.profile: 1,
  Scr.guide: 1,
  Scr.forgot: 2,
};

final app = AppState();

/// Satu state untuk seluruh aplikasi, mengikuti struktur prototipe di Claude Design.
/// ponytail: satu ChangeNotifier global; pecah per fitur kalau rebuild mulai terasa berat.
class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  Scr screen = Scr.onboarding;
  int navDir = 0; // 1 = masuk lebih dalam, -1 = kembali, 0 = pindah tab
  int onb = 0;
  bool permNotif = false; // langkah izin kedua (notifikasi)

  LatLng? userPos;
  bool locDenied = false;
  bool _locForever = false;
  LatLng? mapCenter;
  bool centeredOnUser =
      false; // sekali saja: setelahnya posisi peta milik pengguna
  double mapZoom = 13.5;

  User? user;
  bool get loggedIn => user != null;
  bool notifEnabled = true;

  List<FloodPoint> points = [];
  bool pointsLoading = true;
  bool offline = false;
  DateTime? pointsFetchedAt;
  LatLng? _pointsAt;
  List<Shelter> shelters = [];
  List<Contact> contacts = [];
  List<RiskArea> risk = [];

  Forecast? forecast;
  String district = 'Gayungan';
  int fcSlot = 0;
  bool fcLoading = true;
  bool fcStale = false;

  final layers = <String>{'flood'};
  int? selPoint;
  String? selShelter;
  bool legend = false;

  Radar? radar;
  String radarState = 'idle'; // idle | loading | ready | unavailable
  int radarFrame = 0;
  Timer? _radarTimer;
  bool get radarPlaying => _radarTimer != null;

  List<MyReport> reports = [];
  List<Notif> notifs = [];
  List<WatchLoc> watch = [];

  String? toast;
  Timer? _toastTimer;
  Scr authReturn = Scr.account;
  String? authReason; // report | watch | null
  Scr notifReturn = Scr.map;
  FloodPoint? reportFor; // "Laporkan kondisi terbaru" dari detail lokasi
  ({FloodPoint point, int depth, int photos})? sent;
  int guideTab = 0;
  Set<String> bag = {};
  String forgotEmail = '';
  bool recovery = false; // dibuka dari link reset kata sandi di email

  int get unread => loggedIn ? notifs.where((n) => n.unread).length : 0;
  LatLng get center => userPos ?? balaiKota;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    bag = (_prefs.getStringList('bag') ?? []).toSet();
    if (_prefs.getBool('onboarded') ?? false) {
      screen = Scr.map;
      locate(ask: false);
    }
    Supabase.instance.client.auth.onAuthStateChange.listen((d) {
      if (d.event == AuthChangeEvent.passwordRecovery) {
        recovery = true;
        go(Scr.forgot);
      }
    });
    _load();
  }

  Future<void> _load() async {
    try {
      user = await Api.currentUser();
      if (user != null) await _loadUserData();
      final r = await Future.wait([
        Api.shelters(),
        Api.contacts(),
        Api.riskAreas(),
        Api.settings(),
      ]);
      shelters = r[0] as List<Shelter>;
      contacts = r[1] as List<Contact>;
      risk = r[2] as List<RiskArea>;
    } on ApiError catch (e) {
      showToast(e.message);
    }
    await loadPoints(mapCenter ?? center);
    loadForecast(district);
  }

  /// GET titik genangan dalam 10 km. Gagal = tetap tampilkan data terakhir + tanda offline (US-01).
  Future<void> loadPoints(LatLng at) async {
    _pointsAt = at;
    try {
      points = await Api.floodPoints(at);
      pointsFetchedAt = Api.pointsCachedAt ?? DateTime.now();
      offline = Api.pointsCachedAt != null;
    } on ApiError {
      offline = true;
    }
    pointsLoading = false;
    notifyListeners();
  }

  /// Muat ulang saat peta digeser cukup jauh dari titik muat terakhir.
  void mapMoved(LatLng c) {
    if (_pointsAt == null || meters(c, _pointsAt!) > 4000) loadPoints(c);
  }

  Future<void> _loadUserData() async {
    final r = await Future.wait([
      Api.myReports(),
      Api.notifications(),
      Api.watchLocations(),
    ]);
    reports = r[0] as List<MyReport>;
    notifs = r[1] as List<Notif>;
    watch = r[2] as List<WatchLoc>;
  }

  Future<void> loadForecast(String d) async {
    district = d;
    fcSlot = 0;
    fcLoading = true;
    notifyListeners();
    try {
      forecast = await Api.forecast(d);
      fcStale = forecast?.stale ?? false;
    } catch (_) {
      fcStale =
          forecast !=
          null; // US-09: tampilkan cache terakhir, bukan layar kosong
    }
    fcLoading = false;
    notifyListeners();
  }

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  void go(Scr s) {
    selPoint = null;
    selShelter = null;
    legend = false;
    if (s != Scr.map) stopRadar();
    if (s != screen) navDir = (depthOf[s]! - depthOf[screen]!).sign;
    screen = s;
    notifyListeners();
  }

  /// Tombol kembali Android. false = keluar aplikasi.
  bool back() {
    if (selPoint != null || selShelter != null) {
      set(() => selPoint = selShelter = null);
      return true;
    }
    final to = switch (screen) {
      Scr.onboarding || Scr.permission || Scr.map => null,
      Scr.login =>
        const [Scr.report, Scr.watch, Scr.notif].contains(authReturn)
            ? Scr.map
            : authReturn,
      Scr.watch || Scr.history || Scr.profile => Scr.account,
      Scr.notif => notifReturn,
      Scr.forgot => Scr.login,
      Scr.guide => Scr.emergency,
      _ => Scr.map,
    };
    if (to == null) return false;
    go(to);
    return true;
  }

  void showToast(String msg) {
    _toastTimer?.cancel();
    toast = msg;
    notifyListeners();
    _toastTimer = Timer(
      const Duration(milliseconds: 2600),
      () => set(() => toast = null),
    );
  }

  // --- Onboarding & izin
  Future<void> finishOnboarding() async {
    await _prefs.setBool('onboarded', true);
    go(Scr.map);
  }

  Future<void> locate({bool ask = true}) async {
    var p = await Geolocator.checkPermission();
    if (ask && p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    _locForever = p == LocationPermission.deniedForever;
    if (p == LocationPermission.denied ||
        _locForever ||
        !await Geolocator.isLocationServiceEnabled()) {
      set(() => locDenied = true);
      return;
    }
    locDenied = false;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      // Wilayah awal hanya Surabaya: di luar kota, peta tetap dipusatkan ke Balai Kota.
      userPos = meters(here, balaiKota) < 40000 ? here : null;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> enableLocation() async {
    if (_locForever) {
      showToast('Buka Pengaturan HP untuk mengizinkan lokasi');
      await Geolocator.openAppSettings();
      return;
    }
    await locate();
    if (!locDenied) showToast('Lokasi aktif');
  }

  // --- Peta
  void toggleLayer(String k) {
    HapticFeedback.selectionClick();
    if (!layers.remove(k)) layers.add(k);
    if (k == 'radar') layers.contains('radar') ? _loadRadar() : stopRadar();
    notifyListeners();
  }

  Future<void> _loadRadar() async {
    if (radarState == 'ready') return;
    set(() => radarState = 'loading');
    try {
      radar = await Api.radar();
      radarFrame = radar!.frames.length - 1;
      radarState = 'ready';
    } catch (_) {
      radarState = 'unavailable';
    }
    notifyListeners();
  }

  void toggleRadarPlay() {
    if (radarPlaying) return stopRadar();
    final last = radar!.frames.length - 1;
    if (radarFrame >= last) radarFrame = 0;
    _radarTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      radarFrame++;
      if (radarFrame >= last) stopRadar();
      notifyListeners();
    });
    notifyListeners();
  }

  void stopRadar() {
    _radarTimer?.cancel();
    _radarTimer = null;
    notifyListeners();
  }

  void openPoint(int id) {
    final p = points.where((x) => x.id == id).firstOrNull;
    if (p == null) return showToast('Lokasi ini sudah tidak ada di peta');
    centeredOnUser = true;
    mapCenter = p.pos;
    go(Scr.map);
    set(() => selPoint = id);
  }

  void openShelter(Shelter s) {
    centeredOnUser = true;
    layers.add(s.type);
    mapCenter = s.pos;
    go(Scr.map);
    set(() => selShelter = s.id);
  }

  List<FloodPoint> get nearby => points
      .where((p) => !p.receded && p.depth > 0 && meters(p.pos, center) <= 5000)
      .toList();

  // --- Akun
  void needLogin(Scr ret, String? reason) {
    authReturn = ret;
    authReason = reason;
    go(Scr.login);
  }

  Future<void> signedIn(User u, {required bool isNew}) async {
    user = u;
    await _loadUserData();
    showToast(isNew ? 'Akun dibuat. Selamat datang!' : 'Berhasil masuk');
    go(authReturn);
  }

  void _signedOut(String msg) {
    user = null;
    reports = [];
    notifs = [];
    watch = [];
    showToast(msg);
    go(Scr.account);
  }

  Future<void> logout() async {
    await Api.logout();
    _signedOut('Kamu keluar. Sekarang mode Tamu.');
  }

  void accountDeleted() => _signedOut('Akun dan semua laporanmu sudah dihapus');

  void openReport([FloodPoint? p]) {
    reportFor = p;
    if (!loggedIn) return needLogin(Scr.report, 'report');
    go(Scr.report);
  }

  Future<void> reportSent(int pointId, LatLng at, int depth, int photos) async {
    await loadPoints(at);
    reports = await Api.myReports();
    final p = points.where((x) => x.id == pointId).firstOrNull;
    if (p == null) return go(Scr.history);
    sent = (point: p, depth: depth, photos: photos);
    reportFor = null;
    go(Scr.reportSent);
  }

  /// "Pantau" di detail lokasi = lokasi pantauan radius 500 m di titik itu (notifikasi lewat US-07).
  WatchLoc? watchOf(FloodPoint p) =>
      watch.where((w) => meters(w.pos, p.pos) < 50).firstOrNull;

  Future<void> toggleWatchPoint(FloodPoint p) async {
    if (!loggedIn) {
      showToast('Masuk dulu untuk memantau lokasi');
      return needLogin(Scr.map, 'watch');
    }
    final w = watchOf(p);
    try {
      if (w != null) {
        await Api.deleteWatch(w.id);
        watch = [...watch]..remove(w);
        showToast('Berhenti memantau ${p.name}');
      } else {
        final label = p.name.length > 24
            ? '${p.name.substring(0, 23)}…'
            : p.name;
        watch = [
          ...watch,
          await Api.addWatch(label, '${p.name}, ${p.district}', p.pos, 500),
        ];
        showToast('Kamu akan dikabari saat status ${p.name} berubah');
      }
    } on ApiError catch (e) {
      showToast(e.message);
    }
  }

  /// Status lokasi pantauan: genangan terparah dalam radius.
  FloodPoint? worstNear(WatchLoc w) {
    final inside =
        points.where((p) => meters(p.pos, w.pos) <= w.radius).toList()..sort(
          (a, b) =>
              (a.receded ? -1 : a.depth).compareTo(b.receded ? -1 : b.depth),
        );
    return inside.lastOrNull;
  }

  void toggleBag(String item) {
    if (!bag.remove(item)) bag.add(item);
    _prefs.setStringList('bag', bag.toList());
    notifyListeners();
  }

  void openGuide(int tab) {
    guideTab = tab;
    go(Scr.guide);
  }

  // --- Aksi luar aplikasi
  Future<void> call(String number) async {
    final ok = await launchUrl(
      Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^0-9+]'), '')),
    );
    if (!ok) showToast('Tidak bisa membuka dialer');
  }

  Future<void> directions(LatLng to) async {
    final ok = await launchUrl(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}',
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) showToast('Tidak bisa membuka Google Maps');
  }

  /// PRD US-15: tanpa nama pelapor, koordinat pelapor, atau foto.
  Future<void> share(FloodPoint p) async {
    final v = vers[p.verification]!.label;
    final text = p.receded
        ? '${p.name} sudah surut sejak ${hm(p.recededAt!)} · ${p.source}. Cek kondisi terbaru di aplikasi SIGAP Banjir.'
        : '${p.name}, Kec. ${p.district}: tergenang ${depths[p.depth].label.toLowerCase()} (${depths[p.depth].cm}) · '
              '${p.stale ? 'Perlu Konfirmasi · ' : ''}$v · diperbarui ${hm(p.updatedAt)} · sumber ${p.source}. Cek kondisi terbaru di aplikasi SIGAP Banjir.';
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
