import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../art.dart';
import '../data.dart';
import '../motion.dart';
import '../state.dart';
import '../theme.dart';

/// M05: form laporan. Lokasi GPS (bisa digeser), kategori bergambar, foto 1–3, catatan ≤ 200.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _note = TextEditingController();
  final _photos = <XFile>[];
  late LatLng _pin = app.reportFor?.pos ?? app.center;
  bool _moved = false,
      _sending = false,
      _uploadError = false,
      _errDepth = false,
      _errPhoto = false;
  int? _depth;
  int _quota = Api.reportsPerHour;

  Place? _village; // desa terdekat pin (nama tempat laporan)
  Timer? _lookup;

  @override
  void initState() {
    super.initState();
    Api.quotaLeft().then(
      (q) => mounted ? setState(() => _quota = q) : null,
      onError: (_) {},
    );
    _findVillage();
  }

  /// Nama tempat dari desa terdekat pin; dicari setelah pin berhenti digeser.
  void _findVillage() {
    _lookup?.cancel();
    _lookup = Timer(const Duration(milliseconds: 500), () async {
      try {
        final v = await Api.villageAt(_pin);
        if (mounted) setState(() => _village = v);
      } catch (_) {} // offline/gagal: tetap "Titik pilihan di peta"
    });
  }

  @override
  void dispose() {
    _lookup?.cancel();
    _note.dispose();
    super.dispose();
  }

  String get _place {
    if (app.reportFor != null && !_moved) return app.reportFor!.name;
    final v = _village;
    return v == null
        ? 'Titik pilihan di peta'
        : 'Sekitar ${v.name}, ${v.sub.split(', ').first}';
  }

  Future<void> _addPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (s, icon, label) in const [
                (ImageSource.camera, Icons.photo_camera_rounded, 'Ambil foto'),
                (
                  ImageSource.gallery,
                  Icons.photo_library_rounded,
                  'Pilih dari galeri',
                ),
              ])
                ListTile(
                  leading: Icon(icon, color: C.violet),
                  title: Text(label, style: t(14, w6)),
                  minTileHeight: 56,
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ],
          ),
        ),
      ),
    );
    if (src == null) return;
    // Dikompres di perangkat sebelum dikirim (PRD §9: maks ± 1 MB).
    final x = await ImagePicker().pickImage(
      source: src,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (x == null) return;
    final ext = x.path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png'].contains(ext)) {
      return app.showToast('Foto harus JPG atau PNG');
    }
    if (await x.length() > 5 * 1024 * 1024) {
      return app.showToast('Ukuran foto maksimal 5 MB');
    }
    setState(() {
      _photos.add(x);
      _errPhoto = false;
      _uploadError = false;
    });
  }

  Future<void> _submit() async {
    if (_sending || _quota <= 0) return;
    setState(() {
      _errDepth = _depth == null;
      _errPhoto = _photos.isEmpty;
      _uploadError = false;
    });
    if (_errDepth || _errPhoto) return;
    setState(() => _sending = true);
    try {
      final pointId = await Api.submitReport(
        pos: _pin,
        depth: _depth!,
        name: _place,
        photos: [for (final x in _photos) File(x.path)],
        note: _note.text.trim(),
      );
      HapticFeedback.mediumImpact();
      await app.reportSent(pointId, _pin, _depth!, _photos.length);
    } on ApiError catch (e) {
      // Isian tidak hilang; batas kuota ditampilkan. Tanpa sinyal: simpan & kirim otomatis nanti.
      if (e.code == 'RATE_LIMITED') {
        if (mounted) setState(() => _quota = 0);
      } else if (e.code == 'OFFLINE' || e.code == 'UPLOAD') {
        await app.queueReport(
          pos: _pin,
          depth: _depth!,
          name: _place,
          note: _note.text.trim(),
          photos: [for (final x in _photos) x.path],
        );
        app.showToast(
          'Belum ada sinyal. Laporan disimpan dan dikirim otomatis saat online.',
        );
        app.reportFor = null;
        app.go(Scr.map);
      } else if (mounted) {
        setState(() => _uploadError = true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    final out = quota <= 0;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        topInset(context) + 8,
        16,
        tabSpace(context),
      ),
      children: stagger([
        Header(
          'Lapor Genangan',
          sub: out
              ? 'Batas laporan jam ini tercapai'
              : 'Sisa kuota: $quota dari ${Api.reportsPerHour} laporan jam ini',
          icon: Icons.close_rounded,
          onBack: () => app.go(Scr.map),
        ),
        const SizedBox(height: 18),
        _label('1. Lokasi'),
        Container(
          height: 170,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: soft(.10, 20, 8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: _pin,
                  initialZoom: 16,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                  ),
                  onPositionChanged: (cam, gesture) {
                    if (gesture) {
                      setState(() {
                        _pin = cam.center;
                        _moved = true;
                      });
                      _findVillage();
                    }
                  },
                ),
                children: [baseTiles(context), const MapCredit(compact: true)],
              ),
              const IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 44,
                      color: C.violet,
                      shadows: [
                        Shadow(
                          color: Color(0x66806EF8),
                          blurRadius: 8,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: IgnorePointer(
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: C.ink.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.pan_tool_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Geser peta untuk memindah pin',
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
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.gps_fixed_rounded, size: 20, color: C.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_place, style: t(13, w6)),
                    Text(
                      '${_pin.latitude.toStringAsFixed(4)}, ${_pin.longitude.toStringAsFixed(4)} · ${_moved ? 'dipilih di peta' : 'GPS otomatis'}',
                      style: t(11, FontWeight.w400, C.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _label('2. Seberapa tinggi airnya?'),
        SizedBox(
          // Ikut ukuran huruf sistem supaya label kartu tidak terpotong (172 pada 100%).
          height: 124 + 48 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: depths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final d = depths[i], on = _depth == i;
              return Semantics(
                selected: on,
                label: '${d.label}, ${d.cm}',
                child: Tap(
                  onTap: () => setState(() {
                    HapticFeedback.selectionClick();
                    _depth = i;
                    _errDepth = false;
                  }),
                  width: 112,
                  radius: 22,
                  color: on ? C.blueTint : Colors.white,
                  border: Border.all(
                    color: on ? C.blue : Colors.transparent,
                    width: 2,
                  ),
                  shadow: soft(.08, 16, 6),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  child: ExcludeSemantics(
                    child: Column(
                      children: [
                        DepthFig(i, size: 64),
                        const SizedBox(height: 8),
                        Text(
                          d.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t(12, w6, C.ink, 1.3),
                        ),
                        Text(d.cm, style: t(11, FontWeight.w400, C.muted)),
                        const Spacer(),
                        Container(
                          height: 4,
                          width: 36,
                          decoration: BoxDecoration(
                            color: d.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_errDepth) _err('Pilih salah satu gambar ketinggian air.'),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '3. Foto ', style: t(14, w6)),
                    TextSpan(
                      text: '(wajib, 1–3)',
                      style: t(12, FontWeight.w400, C.muted),
                    ),
                  ],
                ),
              ),
            ),
            Text('JPG/PNG · maks 5 MB', style: t(11, FontWeight.w400, C.muted)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (i, x) in _photos.indexed)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(x.path),
                        fit: BoxFit.cover,
                        semanticLabel: 'Foto ${i + 1}',
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          onPressed: () => setState(() => _photos.removeAt(i)),
                          tooltip: 'Hapus foto ${i + 1}',
                          style: IconButton.styleFrom(
                            backgroundColor: C.ink.withValues(alpha: .75),
                            minimumSize: const Size(28, 28),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_photos.length < 3)
              Tap(
                onTap: _addPhoto,
                width: 96,
                height: 96,
                radius: 20,
                color: Colors.white,
                border: Border.all(color: C.blueLight, width: 2),
                label: 'Tambah foto',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_rounded,
                      size: 26,
                      color: C.blue,
                    ),
                    const SizedBox(height: 4),
                    Text('Tambah', style: t(12, w6, C.blue)),
                  ],
                ),
              ),
          ],
        ),
        if (_errPhoto) _err('Tambahkan minimal 1 foto genangan.'),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '4. Catatan ', style: t(14, w6)),
                    TextSpan(
                      text: '(opsional)',
                      style: t(12, FontWeight.w400, C.muted),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '${_note.text.length}/200',
              style: t(11, FontWeight.w400, C.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          maxLength: 200,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          style: t(13, FontWeight.w400, C.ink, 1.5),
          decoration: inputDeco(
            'Contoh: arus deras di depan minimarket, motor banyak mogok',
          ).copyWith(counterText: ''),
        ),
        const SizedBox(height: 18),
        if (_uploadError) ...[
          const Note(
            'Foto gagal diunggah. Periksa koneksi lalu coba kirim lagi. Isian kamu tidak hilang.',
            icon: Icons.cloud_off_rounded,
            bg: C.redTint,
            fg: C.redInk,
          ),
          const SizedBox(height: 12),
        ],
        if (out) ...[
          Note(
            'Kamu sudah mengirim ${Api.reportsPerHour} laporan dalam 1 jam. Coba lagi nanti.',
            icon: Icons.hourglass_top_rounded,
            bg: C.grayTint,
            fg: C.sub,
          ),
          const SizedBox(height: 12),
        ],
        out
            ? const Btn(
                'Kirim laporan',
                icon: Icons.send_rounded,
                color: Color(0xFFC3C8D4),
              )
            : Btn.violet(
                _sending ? 'Mengirim…' : 'Kirim laporan',
                icon: Icons.send_rounded,
                onTap: _submit,
              ),
      ]),
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(s, style: t(14, w6)),
  );

  Widget _err(String s) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        const Icon(Icons.error_rounded, size: 16, color: C.red),
        const SizedBox(width: 6),
        Expanded(child: Text(s, style: t(12, FontWeight.w400, C.red))),
      ],
    ),
  );
}

/// M06: ringkasan laporan yang baru terkirim.
class SentScreen extends StatelessWidget {
  const SentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = app.sent!;
    final d = depths[s.depth];
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE6E1FF), C.bg],
          stops: [0, .55],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset(context) + 36,
          20,
          tabSpace(context),
        ),
        children: stagger([
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: dur(context, 700),
              curve: Curves.elasticOut,
              builder: (context, v, child) =>
                  Transform.scale(scale: .5 + .5 * v, child: child),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: gViolet,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: soft(.4, 40, 24, C.violet),
                ),
                child: const AppIcon('state_sent', size: 110),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Laporan terkirim',
            textAlign: TextAlign.center,
            style: t(24, w7),
          ),
          const SizedBox(height: 6),
          Text(
            'Terima kasih. Laporanmu sudah tampil di peta dan sedang menunggu dicek verifikator.',
            textAlign: TextAlign.center,
            style: t(14, FontWeight.w400, C.body, 1.55),
          ),
          const SizedBox(height: 20),
          Box(
            radius: 26,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    DepthFig(s.depth, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.point.name, style: t(15, w6)),
                          const SizedBox(height: 4),
                          Pill('${d.label} · ${d.cm}', d.tint, d.ink),
                          const SizedBox(height: 4),
                          Text(
                            '${s.photos} foto · baru saja',
                            style: t(12, FontWeight.w400, C.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: C.line),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: C.grayTint,
                      ),
                      child: Center(
                        child: Text(
                          '?',
                          style: t(13, w7, const Color(0xFF5E6478)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Belum Terverifikasi', style: t(13, w6)),
                          const SizedBox(height: 3),
                          Text(
                            'Warga lain melihat laporanmu dengan label ini. Notifikasi ke pemantau sekitar baru dikirim setelah disetujui.',
                            style: t(12, FontWeight.w400, C.body, 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Btn.primary('Lihat di Peta', onTap: () => app.openPoint(s.point.id)),
          const SizedBox(height: 10),
          Btn(
            'Riwayat laporanku',
            height: 52,
            color: Colors.white,
            fg: C.ink,
            fontSize: 14,
            shadow: soft(.08, 16, 6),
            onTap: () => app.go(Scr.history),
          ),
        ]),
      ),
    );
  }
}

/// M07: riwayat laporan sendiri dengan status.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const st = {
      'approved': (
        'Disetujui',
        Icons.check_circle_rounded,
        C.blueTint2,
        C.blueInk,
      ),
      'pending': ('Menunggu', Icons.schedule_rounded, C.grayTint, C.grayInk),
      'rejected': ('Ditolak', Icons.cancel_rounded, C.redTint, C.redInk),
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        topInset(context) + 8,
        20,
        tabSpace(context),
      ),
      children: stagger([
        Header('Riwayat Laporanku', onBack: () => app.go(Scr.account)),
        const SizedBox(height: 14),
        if (app.reports.isEmpty)
          const EmptyCard(
            Icons.history_rounded,
            'Belum ada laporan',
            'Laporan yang kamu kirim akan muncul di sini.',
            iconColor: C.violetLight,
          ),
        for (final r in app.reports)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Box(
              radius: 22,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DepthFig(r.depth, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: t(14, w6)),
                        const SizedBox(height: 4),
                        Text(
                          '${depths[r.depth].label} · ${dayTime(r.createdAt)}',
                          style: t(12, FontWeight.w400, C.muted),
                        ),
                        const SizedBox(height: 4),
                        Pill(
                          st[r.status]!.$1,
                          st[r.status]!.$3,
                          st[r.status]!.$4,
                          icon: st[r.status]!.$2,
                        ),
                        if (r.reason != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Alasan: ${r.reason}',
                              style: t(12, FontWeight.w400, C.redInk),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}
