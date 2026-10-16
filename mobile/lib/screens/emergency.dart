import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

/// M11: 112, kontak darurat, posko terdekat, kartu Panduan Siaga.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  static const _icons = {
    'bpbd': Icons.emergency_rounded,
    'damkar': Icons.fire_truck_rounded,
    'ambulans': Icons.local_hospital_rounded,
    'polisi': Icons.local_police_rounded,
    'bnpb': Icons.shield_rounded,
    'sar': Icons.sailing_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // Kontak nasional + kontak kab/kota tempat pengguna berada (GPS, atau lokasi prakiraan).
    final adm4 = app.contactAdm4;
    final contacts = app.contacts.where((c) => c.appliesTo(adm4)).toList()
      // Kab/kota dulu, lalu provinsi, lalu nasional.
      ..sort((a, b) => (b.region?.length ?? 0) - (a.region?.length ?? 0));
    final local = contacts.any((c) => c.region != null);
    final posko = app.shelters.where((s) => s.type == 'posko').toList()
      ..sort(
        (a, b) =>
            meters(app.center, a.pos).compareTo(meters(app.center, b.pos)),
      );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDE8E9), C.bg],
          stops: [0, .4],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset(context) + 12,
          20,
          tabSpace(context),
        ),
        children: stagger([
          Text('Darurat', style: t(24, w7)),
          Text(
            'Tetap tenang. Pilih bantuan yang kamu butuhkan.',
            style: t(14, FontWeight.w400, C.body),
          ),
          const SizedBox(height: 16),
          Tap(
            onTap: () {
              HapticFeedback.mediumImpact();
              app.call('112');
            },
            radius: 30,
            gradient: gRed,
            shadow: soft(.35, 36, 20, const Color(0xFFD93439)),
            label: 'Panggil 112',
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .5),
                      width: 2,
                    ),
                  ),
                  child: const AppIcon('call_112', size: 64),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Panggil 112', style: t(30, w7, Colors.white, 1.1)),
                      const SizedBox(height: 2),
                      Text(
                        'Nomor darurat nasional · gratis, 24 jam',
                        style: t(13, FontWeight.w400, Colors.white, 1.45),
                      ),
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
                for (final c in contacts)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        if (_icons.containsKey(c.category))
                          AppIcon('call_${c.category}', size: 42)
                        else
                          const AppIcon('call_112', size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: t(14, w6)),
                              Text(
                                c.phone,
                                style: t(12, FontWeight.w400, C.muted),
                              ),
                            ],
                          ),
                        ),
                        SquareBtn(
                          Icons.call_rounded,
                          bg: C.greenTint,
                          fg: C.green,
                          shadowed: false,
                          label: 'Telepon ${c.name}',
                          onTap: () => app.call(c.phone),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (!local) ...[
            const SizedBox(height: 10),
            Note(
              adm4 == null
                  ? 'Aktifkan lokasi agar nomor BPBD dan layanan di daerahmu ikut tampil.'
                  : 'Nomor BPBD untuk daerahmu belum tersedia. Gunakan 112 atau BNPB 117.',
              icon: Icons.info_outline_rounded,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Posko terdekat', style: t(16, w6))),
              TextButton(
                onPressed: () {
                  app.layers.add('posko');
                  app.go(Scr.map);
                },
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Row(
                  children: [
                    Text('Lihat di peta', style: t(13, w6, C.blueMid)),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: C.blueMid,
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final p in posko)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Box(
                radius: 22,
                child: Row(
                  children: [
                    const IconTile(
                      Icons.night_shelter_rounded,
                      C.violetTint,
                      C.violetMid,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: t(14, w6, C.ink, 1.35)),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Pill(
                                p.status == 'full' ? 'Penuh' : 'Buka',
                                p.status == 'full' ? C.redTint : C.greenTint,
                                p.status == 'full' ? C.redInk : C.green,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                km(meters(app.center, p.pos)),
                                style: t(12, FontWeight.w400, C.muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Tap(
                      onTap: () => app.directions(p.pos),
                      height: 44,
                      radius: 14,
                      color: C.blueTint,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_rounded,
                            size: 18,
                            color: C.blueMid,
                          ),
                          const SizedBox(width: 4),
                          Text('Arahkan', style: t(13, w6, C.blueMid)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Tap(
            onTap: () => app.openGuide(0),
            radius: 26,
            gradient: gViolet,
            shadow: soft(.3, 30, 16, C.violet),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                IconTile(
                  Icons.menu_book_rounded,
                  Colors.white.withValues(alpha: .25),
                  Colors.white,
                  size: 52,
                  iconSize: 26,
                  radius: 18,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Panduan Siaga Banjir',
                        style: t(16, w6, Colors.white),
                      ),
                      Text(
                        'Sebelum, saat, setelah banjir + checklist Tas Siaga. Bisa dibuka offline.',
                        style: t(12, FontWeight.w400, Colors.white, 1.45),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

const _stepIcons = {
  'route': Icons.route_rounded,
  'call': Icons.call_rounded,
  'backpack': Icons.backpack_rounded,
  'description': Icons.description_rounded,
  'cleaning': Icons.cleaning_services_rounded,
  'cloud': Icons.cloud_rounded,
  'groups': Icons.groups_rounded,
  'power': Icons.power_settings_new_rounded,
  'upstairs': Icons.upload_rounded,
  'directions_run': Icons.directions_run_rounded,
  'block': Icons.block_rounded,
  'bolt': Icons.electric_bolt_rounded,
  'accessible': Icons.accessible_rounded,
  'sos': Icons.sos_rounded,
  'campaign': Icons.campaign_rounded,
  'electrical_services': Icons.electrical_services_rounded,
  'no_food': Icons.no_food_rounded,
  'water': Icons.water_drop_rounded,
  'pest': Icons.pest_control_rounded,
  'medical': Icons.medical_services_rounded,
};

/// M14: panduan dibundel di aplikasi (assets/guide.json) supaya tetap terbuka saat offline.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static final _guide = rootBundle
      .loadString('assets/guide.json')
      .then((s) => jsonDecode(s) as Map<String, dynamic>);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _guide,
    builder: (context, snap) {
      final g = snap.data;
      if (g == null) return const SizedBox.shrink();
      final sections = (g['sections'] as List).cast<Map<String, dynamic>>();
      final sec = sections[app.guideTab];
      final bag = (g['bag'] as List).cast<String>();
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset(context) + 8,
          20,
          tabSpace(context),
        ),
        children: stagger([
          Header(
            'Panduan Siaga Banjir',
            sub: 'Bisa dibuka tanpa internet',
            onBack: () => app.go(Scr.emergency),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: soft(.08, 16, 6),
            ),
            child: Row(
              children: [
                for (final (i, s) in sections.indexed)
                  Expanded(
                    child: Semantics(
                      selected: app.guideTab == i,
                      child: Tap(
                        onTap: () => app.set(() => app.guideTab = i),
                        height: 44,
                        radius: 12,
                        color: app.guideTab == i
                            ? C.violetTint
                            : Colors.transparent,
                        child: Center(
                          child: Text(
                            s['title'] as String,
                            style: t(
                              14,
                              w6,
                              app.guideTab == i ? C.violetInk : C.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(sec['heading'] as String, style: t(18, w7)),
          const SizedBox(height: 10),
          for (final (i, st) in (sec['steps'] as List).indexed)
            Appear(
              key: ValueKey('${app.guideTab}-$i'),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Box(
                  radius: 20,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconTile(
                        _stepIcons[st[0]] ?? Icons.check_rounded,
                        C.violetTint,
                        C.violetMid,
                        size: 42,
                        iconSize: 21,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${i + 1}. ${st[1]}',
                          style: t(13, FontWeight.w400, C.ink, 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Text(
            sec['source'] as String,
            style: t(11, FontWeight.w400, C.muted, 1.5),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Icon(Icons.backpack_rounded, size: 22, color: C.violetMid),
              const SizedBox(width: 8),
              Expanded(child: Text('Checklist Tas Siaga', style: t(18, w7))),
              Text(
                '${bag.where(app.bag.contains).length}/${bag.length}',
                style: t(13, w6, C.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Centang yang sudah siap. Tersimpan di HP ini.',
            style: t(12, FontWeight.w400, C.muted),
          ),
          const SizedBox(height: 10),
          Box(
            radius: 22,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final item in bag)
                  CheckboxListTile(
                    value: app.bag.contains(item),
                    onChanged: (_) => app.toggleBag(item),
                    activeColor: C.violet,
                    controlAffinity: ListTileControlAffinity.leading,
                    minTileHeight: 48,
                    title: Text(
                      item,
                      style: t(13, FontWeight.w400, C.ink, 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );
    },
  );
}
