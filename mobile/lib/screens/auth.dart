import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

final _email = RegExp(r'^\S+@\S+\.\S+$');

const _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFDCE8FF), C.bg],
    stops: [0, .45],
  ),
);

/// M12: masuk / daftar. Tamu boleh lanjut tanpa akun.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController(),
      _mail = TextEditingController(text: app.forgotEmail),
      _pw = TextEditingController();
  bool _register = false, _show = false, _busy = false, _locked = false;
  Map<String, String> _err = {};
  String? _formErr;

  @override
  void dispose() {
    _name.dispose();
    _mail.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_locked || _busy) return;
    final e = <String, String>{};
    if (_register && _name.text.trim().length < 2) e['name'] = 'Isi nama kamu';
    if (!_email.hasMatch(_mail.text.trim())) {
      e['email'] = 'Format email belum benar';
    }
    if (_pw.text.length < 8) e['pw'] = 'Kata sandi minimal 8 karakter';
    setState(() {
      _err = e;
      _formErr = null;
    });
    if (e.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final u = _register
          ? await Api.register(_name.text.trim(), _mail.text.trim(), _pw.text)
          : await Api.login(_mail.text.trim(), _pw.text);
      if (u == null) {
        // Konfirmasi email wajib. Supabase menjawab sama untuk email yang sudah terdaftar
        // (tanpa mengirim apa pun) agar daftar akun tidak bisa ditebak, jadi pesannya mencakup keduanya.
        return setState(() {
          _register = false;
          _formErr =
              'Cek email ${_mail.text.trim()} dan buka link konfirmasinya, lalu masuk. '
              'Tidak ada email masuk? Mungkin email ini sudah terdaftar: masuk dengan kata sandi lama atau pakai "Lupa kata sandi?".';
        });
      }
      await app.signedIn(u, isNew: _register);
    } on ApiError catch (x) {
      if (mounted) {
        setState(
          () => x.code == 'LOCKED' ? _locked = true : _formErr = x.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = app.authReason;
    final guestTo =
        const [Scr.report, Scr.watch, Scr.notif].contains(app.authReturn)
        ? Scr.map
        : app.authReturn;
    Widget tab(String label, bool on, VoidCallback f) => Expanded(
      child: Semantics(
        selected: on,
        child: Tap(
          onTap: f,
          height: 44,
          radius: 12,
          color: on ? C.blueTint : Colors.transparent,
          child: Center(
            child: Text(label, style: t(14, w6, on ? C.blueInk : C.muted)),
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: _bg,
      child: AutofillGroup(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            topInset(context) + 8,
            20,
            tabSpace(context) + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: stagger([
            Align(
              alignment: Alignment.centerLeft,
              child: SquareBtn(
                Icons.arrow_back_rounded,
                label: 'Kembali',
                onTap: app.back,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              reason == 'report'
                  ? 'Masuk untuk melapor'
                  : reason == 'watch'
                  ? 'Masuk untuk memantau'
                  : _register
                  ? 'Buat akun'
                  : 'Masuk',
              style: t(26, w7, C.ink, 1.25),
            ),
            const SizedBox(height: 6),
            Text(
              reason == 'report'
                  ? 'Login membantu kami melacak laporan dan membatasi spam. Setelah masuk, kamu langsung kembali ke form laporan.'
                  : 'Simpan lokasi pantauan, kirim laporan, dan terima notifikasi.',
              style: t(14, FontWeight.w400, C.body, 1.55),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: soft(.08, 16, 6),
              ),
              child: Row(
                children: [
                  tab(
                    'Masuk',
                    !_register,
                    () => setState(() {
                      _register = false;
                      _err = {};
                      _formErr = null;
                    }),
                  ),
                  tab(
                    'Daftar',
                    _register,
                    () => setState(() {
                      _register = true;
                      _err = {};
                      _formErr = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_locked) ...[
              const Note(
                'Akun dikunci sementara karena 5 kali gagal masuk. Coba lagi dalam 15 menit.',
                icon: Icons.lock_clock_rounded,
                bg: C.redTint,
                fg: C.redInk,
              ),
              const SizedBox(height: 14),
            ],
            if (_formErr != null) ...[
              Note(_formErr!),
              const SizedBox(height: 14),
            ],
            if (_register) ...[
              Field(
                'Nama',
                _name,
                hint: 'Nama lengkap',
                error: _err['name'],
                autofill: const [AutofillHints.name],
              ),
              const SizedBox(height: 14),
            ],
            Field(
              'Email',
              _mail,
              hint: 'nama@email.com',
              error: _err['email'],
              type: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
            ),
            const SizedBox(height: 14),
            Field(
              'Kata sandi',
              _pw,
              hint: 'Minimal 8 karakter',
              error: _err['pw'],
              obscure: !_show,
              autofill: [
                _register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              suffix: IconButton(
                tooltip: _show
                    ? 'Sembunyikan kata sandi'
                    : 'Tampilkan kata sandi',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(
                  _show
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: C.muted,
                ),
              ),
            ),
            if (!_register)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    app.forgotEmail = _mail.text.trim();
                    app.go(Scr.forgot);
                  },
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text('Lupa kata sandi?', style: t(13, w6, C.blueInk)),
                ),
              )
            else
              const SizedBox(height: 20),
            _locked || _busy
                ? Btn(
                    _busy ? 'Memproses…' : (_register ? 'Daftar' : 'Masuk'),
                    color: const Color(0xFFC3C8D4),
                  )
                : Btn.primary(_register ? 'Daftar' : 'Masuk', onTap: _submit),
            if (_register)
              Center(
                child: TextButton(
                  onPressed: app.openPrivacy,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                  child: Text.rich(
                    TextSpan(
                      text: 'Dengan mendaftar, kamu menyetujui ',
                      style: t(12, FontWeight.w400, C.muted),
                      children: [
                        TextSpan(
                          text: 'Kebijakan Privasi',
                          style: t(12, w6, C.blueInk),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Btn(
              'Lanjut sebagai Tamu',
              height: 48,
              fg: C.body,
              fontSize: 14,
              onTap: () => app.go(guestTo),
            ),
          ]),
        ),
      ),
    );
  }
}

/// M13: lupa kata sandi. Pesan selalu sama supaya tidak membocorkan email terdaftar.
class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key});

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  final _mail = TextEditingController(text: app.forgotEmail),
      _pw = TextEditingController(),
      _pw2 = TextEditingController();
  // Dibuka dari link email (deep link) → langsung ke form kata sandi baru.
  int _step = app.recovery ? 2 : 0;
  Map<String, String> _err = {};
  bool _busy = false;

  @override
  void dispose() {
    _mail.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.hasMatch(_mail.text.trim())) {
      return setState(() => _err = {'email': 'Format email belum benar'});
    }
    try {
      await Api.forgotPassword(_mail.text.trim());
    } on ApiError catch (x) {
      return app.showToast(x.message);
    }
    setState(() {
      _step = 1;
      _err = {};
    });
  }

  Future<void> _save() async {
    final e = <String, String>{};
    if (_pw.text.length < 8) e['pw'] = 'Kata sandi minimal 8 karakter';
    if (_pw2.text != _pw.text) e['pw2'] = 'Kata sandi belum sama';
    setState(() => _err = e);
    if (e.isNotEmpty) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Api.resetPassword(_pw.text);
      await Api.logout(); // masuk ulang dengan kata sandi baru
      app.recovery = false;
      setState(() => _step = 3);
    } on ApiError catch (x) {
      app.showToast(
        x.code == 'otp_expired'
            ? 'Link sudah kedaluwarsa. Minta link baru.'
            : x.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hero(IconData icon, Gradient g, Color glow) => Center(
    child: Container(
      width: 110,
      height: 110,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        gradient: g,
        borderRadius: BorderRadius.circular(36),
        boxShadow: soft(.4, 40, 20, glow),
      ),
      child: Icon(icon, size: 52, color: Colors.white),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mail = _step == 2 && app.recovery
        ? (Supabase.instance.client.auth.currentUser?.email ?? '')
        : _mail.text.trim();
    final body = switch (_step) {
      0 => [
        Text('Lupa kata sandi?', style: t(26, w7, C.ink, 1.25)),
        const SizedBox(height: 6),
        Text(
          'Masukkan email akunmu. Kami kirim link untuk membuat kata sandi baru.',
          style: t(14, FontWeight.w400, C.body, 1.55),
        ),
        const SizedBox(height: 20),
        Field(
          'Email',
          _mail,
          hint: 'nama@email.com',
          error: _err['email'],
          type: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
        ),
        const SizedBox(height: 20),
        Btn.primary('Kirim link', onTap: _send),
      ],
      1 => [
        _hero(Icons.mark_email_read_rounded, gBlueSoft, C.blue),
        const SizedBox(height: 10),
        Text('Cek email kamu', textAlign: TextAlign.center, style: t(24, w7)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Jika email terdaftar, link atur ulang sudah dikirim ke ',
              ),
              TextSpan(text: mail, style: t(14, w6)),
              const TextSpan(text: '. Berlaku 60 menit. Cek juga folder spam.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: t(14, FontWeight.w400, C.body, 1.55),
        ),
        const SizedBox(height: 20),
        Note(
          'Buka link itu dari HP ini. Aplikasi akan terbuka langsung di form kata sandi baru.',
          icon: Icons.info_outline_rounded,
          bg: C.blueTint2,
          fg: C.blueInk,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Btn(
                'Kirim ulang',
                height: 48,
                fontSize: 14,
                color: Colors.white,
                fg: C.ink,
                radius: 16,
                shadow: soft(.08, 16, 6),
                onTap: () async {
                  try {
                    await Api.forgotPassword(mail);
                    app.showToast('Link baru dikirim ke $mail');
                  } on ApiError catch (x) {
                    app.showToast(x.message);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Btn(
                'Ganti email',
                height: 48,
                fontSize: 14,
                fg: C.blueInk,
                onTap: () => setState(() => _step = 0),
              ),
            ),
          ],
        ),
      ],
      2 => [
        Text('Buat kata sandi baru', style: t(26, w7, C.ink, 1.25)),
        const SizedBox(height: 6),
        Text(
          'Untuk $mail. Gunakan minimal 8 karakter.',
          style: t(14, FontWeight.w400, C.body, 1.55),
        ),
        const SizedBox(height: 20),
        Field(
          'Kata sandi baru',
          _pw,
          hint: 'Minimal 8 karakter',
          error: _err['pw'],
          obscure: true,
          autofill: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 14),
        Field(
          'Ulangi kata sandi',
          _pw2,
          hint: 'Ketik ulang',
          error: _err['pw2'],
          obscure: true,
        ),
        const SizedBox(height: 20),
        Btn.primary(_busy ? 'Menyimpan…' : 'Simpan kata sandi', onTap: _save),
      ],
      _ => [
        _hero(Icons.lock_reset_rounded, gViolet, C.violet),
        const SizedBox(height: 10),
        Text(
          'Kata sandi diperbarui',
          textAlign: TextAlign.center,
          style: t(24, w7),
        ),
        const SizedBox(height: 6),
        Text(
          'Masuk dengan kata sandi barumu. Perangkat lain yang masih login otomatis keluar.',
          textAlign: TextAlign.center,
          style: t(14, FontWeight.w400, C.body, 1.55),
        ),
        const SizedBox(height: 20),
        Btn.primary(
          'Masuk sekarang',
          onTap: () {
            app.forgotEmail = mail;
            app.go(Scr.login);
          },
        ),
      ],
    };
    return DecoratedBox(
      decoration: _bg,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset(context) + 8,
          20,
          tabSpace(context) + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: stagger([
          Align(
            alignment: Alignment.centerLeft,
            child: SquareBtn(
              Icons.arrow_back_rounded,
              label: 'Kembali',
              onTap: () => _step == 1 || _step == 2
                  ? setState(() => _step--)
                  : app.go(Scr.login),
            ),
          ),
          const SizedBox(height: 20),
          ...body,
        ]),
      ),
    );
  }
}
