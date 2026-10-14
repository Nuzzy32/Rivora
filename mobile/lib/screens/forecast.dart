import 'package:flutter/services.dart';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../art.dart';
import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

/// Latar mengikuti suasana slot terpilih (dekoratif; berpindah pelan).
List<Color> _mood(String kind) => switch (kind) {
  'heavy' ||
  'storm' => const [Color(0xFF8FAEF5), Color(0xFF4F7FEA), Color(0xFF6A5FE3)],
  'rain' || 'nightrain' => const [
    Color(0xFF96B8FA),
    Color(0xFF5289F3),
    Color(0xFF6873EE),
  ],
  'nightcloud' => const [
    Color(0xFF8EA4F2),
    Color(0xFF5472E2),
    Color(0xFF4F55C2),
  ],
  'sun' ||
  'partly' => const [Color(0xFFA9D0FF), Color(0xFF5DA0FD), Color(0xFF7C9BF7)],
  _ => const [Color(0xFF9FC3FF), C.blue, Color(0xFF6C86F6)],
};

/// M08: prakiraan BMKG per 3 jam untuk kecamatan terpilih.
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  final _chips = ScrollController();
  int _dir = 1; // arah geser isi kartu: 1 = slot ke kanan, -1 = ke kiri

  @override
  void dispose() {
    _chips.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == app.fcSlot) return;
    _dir = i > app.fcSlot ? 1 : -1;
    HapticFeedback.selectionClick();
    app.set(() => app.fcSlot = i);
    // Bawa chip terpilih ke tengah layar.
    if (_chips.hasClients) {
      final target =
          i * 76.0 - (MediaQuery.sizeOf(context).width - 66) / 2 + 20;
      _chips.animateTo(
        target.clamp(0, _chips.position.maxScrollExtent),
        duration: dur(context, 380),
        curve: easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = app.forecast;
    final loading = app.fcLoading || f == null || f.slots.isEmpty;
    final cur = loading
        ? null
        : f.slots[app.fcSlot.clamp(0, f.slots.length - 1)];
    final now = DateTime.now();
    final src = f == null
        ? 'Sumber: BMKG'
        : 'Sumber: BMKG · ${app.fcStale ? 'data tersimpan' : 'diambil'} ${hm(f.fetchedAt)} WIB';
    final key = '${app.district}-${app.fcSlot}';
    return AnimatedContainer(
      duration: dur(context, 700),
      curve: easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-.3, -1),
          end: const Alignment(.3, 1),
          colors: _mood(cur?.kind ?? 'cloud'),
          stops: const [0, .52, 1],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.only(top: topInset(context) + 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prakiraan', style: t(24, w7, Colors.white)),
                      Text(
                        '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} · per 3 jam',
                        style: t(13, w5, Colors.white),
                      ),
                    ],
                  ),
                ),
                Tap(
                  onTap: () => _pickDistrict(context),
                  height: 48,
                  radius: 15,
                  color: Colors.white.withValues(alpha: .22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .55),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                  label: 'Pilih kecamatan',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      AnimatedSwitcher(
                        duration: dur(context, 260),
                        transitionBuilder: materialize(
                          from: const Offset(0, 6),
                        ),
                        child: Text(
                          'Kec. ${app.district}',
                          key: ValueKey(app.district),
                          style: t(13, w6, Colors.white),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 130,
            child: ListView(
              key: ValueKey(
                app.district,
              ), // ganti kecamatan → chip masuk ulang bertahap
              controller: _chips,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              children: [
                for (final (i, s)
                    in (loading ? const <Slot>[] : f.slots).indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Appear(
                      index: i,
                      dy: 14,
                      child: _SlotChip(
                        s,
                        selected: i == app.fcSlot,
                        onTap: () => _select(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: .42),
                    Colors.white.withValues(alpha: .12),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .55)),
                boxShadow: soft(.25, 40, 24, const Color(0xFF325AC8)),
              ),
              child: AnimatedSwitcher(
                duration: dur(context, 360),
                transitionBuilder: materialize(),
                child: cur == null ? _loadingCard() : _card(f!, cur, key),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            constraints: const BoxConstraints(minHeight: 360),
            padding: EdgeInsets.fromLTRB(20, 22, 20, tabSpace(context)),
            decoration: const BoxDecoration(
              color: C.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (app.fcStale) ...[
                  Appear(
                    child: Note(
                      'Gagal memuat data terbaru. Menampilkan prakiraan tersimpan pukul ${hm(f!.fetchedAt)} WIB.',
                      icon: Icons.cloud_off_rounded,
                      bg: C.ink,
                      fg: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (f?.warning != null && !app.fcStale) ...[
                  Appear(
                    child: Box(
                      radius: 22,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const IconTile(
                            Icons.thunderstorm_rounded,
                            C.violet,
                            Colors.white,
                            gradient: gViolet,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Peringatan dini BMKG', style: t(14, w6)),
                                const SizedBox(height: 3),
                                Text(
                                  f!.warning!,
                                  style: t(13, FontWeight.w400, C.body, 1.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Appear(
                  index: 1,
                  child: Box(
                    radius: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.shield_rounded,
                              size: 20,
                              color: C.violetMid,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(src, style: t(13, w6))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Prakiraan ini bukan prediksi banjir. Untuk kondisi jalan saat ini, lihat laporan di Peta.',
                          style: t(13, FontWeight.w400, C.body, 1.55),
                        ),
                        const SizedBox(height: 12),
                        Btn(
                          'Cek genangan di Peta',
                          icon: Icons.map_outlined,
                          height: 48,
                          radius: 16,
                          fontSize: 14,
                          color: C.blueTint,
                          fg: C.blueMid,
                          onTap: () => app.go(Scr.map),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingCard() => SizedBox(
    key: const ValueKey('loading'),
    height: 262,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Shimmer(
          base: Colors.white.withValues(alpha: .35),
          glow: Colors.white.withValues(alpha: .75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_skel(.6), const SizedBox(height: 14), _skel(.4)],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          app.fcLoading
              ? 'Memuat prakiraan Kec. ${app.district}…'
              : 'Prakiraan Kec. ${app.district} belum tersedia. Coba lagi sebentar lagi.',
          style: t(13, w5, Colors.white),
        ),
      ],
    ),
  );

  /// Isi kartu: ilustrasi berganti dengan scale+blur, angka bergulir, teks bergeser searah pilihan.
  Widget _card(Forecast f, Slot cur, String key) => Column(
    key: const ValueKey('card'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(-14, -18),
            child: SizedBox(
              width: 150,
              height: 150,
              child: AnimatedSwitcher(
                duration: dur(context, 420),
                reverseDuration: dur(context, 200),
                transitionBuilder: (child, a) => AnimatedBuilder(
                  animation: a,
                  child: child,
                  builder: (context, child) {
                    final v = easeOut.transform(a.value);
                    return Opacity(
                      opacity: v,
                      child: Transform.scale(
                        scale: .85 + .15 * v,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 6 * (1 - v),
                            sigmaY: 6 * (1 - v),
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
                child: LiveWx(
                  cur.kind,
                  key: ValueKey('${cur.kind}-$key'),
                  size: 150,
                ),
              ),
            ),
          ),
          // Angka besar mengecil sendiri kalau layar sempit / huruf sistem diperbesar.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CountTo(
                    cur.temp,
                    suffix: '°',
                    style: t(
                      68,
                      w6,
                      Colors.white,
                      1,
                    ).copyWith(letterSpacing: -2),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Terasa ', style: t(13, w5, Colors.white)),
                      CountTo(
                        cur.feels,
                        suffix: '°',
                        style: t(13, w5, Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      Transform.translate(
        offset: const Offset(0, -14),
        child: AnimatedSwitcher(
          duration: dur(context, 340),
          reverseDuration: dur(context, 160),
          transitionBuilder: materialize(from: Offset(_dir * 24, 0)),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey(key),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cur.desc, style: t(26, w7, Colors.white)),
              Text('Pukul ${hm(cur.time)} WIB', style: t(14, w5, Colors.white)),
              if (f.rainLine != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: C.violetInk,
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: Text(f.rainLine!, style: t(12, w6))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          _stat(
            Icons.umbrella_rounded,
            AnimatedSwitcher(
              duration: dur(context, 260),
              transitionBuilder: materialize(from: const Offset(0, 6)),
              child: Text(
                '${cur.rainMm.toStringAsFixed(1).replaceAll('.', ',')} mm',
                key: ValueKey(cur.rainMm),
                style: t(15, w6, Colors.white),
              ),
            ),
            'Curah hujan',
          ),
          const SizedBox(width: 10),
          _stat(
            Icons.air_rounded,
            CountTo(cur.wind, suffix: ' km/j', style: t(15, w6, Colors.white)),
            'Angin',
          ),
          const SizedBox(width: 10),
          _stat(
            Icons.water_drop_outlined,
            CountTo(cur.hum, suffix: '%', style: t(15, w6, Colors.white)),
            'Kelembapan',
          ),
        ],
      ),
    ],
  );

  Widget _skel(double w) => FractionallySizedBox(
    widthFactor: w,
    child: Container(
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );

  Widget _stat(IconData icon, Widget value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: Colors.white),
          const SizedBox(height: 4),
          value,
          Text(
            label,
            textAlign: TextAlign.center,
            style: t(11, w5, Colors.white),
          ),
        ],
      ),
    ),
  );

  void _pickDistrict(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3EE),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
              child: Text('Pilih kecamatan', style: t(17, w7)),
            ),
            for (final (i, d) in Api.districts.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Appear(
                  index: i,
                  child: Tap(
                    onTap: () {
                      Navigator.pop(ctx);
                      app.loadForecast(d);
                    },
                    height: 52,
                    radius: 16,
                    color: d == app.district ? C.blueTint : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text('Kec. $d', style: t(14, w5))),
                        if (d == app.district)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 22,
                            color: C.blue,
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
  );
}

/// Chip slot 3 jam. Yang terpilih "terangkat": putih, bayangan, sedikit lebih besar.
class _SlotChip extends StatelessWidget {
  final Slot s;
  final bool selected;
  final VoidCallback onTap;
  const _SlotChip(this.s, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? C.violetMid : Colors.white;
    return Semantics(
      selected: selected,
      label: 'Pukul ${hm(s.time)}, ${s.desc}, ${s.temp} derajat',
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: dur(context, 260),
        curve: easeOut,
        child: Tap(
          onTap: onTap,
          width: 66,
          height: 120,
          radius: 33,
          pressScale: .94,
          color: selected ? Colors.white : Colors.white.withValues(alpha: .18),
          border: Border.all(color: Colors.white.withValues(alpha: .4)),
          shadow: selected
              ? soft(.25, 24, 14, const Color(0xFF325AC8))
              : soft(0, 24, 14, const Color(0xFF325AC8)),
          child: ExcludeSemantics(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: fg),
              duration: dur(context, 200),
              builder: (context, c, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(hm(s.time), style: t(12, w6, c!)),
                  Wx(s.kind, size: 44),
                  Text('${s.temp}°', style: t(18, w6, c)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
