import 'package:flutter/material.dart';

import '../art.dart';
import '../data.dart';
import '../state.dart';
import '../theme.dart';

/// M08: prakiraan BMKG per 3 jam untuk kecamatan terpilih.
class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final f = app.forecast;
    final cur = f?.slots[app.fcSlot];
    final now = DateTime.now();
    final src = f == null
        ? 'Sumber: BMKG'
        : 'Sumber: BMKG · ${app.fcStale ? 'data tersimpan' : 'diambil'} ${hm(f.fetchedAt)} WIB';
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-.3, -1),
          end: Alignment(.3, 1),
          colors: [Color(0xFF9FC3FF), C.blue, Color(0xFF6C86F6)],
          stops: [0, .52, 1],
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
                      Text(
                        'Kec. ${app.district}',
                        style: t(13, w6, Colors.white),
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
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              children: [
                for (final (i, s) in (f?.slots ?? const <Slot>[]).indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      selected: i == app.fcSlot,
                      label:
                          'Pukul ${hm(s.time)}, ${s.desc}, ${s.temp} derajat',
                      child: Tap(
                        onTap: () => app.set(() => app.fcSlot = i),
                        width: 66,
                        height: 120,
                        radius: 33,
                        color: i == app.fcSlot
                            ? Colors.white
                            : Colors.white.withValues(alpha: .18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .4),
                        ),
                        shadow: i == app.fcSlot
                            ? soft(.25, 24, 14, const Color(0xFF325AC8))
                            : null,
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                hm(s.time),
                                style: t(
                                  12,
                                  w6,
                                  i == app.fcSlot ? C.violetMid : Colors.white,
                                ),
                              ),
                              Wx(s.kind, size: 44),
                              Text(
                                '${s.temp}°',
                                style: t(
                                  18,
                                  w6,
                                  i == app.fcSlot ? C.violetMid : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
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
              child: app.fcLoading || cur == null
                  ? SizedBox(
                      height: 262,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _skel(.6, .4),
                          const SizedBox(height: 14),
                          _skel(.4, .3),
                          const SizedBox(height: 14),
                          Text(
                            'Memuat prakiraan Kec. ${app.district}…',
                            style: t(13, w5, Colors.white),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Transform.translate(
                              offset: const Offset(-14, -18),
                              child: Wx(cur.kind, size: 150),
                            ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${cur.temp}°',
                                  style: t(
                                    68,
                                    w6,
                                    Colors.white,
                                    1,
                                  ).copyWith(letterSpacing: -2),
                                ),
                                Text(
                                  'Terasa ${cur.feels}°',
                                  style: t(13, w5, Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Transform.translate(
                          offset: const Offset(0, -14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cur.desc, style: t(26, w7, Colors.white)),
                              Text(
                                'Pukul ${hm(cur.time)} WIB',
                                style: t(14, w5, Colors.white),
                              ),
                              if (f!.rainLine != null)
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
                                      Flexible(
                                        child: Text(
                                          f.rainLine!,
                                          style: t(12, w6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _stat(
                              Icons.umbrella_rounded,
                              '${cur.rainMm.toStringAsFixed(1).replaceAll('.', ',')} mm',
                              'Curah hujan',
                            ),
                            const SizedBox(width: 10),
                            _stat(
                              Icons.air_rounded,
                              '${cur.wind} km/j',
                              'Angin',
                            ),
                            const SizedBox(width: 10),
                            _stat(
                              Icons.water_drop_outlined,
                              '${cur.hum}%',
                              'Kelembapan',
                            ),
                          ],
                        ),
                      ],
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
                  Note(
                    'Gagal memuat data terbaru. Menampilkan prakiraan tersimpan pukul ${hm(f!.fetchedAt)} WIB.',
                    icon: Icons.cloud_off_rounded,
                    bg: C.ink,
                    fg: Colors.white,
                  ),
                  const SizedBox(height: 12),
                ],
                if (f?.warning != null && !app.fcStale) ...[
                  Box(
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
                  const SizedBox(height: 12),
                ],
                Box(
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skel(double w, double a) => FractionallySizedBox(
    widthFactor: w,
    child: Container(
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: a),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );

  Widget _stat(IconData icon, String value, String label) => Expanded(
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
          Text(value, style: t(15, w6, Colors.white)),
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
            for (final d in Api.districts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
          ],
        ),
      ),
    ),
  );
}
