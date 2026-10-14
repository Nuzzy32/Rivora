import 'package:flutter/material.dart';

import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

/// M04: cari jalan, kelurahan, posko.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final rows =
        <
              ({
                String name,
                String sub,
                String badge,
                Color tint,
                Color ink,
                IconData icon,
                Color iconBg,
                Color iconFg,
                VoidCallback onTap,
              })
            >[
              for (final p in app.points)
                (
                  name: p.name,
                  sub:
                      'Kec. ${p.district} · ${p.receded ? 'Surut ${hm(p.recededAt!)}' : ago(p.updatedAt)}',
                  badge: p.receded ? 'Sudah Surut' : depths[p.depth].label,
                  tint: depths[p.depth].tint,
                  ink: depths[p.depth].ink,
                  icon: Icons.water_drop_rounded,
                  iconBg: depths[p.depth].tint,
                  iconFg: depths[p.depth].color,
                  onTap: () => app.openPoint(p.id),
                ),
              if (q.isNotEmpty)
                for (final s in app.shelters)
                  (
                    name: s.name,
                    sub:
                        '${s.type == 'posko' ? 'Posko' : 'Faskes'} · ${km(meters(app.center, s.pos))}',
                    badge: s.status == 'full' ? 'Penuh' : 'Buka',
                    tint: s.status == 'full' ? C.redTint : C.greenTint,
                    ink: s.status == 'full' ? C.redInk : C.green,
                    icon: s.type == 'posko'
                        ? Icons.night_shelter_rounded
                        : Icons.local_hospital_rounded,
                    iconBg: s.type == 'posko' ? C.violetTint : C.blueTint2,
                    iconFg: s.type == 'posko' ? C.violetMid : C.blueInk,
                    onTap: () => app.openShelter(s),
                  ),
            ]
            .where(
              (r) =>
                  q.isEmpty || '${r.name} ${r.sub}'.toLowerCase().contains(q),
            )
            .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        topInset(context) + 8,
        16,
        tabSpace(context),
      ),
      children: stagger([
        Row(
          children: [
            SquareBtn(
              Icons.arrow_back_rounded,
              size: 52,
              label: 'Kembali',
              onTap: () => app.go(Scr.map),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: soft(.12, 20, 8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 22, color: C.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _q,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        style: t(14),
                        decoration: InputDecoration.collapsed(
                          hintText: 'Nama jalan, kelurahan, posko…',
                          hintStyle: t(14, FontWeight.w400, C.faint),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (app.loggedIn && q.isEmpty && app.watch.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in app.watch)
                Tap(
                  onTap: () {
                    app.mapCenter = w.pos;
                    final p = app.worstNear(w);
                    p != null ? app.openPoint(p.id) : app.go(Scr.map);
                  },
                  height: 44,
                  radius: 14,
                  color: Colors.white,
                  shadow: soft(.10, 14, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(watchIcon(w.label), size: 18, color: C.violet),
                      const SizedBox(width: 6),
                      Text(w.label, style: t(13, w5)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (q.isEmpty || rows.isNotEmpty)
          Text(
            q.isEmpty ? 'Laporan terbaru di Surabaya' : '${rows.length} hasil',
            style: t(13, w6, C.muted),
          ),
        if (q.isNotEmpty && rows.isEmpty)
          EmptyCard(
            Icons.travel_explore_rounded,
            'Tidak ditemukan',
            'Belum ada laporan untuk "${_q.text.trim()}". Coba nama jalan lain, misalnya Darmo atau Ketintang.',
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Tap(
              onTap: r.onTap,
              radius: 20,
              color: Colors.white,
              shadow: soft(.08, 16, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  IconTile(r.icon, r.iconBg, r.iconFg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: t(14, w6, C.ink, 1.35)),
                        Text(r.sub, style: t(12, FontWeight.w400, C.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(r.badge, r.tint, r.ink),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

IconData watchIcon(String label) => switch (label) {
  'Rumah' => Icons.home_rounded,
  'Kampus' => Icons.school_rounded,
  'Kantor' => Icons.work_rounded,
  _ => Icons.location_on_rounded,
};
