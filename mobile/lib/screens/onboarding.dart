import 'package:flutter/material.dart';
import '../motion.dart';

import '../art.dart';
import '../state.dart';
import '../theme.dart';

const _bg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFDCE8FF), C.bg],
    stops: [0, .62],
  ),
);

/// M01: 3 slide (cek kondisi, lapor, pantau) dengan tombol Lewati.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const _copy = [
    (
      'Cek kondisi jalan sebelum berangkat',
      'Lihat tinggi genangan per lokasi, kapan diperbarui, dan siapa sumbernya. Tidak perlu tanya di grup WhatsApp.',
    ),
    (
      'Lapor genangan di sekitarmu',
      'Pilih gambar tinggi air, ambil foto, kirim. Kurang dari satu menit, dan warga lain bisa menghindar.',
    ),
    (
      'Pantau rumah, kampus, kantor',
      'Kami kabari kalau genangan selutut ke atas muncul di dekat lokasi yang kamu simpan. Hanya dari laporan terverifikasi atau resmi.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final i = app.onb;
    return Container(
      decoration: _bg,
      padding: EdgeInsets.fromLTRB(
        24,
        topInset(context) + 16,
        24,
        bottomInset(context) + 34,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: gBlueSoft,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: soft(.35, 16, 8, C.blue),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('SIGAP Banjir', style: t(16, w7))),
              Tap(
                onTap: () => app.go(Scr.permission),
                height: 48,
                radius: 14,
                color: Colors.white.withValues(alpha: .7),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text('Lewati', style: t(14, w5))),
              ),
            ],
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: dur(context, 420),
              reverseDuration: dur(context, 180),
              transitionBuilder: materialize(from: const Offset(28, 0)),
              // Muat → rata bawah seperti desain; tidak muat (HP kecil, huruf 130%) → bisa di-scroll.
              child: LayoutBuilder(
                key: ValueKey(i),
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: (c.maxHeight - 230).clamp(200, 330),
                          child: FittedBox(
                            child: SizedBox(
                              width: 342,
                              height: 330,
                              child: [
                                const _Slide0(),
                                const _Slide1(),
                                const _Slide2(),
                              ][i],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          _copy[i].$1,
                          style: t(
                            28,
                            w7,
                            C.ink,
                            1.2,
                          ).copyWith(letterSpacing: -.4),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _copy[i].$2,
                          style: t(15, FontWeight.w400, C.body, 1.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              for (var d = 0; d < 3; d++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 6),
                  width: d == i ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: d == i ? C.blue : const Color(0xFFC4D6F5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              Tap(
                onTap: () =>
                    i < 2 ? app.set(() => app.onb++) : app.go(Scr.permission),
                height: 56,
                radius: 20,
                gradient: gBlue,
                shadow: soft(.35, 24, 12, C.blue),
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      i == 2 ? 'Mulai' : 'Lanjut',
                      style: t(15, w6, Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Slide0 extends StatelessWidget {
  const _Slide0();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned(top: 10, left: 30, child: WxAnim('heavy', size: 190)),
      Positioned(
        bottom: 20,
        right: 6,
        child: Container(
          width: 236,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: soft(.16, 36, 18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Jl. Ketintang Baru', style: t(14, w6))),
                  Pill('Selutut', depths[2].tint, depths[2].ink),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: C.blueMid,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Terverifikasi · 12 menit lalu',
                      style: t(12, FontWeight.w400, C.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Slide1 extends StatelessWidget {
  const _Slide1();

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: soft(.16, 36, 18),
        ),
        child: const DepthFig(2, size: 150),
      ),
      Positioned(
        top: 40,
        right: 20,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: gViolet,
            borderRadius: BorderRadius.circular(16),
            boxShadow: soft(.35, 24, 12, C.violet),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.photo_camera_rounded,
                size: 20,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text('Foto + GPS', style: t(13, w6, Colors.white)),
            ],
          ),
        ),
      ),
      Positioned(
        bottom: 30,
        left: 14,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: soft(.14, 24, 12),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: depths[2].color,
                ),
              ),
              const SizedBox(width: 8),
              Text('Selutut · ± 40 cm', style: t(13, w6)),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Slide2 extends StatelessWidget {
  const _Slide2();

  Widget _row(
    double w,
    IconData icon,
    Color bg,
    Color fg,
    String title,
    String sub, {
    bool solid = true,
  }) => Container(
    width: w,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: solid ? Colors.white : Colors.white.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(22),
      boxShadow: solid ? soft(.16, 36, 18) : null,
    ),
    child: Row(
      children: [
        IconTile(icon, bg, fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t(13, w6)),
              Text(sub, style: t(12, FontWeight.w400, C.muted)),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _row(
        300,
        Icons.home_rounded,
        C.redTint,
        C.redInk,
        'Rumah · air sepinggang',
        '800 m dari rumah · Terverifikasi',
      ),
      const SizedBox(height: 12),
      _row(
        270,
        Icons.school_rounded,
        C.greenTint,
        C.green,
        'Kampus · sudah surut',
        'Surut pukul 14.10',
        solid: false,
      ),
    ],
  );
}

/// M01 Izin: lokasi lalu notifikasi, dengan penjelasan konteks (PRD §9 Privasi).
class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notif = app.permNotif;
    Future<void> next(bool allow) async {
      if (!notif) {
        if (allow) await app.locate();
        app.set(() => app.permNotif = true);
      } else {
        // ponytail: izin notifikasi push diminta lewat firebase_messaging saat FCM dipasang bersama backend.
        await app.finishOnboarding();
        if (!allow) app.notifEnabled = false;
      }
      if (!allow && !notif) app.set(() => app.locDenied = true);
    }

    return Container(
      decoration: _bg,
      padding: EdgeInsets.fromLTRB(
        24,
        topInset(context) + 16,
        24,
        bottomInset(context) + 34,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .65),
                ),
                child: Center(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      gradient: gBlueSoft,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: soft(.4, 40, 20, C.blue),
                    ),
                    child: AnimatedSwitcher(
                      duration: dur(context, 320),
                      transitionBuilder: (child, a) => ScaleTransition(
                        scale: Tween(begin: .7, end: 1.0).animate(
                          CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                        ),
                        child: FadeTransition(opacity: a, child: child),
                      ),
                      child: Icon(
                        notif
                            ? Icons.notifications_rounded
                            : Icons.location_on_rounded,
                        key: ValueKey(notif),
                        size: 52,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            notif ? 'Nyalakan notifikasi?' : 'Izinkan akses lokasi?',
            style: t(26, w7, C.ink, 1.25),
          ),
          const SizedBox(height: 10),
          Text(
            notif
                ? 'Kami hanya mengirim kabar dari laporan terverifikasi atau resmi, supaya tidak ada alarm palsu.'
                : 'Lokasi dipakai di HP-mu saja untuk memusatkan peta ke sekitarmu. Kami tidak menyimpan lokasi realtime kamu.',
            style: t(15, FontWeight.w400, C.body, 1.6),
          ),
          const SizedBox(height: 28),
          Btn.primary('Izinkan', onTap: () => next(true)),
          const SizedBox(height: 10),
          Btn('Nanti saja', height: 52, fg: C.body, onTap: () => next(false)),
        ],
      ),
    );
  }
}
