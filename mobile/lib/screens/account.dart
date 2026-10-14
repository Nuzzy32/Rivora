import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';
import 'search.dart' show watchIcon;

String initials(String n) {
  final s = n
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isEmpty ? '' : w[0])
      .join()
      .toUpperCase();
  return s.isEmpty ? '?' : s;
}

/// M12 Akun: mode Tamu atau profil warga.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final u = app.user;
    final rows = u != null
        ? [
            (
              Icons.add_location_alt_rounded,
              'Lokasi Pantauan',
              '${app.watch.length} dari 5 lokasi',
              C.violetTint,
              C.violetMid,
              Icons.chevron_right_rounded,
              () => app.go(Scr.watch),
            ),
            (
              Icons.notifications_rounded,
              'Notifikasi',
              app.unread > 0
                  ? '${app.unread} belum dibaca'
                  : 'Semua sudah dibaca',
              C.blueTint2,
              C.blueInk,
              Icons.chevron_right_rounded,
              () {
                app.notifReturn = Scr.account;
                app.go(Scr.notif);
              },
            ),
            (
              Icons.history_rounded,
              'Riwayat Laporanku',
              '${app.reports.length} laporan',
              C.amberTint,
              C.amberInk,
              Icons.chevron_right_rounded,
              () => app.go(Scr.history),
            ),
          ]
        : [
            (
              Icons.add_location_alt_rounded,
              'Lokasi Pantauan',
              'Perlu masuk',
              C.bg,
              C.muted,
              Icons.lock_rounded,
              () => app.needLogin(Scr.watch, 'watch'),
            ),
            (
              Icons.notifications_rounded,
              'Notifikasi',
              'Perlu masuk',
              C.bg,
              C.muted,
              Icons.lock_rounded,
              () => app.needLogin(Scr.notif, 'watch'),
            ),
            (
              Icons.call_rounded,
              'Kontak darurat',
              '112, BPBD, Damkar',
              C.redTint,
              C.red,
              Icons.chevron_right_rounded,
              () => app.go(Scr.emergency),
            ),
          ];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        topInset(context) + 12,
        20,
        tabSpace(context),
      ),
      children: stagger([
        Text('Akun', style: t(24, w7)),
        const SizedBox(height: 16),
        if (u == null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: gBlueSoft,
              borderRadius: BorderRadius.circular(28),
              boxShadow: soft(.3, 30, 18, C.blue),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconTile(
                      Icons.person_rounded,
                      Colors.white.withValues(alpha: .3),
                      Colors.white,
                      size: 52,
                      iconSize: 28,
                      radius: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mode Tamu', style: t(17, w6, Colors.white)),
                          Text(
                            'Kamu bisa lihat peta, prakiraan, dan posko.',
                            style: t(13, FontWeight.w400, Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Masuk untuk mengirim laporan, menyimpan lokasi pantauan, dan menerima notifikasi.',
                  style: t(13, FontWeight.w400, Colors.white, 1.5),
                ),
                const SizedBox(height: 12),
                Btn(
                  'Masuk atau daftar',
                  height: 48,
                  radius: 16,
                  fontSize: 14,
                  color: Colors.white,
                  fg: C.blueMid,
                  onTap: () => app.needLogin(Scr.account, null),
                ),
              ],
            ),
          )
        else
          Box(
            radius: 28,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: gViolet,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(
                      initials(u.name),
                      style: t(20, w7, Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, style: t(17, w6)),
                      Text(
                        '${u.email} · Warga',
                        style: t(13, FontWeight.w400, C.muted),
                      ),
                      if (u.pendingEmail != null)
                        Text(
                          'Menunggu verifikasi: ${u.pendingEmail}',
                          style: t(11, FontWeight.w400, C.amberInk),
                        ),
                    ],
                  ),
                ),
                Tap(
                  onTap: () => app.go(Scr.profile),
                  height: 44,
                  radius: 14,
                  color: C.bg,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: C.blueInk,
                      ),
                      const SizedBox(width: 4),
                      Text('Ubah', style: t(13, w6, C.blueInk)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Box(
          radius: 26,
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (final (icon, label, sub, bg, fg, trail, onTap) in rows)
                Tap(
                  onTap: onTap,
                  radius: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        IconTile(icon, bg, fg, size: 42, iconSize: 21),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: t(14, w6)),
                              Text(sub, style: t(12, FontWeight.w400, C.muted)),
                            ],
                          ),
                        ),
                        Icon(trail, size: 20, color: C.faint),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (u != null) ...[
          const SizedBox(height: 16),
          Box(
            radius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifikasi genangan', style: t(14, w6)),
                      Text(
                        'Selutut ke atas, dari laporan Terverifikasi atau Resmi saja',
                        style: t(12, FontWeight.w400, C.muted, 1.45),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: app.notifEnabled,
                  activeTrackColor: C.blue,
                  onChanged: (v) => app.set(() => app.notifEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Btn(
                  'Keluar',
                  height: 52,
                  radius: 18,
                  fontSize: 14,
                  color: Colors.white,
                  fg: C.ink,
                  shadow: soft(.08, 16, 6),
                  onTap: app.logout,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Btn(
                  'Hapus akun',
                  height: 52,
                  radius: 18,
                  fontSize: 14,
                  fg: C.red,
                  onTap: () => _deleteAccount(context),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: app.openPrivacy,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(
              Icons.privacy_tip_outlined,
              size: 18,
              color: C.muted,
            ),
            label: Text('Kebijakan privasi', style: t(13, w6, C.sub)),
          ),
        ),
      ]),
    );
  }

  /// PRD US-06: konfirmasi + wajib ketik ulang kata sandi.
  void _deleteAccount(BuildContext context) {
    var step = 1;
    var busy = false;
    String? err;
    final pw = TextEditingController();
    showDialog(
      context: context,
      barrierColor: const Color(0x731A1D26),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const IconTile(
                      Icons.warning_rounded,
                      C.redTint,
                      C.red,
                      size: 52,
                      iconSize: 26,
                      radius: 18,
                    ),
                    const Spacer(),
                    Text('Langkah $step dari 2', style: t(12, w6, C.muted)),
                  ],
                ),
                const SizedBox(height: 14),
                if (step == 1) ...[
                  Text('Hapus akun?', style: t(20, w7)),
                  const SizedBox(height: 4),
                  Text(
                    'Yang ikut terhapus:',
                    style: t(14, FontWeight.w400, C.body),
                  ),
                  const SizedBox(height: 10),
                  for (final (icon, text) in [
                    (
                      Icons.description_rounded,
                      '${app.reports.length} laporan, dari peta dan riwayat',
                    ),
                    (
                      Icons.location_off_rounded,
                      '${app.watch.length} lokasi pantauan dan semua notifikasi',
                    ),
                    (
                      Icons.devices_rounded,
                      'Profil dan sesi login di semua perangkat',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: C.red),
                          const SizedBox(width: 10),
                          Expanded(child: Text(text, style: t(13))),
                        ],
                      ),
                    ),
                  const Note('Tindakan ini tidak bisa dibatalkan.'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Btn(
                          'Batal',
                          height: 52,
                          radius: 18,
                          fontSize: 14,
                          color: C.bg,
                          fg: C.ink,
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Btn(
                          'Lanjutkan',
                          height: 52,
                          radius: 18,
                          fontSize: 14,
                          color: Colors.white,
                          fg: C.red,
                          border: Border.all(color: C.redBright, width: 1.5),
                          onTap: () => setD(() => step = 2),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text('Konfirmasi terakhir', style: t(20, w7)),
                  const SizedBox(height: 6),
                  Text(
                    'Ketik ulang kata sandi untuk menghapus akun ${app.user?.email} secara permanen.',
                    style: t(14, FontWeight.w400, C.body, 1.55),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pw,
                    obscureText: true,
                    autofocus: true,
                    onChanged: (_) => setD(() => err = null),
                    decoration: inputDeco('Kata sandi', err != null),
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(err!, style: t(12, FontWeight.w400, C.red)),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Btn(
                          'Kembali',
                          height: 52,
                          radius: 18,
                          fontSize: 14,
                          color: C.bg,
                          fg: C.ink,
                          onTap: () => setD(() => step = 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 14,
                        child: Btn(
                          busy ? 'Menghapus…' : 'Hapus permanen',
                          height: 52,
                          radius: 18,
                          fontSize: 14,
                          color: pw.text.length >= 8 && !busy
                              ? const Color(0xFFD93439)
                              : const Color(0xFFEBB8BA),
                          onTap: pw.text.length < 8 || busy
                              ? null
                              : () async {
                                  setD(() => busy = true);
                                  try {
                                    await Api.deleteAccount(pw.text);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    app.accountDeleted();
                                  } on ApiError catch (e) {
                                    setD(() {
                                      err = e.message;
                                      busy = false;
                                    });
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(pw.dispose);
  }
}

/// M12 Edit Profil.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: app.user!.name);
  late final _mail = TextEditingController(
    text: app.user!.pendingEmail ?? app.user!.email,
  );
  final _cur = TextEditingController(), _nw = TextEditingController();
  Map<String, String> _err = {};

  @override
  void dispose() {
    for (final c in [_name, _mail, _cur, _nw]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    final e = <String, String>{};
    if (_name.text.trim().length < 2) e['name'] = 'Nama minimal 2 huruf';
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_mail.text.trim())) {
      e['email'] = 'Format email belum benar';
    }
    if (_cur.text.isNotEmpty || _nw.text.isNotEmpty) {
      if (_cur.text.length < 8) e['cur'] = 'Masukkan kata sandi saat ini';
      if (_nw.text.length < 8) {
        e['nw'] = 'Kata sandi baru minimal 8 karakter';
      } else if (_nw.text == _cur.text) {
        e['nw'] = 'Kata sandi baru harus berbeda';
      }
    }
    setState(() => _err = e);
    if (e.isNotEmpty) return;
    final u = app.user!, mail = _mail.text.trim(), changed = mail != u.email;
    setState(() => _busy = true);
    try {
      app.user = await Api.updateProfile(
        name: _name.text.trim(),
        email: mail,
        currentPw: _nw.text.isEmpty ? null : _cur.text,
        newPw: _nw.text.isEmpty ? null : _nw.text,
      );
    } on ApiError catch (x) {
      if (mounted) setState(() => _busy = false);
      return app.showToast(
        x.code == 'invalid_credentials'
            ? 'Kata sandi saat ini salah.'
            : x.message,
      );
    }
    app.showToast(
      changed
          ? 'Profil disimpan. Buka link verifikasi di $mail'
          : _nw.text.isNotEmpty
          ? 'Profil dan kata sandi disimpan'
          : 'Profil disimpan',
    );
    app.go(Scr.account);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      20,
      topInset(context) + 8,
      20,
      tabSpace(context) + MediaQuery.viewInsetsOf(context).bottom,
    ),
    children: stagger([
      Header('Edit Profil', onBack: () => app.go(Scr.account)),
      const SizedBox(height: 16),
      Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: gViolet,
            borderRadius: BorderRadius.circular(30),
            boxShadow: soft(.35, 30, 16, C.violet),
          ),
          child: Center(
            child: Text(initials(_name.text), style: t(30, w7, Colors.white)),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Box(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Field(
              'Nama',
              _name,
              hint: 'Nama lengkap',
              error: _err['name'],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Field(
              'Email',
              _mail,
              hint: 'nama@email.com',
              error: _err['email'],
              type: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
            ),
            if (_mail.text.trim() != app.user!.email) ...[
              const SizedBox(height: 14),
              const Note(
                'Kami kirim link verifikasi ke email baru. Email lama tetap dipakai sampai link itu dibuka.',
                bg: C.blueTint2,
                fg: C.blueInk,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      Box(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ganti kata sandi', style: t(14, w6)),
            Text(
              'Opsional. Kosongkan kalau tidak ingin mengganti.',
              style: t(12, FontWeight.w400, C.muted),
            ),
            const SizedBox(height: 14),
            Field(
              'Kata sandi saat ini',
              _cur,
              hint: '••••••••',
              error: _err['cur'],
              obscure: true,
              autofill: const [AutofillHints.password],
            ),
            const SizedBox(height: 14),
            Field(
              'Kata sandi baru',
              _nw,
              hint: 'Minimal 8 karakter',
              error: _err['nw'],
              obscure: true,
              autofill: const [AutofillHints.newPassword],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Btn.primary(_busy ? 'Menyimpan…' : 'Simpan perubahan', onTap: _save),
    ]),
  );
}

/// M09: maks 5 lokasi pantauan; tambah via lokasi saat ini, cari alamat, atau geser pin.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  bool _adding = false, _err = false;
  int? _editing;
  String _label = 'Rumah', _mode = 'search';
  int _radius = 1000;
  final _custom = TextEditingController(),
      _q = TextEditingController(),
      _rename = TextEditingController();
  (String, LatLng)? _picked;
  late LatLng _mapPin = app.center;
  List<(String, LatLng)> _hits = [];
  Timer? _wait, _pinWait;
  String? _pinLabel;

  @override
  void initState() {
    super.initState();
    _labelPin();
  }

  /// Nama desa di bawah pin peta, ditunggu sebentar setelah peta berhenti digeser.
  void _labelPin() {
    _pinWait?.cancel();
    _pinWait = Timer(const Duration(milliseconds: 450), () async {
      final p = _mapPin;
      final s = await _nearAddr(p);
      if (mounted && p == _mapPin) setState(() => _pinLabel = s);
    });
  }

  /// Cari kelurahan/kecamatan/kota se-Indonesia (titik tengahnya; geser di "Peta" untuk titik persis).
  void _search(String q) {
    _wait?.cancel();
    if (q.trim().length < 3) return setState(() => _hits = []);
    _wait = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Api.searchRegions(q);
        if (mounted && _q.text == q) {
          setState(
            () => _hits = [
              for (final p in r)
                if (p.pos != null) (p.label, p.pos!),
            ],
          );
        }
      } on ApiError catch (_) {}
    });
  }

  static const _radii = [(500, '500 m'), (1000, '1 km'), (2000, '2 km')];

  @override
  void dispose() {
    _wait?.cancel();
    _pinWait?.cancel();
    _custom.dispose();
    _q.dispose();
    _rename.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _adding = _err = false;
    _label = 'Rumah';
    _mode = 'search';
    _radius = 1000;
    _picked = null;
    _hits = [];
    _custom.clear();
    _q.clear();
  });

  Future<String> _nearAddr(LatLng p) async {
    try {
      final v = await Api.villageAt(p);
      if (v != null) return 'Sekitar ${v.label}';
    } catch (_) {} // offline/gagal: pakai koordinat
    return 'Titik di peta (${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)})';
  }

  Future<void> _confirm() async {
    (String, LatLng)? at;
    if (_mode == 'current') {
      if (app.userPos == null) {
        return app.showToast('Lokasi belum aktif. Pilih lewat Cari atau Peta.');
      }
      at = (await _nearAddr(app.userPos!), app.userPos!);
    } else if (_mode == 'map') {
      at = (await _nearAddr(_mapPin), _mapPin);
    } else {
      at = _picked;
      if (at == null) return setState(() => _err = true);
    }
    final label = _label == 'Lainnya'
        ? (_custom.text.trim().isEmpty ? 'Lokasi lain' : _custom.text.trim())
        : _label;
    try {
      final w = await Api.addWatch(label, at.$1, at.$2, _radius);
      app.set(() => app.watch = [...app.watch, w]);
      app.showToast('$label disimpan ke pantauan');
      _reset();
    } on ApiError catch (x) {
      app.showToast(x.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = app.watch.length;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        topInset(context) + 8,
        20,
        tabSpace(context) + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: stagger([
        Header(
          'Lokasi Pantauan',
          sub: '$n dari 5 lokasi',
          onBack: () => app.go(Scr.account),
        ),
        const SizedBox(height: 16),
        if (n == 0 && !_adding)
          const EmptyCard(
            Icons.add_location_alt_rounded,
            'Belum ada lokasi pantauan',
            'Simpan rumah, kampus, atau kantor. Kami kabari saat ada genangan selutut ke atas di dekatnya.',
            iconColor: C.violetLight,
          ),
        for (final w in app.watch) ...[
          _watchCard(w),
          const SizedBox(height: 16),
        ],
        if (_adding) ...[_addForm(), const SizedBox(height: 16)],
        if (n >= 5)
          const Note(
            'Batas 5 lokasi tercapai. Hapus salah satu untuk menambah lokasi baru.',
            bg: C.grayTint,
            fg: C.sub,
          ),
        if (n < 5 && !_adding)
          Tap(
            onTap: () => setState(() {
              _adding = true;
              _editing = null;
            }),
            height: 54,
            radius: 20,
            border: Border.all(color: C.violetLight, width: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, size: 20, color: C.violetMid),
                const SizedBox(width: 6),
                Text('Tambah lokasi', style: t(14, w6, C.violetMid)),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _watchCard(WatchLoc w) {
    final p = app.worstNear(w);
    final d = depths[p == null || p.receded ? 0 : p.depth];
    final status = p == null
        ? 'Aman · tidak ada genangan'
        : p.receded
        ? 'Sudah surut'
        : '${d.label} di dekatnya';
    final ed = _editing == w.id;
    return Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                watchIcon(w.label),
                C.violetTint,
                C.violetMid,
                size: 48,
                iconSize: 24,
                radius: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.label, style: t(15, w6)),
                    Text(
                      '${w.place} · radius ${km(w.radius.toDouble())}',
                      style: t(12, FontWeight.w400, C.muted),
                    ),
                    const SizedBox(height: 3),
                    Pill(status, d.tint, d.ink),
                  ],
                ),
              ),
              SquareBtn(
                Icons.tune_rounded,
                size: 44,
                shadowed: false,
                bg: ed ? C.violet : C.bg,
                fg: ed ? Colors.white : C.muted,
                label: 'Ubah ${w.label}',
                onTap: () {
                  _rename.text = w.label;
                  setState(() {
                    _editing = ed ? null : w.id;
                    _adding = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              SquareBtn(
                Icons.delete_outline_rounded,
                size: 44,
                shadowed: false,
                bg: C.bg,
                fg: C.muted,
                label: 'Hapus ${w.label}',
                onTap: () async {
                  try {
                    await Api.deleteWatch(w.id);
                    _editing = null;
                    app.set(() => app.watch = [...app.watch]..remove(w));
                    app.showToast('${w.label} dihapus dari pantauan');
                  } on ApiError catch (x) {
                    app.showToast(x.message);
                  }
                },
              ),
            ],
          ),
          if (ed) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: C.line),
            ),
            Text('Nama', style: t(12, w6, C.sub)),
            const SizedBox(height: 8),
            TextField(
              controller: _rename,
              maxLength: 24,
              style: t(14),
              decoration: inputDeco(
                'Contoh: Rumah Ibu',
              ).copyWith(counterText: ''),
              onSubmitted: (v) => _renameTo(w, v),
              onTapOutside: (_) => _renameTo(w, _rename.text),
            ),
            const SizedBox(height: 12),
            Text('Ubah radius pantau', style: t(12, w6, C.sub)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (r, l) in _radii) ...[
                  Expanded(
                    child: Choice(l, w.radius == r, () async {
                      final old = w.radius;
                      app.set(() => w.radius = r);
                      try {
                        await Api.updateWatch(w);
                        app.showToast('Radius ${w.label} diubah ke $l');
                      } on ApiError catch (x) {
                        app.set(() => w.radius = old);
                        app.showToast(x.message);
                      }
                    }),
                  ),
                  if (r != 2000) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Notifikasi dikirim saat ada genangan selutut ke atas di dalam radius ini.',
              style: t(11, FontWeight.w400, C.muted, 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _renameTo(WatchLoc w, String v) async {
    final name = v.trim(), old = w.label;
    if (name.isEmpty || name == old) return;
    app.set(() => w.label = name);
    try {
      await Api.updateWatch(w);
      app.showToast('Nama diubah ke $name');
    } on ApiError catch (x) {
      app.set(() => w.label = old);
      app.showToast(x.message);
    }
  }

  Widget _addForm() {
    final q = _q.text.trim();
    final suggest = _hits.take(5).toList();
    return Box(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Lokasi baru', style: t(15, w6))),
              TextButton(
                onPressed: _reset,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text('Batal', style: t(13, w5, C.body)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Nama', style: t(12, w6, C.sub)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in const ['Rumah', 'Kampus', 'Kantor', 'Lainnya'])
                Choice(l, _label == l, () => setState(() => _label = l)),
            ],
          ),
          if (_label == 'Lainnya') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _custom,
              maxLength: 24,
              style: t(14),
              decoration: inputDeco(
                'Contoh: Rumah Ibu',
              ).copyWith(counterText: ''),
            ),
          ],
          const SizedBox(height: 16),
          Text('Titik lokasi', style: t(12, w6, C.sub)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                for (final (m, l, icon) in const [
                  ('current', 'Saat ini', Icons.my_location_rounded),
                  ('search', 'Cari', Icons.search_rounded),
                  ('map', 'Peta', Icons.map_outlined),
                ])
                  Expanded(
                    child: Semantics(
                      selected: _mode == m,
                      child: Tap(
                        onTap: () => setState(() {
                          _mode = m;
                          _err = false;
                        }),
                        height: 44,
                        radius: 11,
                        color: _mode == m ? Colors.white : Colors.transparent,
                        shadow: _mode == m ? soft(.12, 10, 4) : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 16,
                              color: _mode == m ? C.violetInk : C.body,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l,
                              style: t(
                                12,
                                w6,
                                _mode == m ? C.violetInk : C.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_mode == 'current')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.my_location_rounded,
                    size: 20,
                    color: C.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: app.userPos == null
                        ? Text(
                            'Lokasi belum aktif. Aktifkan izin lokasi atau pilih lewat Cari / Peta.',
                            style: t(13, FontWeight.w400, C.body, 1.4),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.herePlace != null
                                    ? 'Sekitar ${app.herePlace!.label}'
                                    : 'Titik GPS (${app.userPos!.latitude.toStringAsFixed(4)}, ${app.userPos!.longitude.toStringAsFixed(4)})',
                                style: t(13, w6),
                              ),
                              Text(
                                'Lokasimu sekarang, dari GPS',
                                style: t(11, FontWeight.w400, C.muted),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          if (_mode == 'search') ...[
            TextField(
              controller: _q,
              onChanged: (v) {
                setState(() {
                  _picked = null;
                  _err = false;
                });
                _search(v);
              },
              style: t(14),
              decoration: inputDeco('Cari kelurahan, kecamatan, atau kota')
                  .copyWith(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: C.muted,
                    ),
                  ),
            ),
            const SizedBox(height: 6),
            for (final a in suggest)
              Tap(
                onTap: () => setState(() {
                  _picked = a;
                  _q.text = a.$1;
                  _err = false;
                }),
                radius: 12,
                color: _picked == a ? C.blueTint : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 20,
                      color: _picked == a ? C.blue : C.faint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.$1, style: t(13))),
                    if (_picked == a)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: C.blue,
                      ),
                  ],
                ),
              ),
            if (suggest.isEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  q.length < 3
                      ? 'Ketik minimal 3 huruf. Untuk titik persis, pilih di Peta.'
                      : 'Belum ditemukan. Coba nama lain atau pilih di Peta.',
                  style: t(12, FontWeight.w400, C.muted),
                ),
              ),
          ],
          if (_mode == 'map') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 170,
                child: Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: _mapPin,
                        initialZoom: 14,
                        interactionOptions: const InteractionOptions(
                          flags:
                              InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                        ),
                        onPositionChanged: (cam, g) {
                          if (!g) return;
                          setState(() {
                            _mapPin = cam.center;
                            _pinLabel = null;
                          });
                          _labelPin();
                        },
                      ),
                      children: [
                        baseTiles(context),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: _mapPin,
                              radius: _radius.toDouble(),
                              useRadiusInMeter: true,
                              color: C.violet.withValues(alpha: .12),
                              borderColor: C.violet,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                        const MapCredit(compact: true),
                      ],
                    ),
                    const IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 36),
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 40,
                            color: C.violet,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: IgnorePointer(
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: C.ink.withValues(alpha: .82),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.pan_tool_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Geser peta ke lokasi',
                                style: t(11, FontWeight.w400, Colors.white),
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
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.pin_drop_rounded, size: 18, color: C.violet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pinLabel ?? 'Mencari nama lokasi…',
                    style: t(13, w6),
                  ),
                ),
              ],
            ),
          ],
          if (_err)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Pilih salah satu alamat dari daftar dulu.',
                style: t(12, FontWeight.w400, C.red),
              ),
            ),
          const SizedBox(height: 16),
          Text('Radius pantau', style: t(12, w6, C.sub)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (r, l) in _radii) ...[
                Expanded(
                  child: Choice(
                    l,
                    _radius == r,
                    () => setState(() => _radius = r),
                  ),
                ),
                if (r != 2000) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Btn(
            'Simpan lokasi',
            height: 50,
            radius: 16,
            fontSize: 14,
            gradient: gViolet,
            onTap: _confirm,
          ),
        ],
      ),
    );
  }
}

/// M10: notifikasi terbaru; ketuk membuka detail lokasi.
class NotifScreen extends StatelessWidget {
  const NotifScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      20,
      topInset(context) + 8,
      20,
      tabSpace(context),
    ),
    children: stagger([
      Header(
        'Notifikasi',
        onBack: app.back,
        trailing: app.loggedIn && app.notifs.isNotEmpty
            ? TextButton(
                onPressed: () async {
                  try {
                    await Api.clearNotifications();
                    app.set(() => app.notifs = []);
                  } on ApiError catch (x) {
                    app.showToast(x.message);
                  }
                },
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text('Hapus semua', style: t(13, w6, C.blueMid)),
              )
            : null,
      ),
      const SizedBox(height: 14),
      if (!app.loggedIn)
        EmptyCard(
          Icons.notifications_off_rounded,
          'Masuk untuk menerima notifikasi',
          'Simpan lokasi pantauan dan kami kabari saat status di sana berubah.',
          action: Btn.primary(
            'Masuk',
            height: 48,
            fontSize: 14,
            onTap: () => app.needLogin(Scr.notif, 'watch'),
          ),
        )
      else if (app.notifs.isEmpty)
        const EmptyCard(
          Icons.notifications_rounded,
          'Belum ada notifikasi',
          'Notifikasi muncul saat status lokasi pantauanmu berubah.',
        ),
      if (app.loggedIn)
        for (final n in app.notifs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Builder(
              builder: (_) {
                final p = app.points
                    .where((x) => x.id == n.pointId)
                    .firstOrNull;
                final d = depths[p?.depth ?? 0];
                return Tap(
                  onTap: () {
                    if (n.unread) Api.markRead(n.id).catchError((_) {});
                    n.unread = false;
                    p != null
                        ? app.openPoint(p.id)
                        : app.showToast('Lokasi ini sudah tidak ada di peta');
                  },
                  radius: 22,
                  color: n.unread
                      ? Colors.white
                      : Colors.white.withValues(alpha: .6),
                  shadow: soft(.08, 20, 8),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconTile(
                        p?.receded ?? false
                            ? Icons.check_circle_rounded
                            : Icons.water_drop_rounded,
                        d.tint,
                        d.ink,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title, style: t(14, w6, C.ink, 1.35)),
                            const SizedBox(height: 3),
                            Text(
                              n.body,
                              style: t(13, FontWeight.w400, C.body, 1.45),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ago(n.time),
                              style: t(11, FontWeight.w400, C.muted),
                            ),
                          ],
                        ),
                      ),
                      if (n.unread)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(top: 6, left: 8),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: C.blue,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
    ]),
  );
}
