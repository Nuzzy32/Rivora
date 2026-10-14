import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../art.dart';
import '../data.dart';
import '../state.dart';
import '../theme.dart';

/// Tautan publik satu titik (web/titik.html): bisa dibuka siapa saja di grup WhatsApp.
String pointLink(int id) =>
    'https://sigap-banjir-panel.vercel.app/titik.html?id=$id';

/// Pratinjau kartu bagikan, lalu kirim sebagai gambar + teks + tautan (PRD US-15: tanpa data pelapor).
Future<void> openShare(BuildContext context, FloodPoint p) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ShareSheet(p),
    );

class _ShareSheet extends StatefulWidget {
  final FloodPoint p;
  const _ShareSheet(this.p);

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _send({required bool image}) async {
    setState(() => _busy = true);
    String? path;
    if (image) {
      try {
        final b =
            _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 3);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File(
          '${(await getTemporaryDirectory()).path}/sigap-banjir-${widget.p.id}.png',
        );
        await f.writeAsBytes(png!.buffer.asUint8List());
        path = f.path;
      } catch (_) {} // gagal membuat gambar: tetap kirim teks + tautan
    }
    if (mounted) Navigator.pop(context);
    await app.share(widget.p, imagePath: path);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFDDE3EE),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 14),
          Text('Bagikan kondisi ini', style: t(17, w7)),
          const SizedBox(height: 14),
          RepaintBoundary(key: _card, child: _ShareCard(widget.p)),
          const SizedBox(height: 16),
          _busy
              ? const Btn('Menyiapkan…', color: Color(0xFFC3C8D4))
              : Btn.primary(
                  'Bagikan gambar + tautan',
                  icon: Icons.ios_share_rounded,
                  onTap: () => _send(image: true),
                ),
          TextButton(
            onPressed: _busy ? null : () => _send(image: false),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text('Kirim teks saja', style: t(13, w6, C.sub)),
          ),
        ],
      ),
    ),
  );
}

/// Kartu 4:5 yang dirender menjadi gambar. Warna & ilustrasi ketinggian sama dengan peta.
class _ShareCard extends StatelessWidget {
  final FloodPoint p;
  const _ShareCard(this.p);

  @override
  Widget build(BuildContext context) {
    final d = depths[p.receded ? 0 : p.depth], v = vers[p.verification]!;
    // Tanggal lengkap: gambar bisa dibuka berhari-hari kemudian di grup.
    final at = p.receded ? p.recededAt! : p.updatedAt;
    final when = '${at.day} ${months[at.month - 1]} ${at.year}, ${hm(at)}';
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [d.tint, Colors.white],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: C.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/brand/logo-mark.png', height: 26),
                const SizedBox(width: 8),
                Text('SIGAP Banjir', style: t(13, w7, C.ink)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: v.tint,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(v.icon, size: 14, color: v.color),
                      const SizedBox(width: 4),
                      Text(v.label, style: t(11, w6, v.color)),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t(22, w7, C.ink, 1.2),
            ),
            if (p.district.isNotEmpty)
              Text('Kec. ${p.district}', style: t(13, FontWeight.w400, C.sub)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: d.color.withValues(alpha: .35),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  DepthFig(p.receded ? 0 : p.depth, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.receded ? 'Sudah surut' : d.label,
                          style: t(20, w7, d.ink, 1.2),
                        ),
                        Text(
                          p.receded ? 'Jalan bisa dilalui lagi' : d.cm,
                          style: t(13, w6, d.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${p.receded ? 'Surut' : 'Diperbarui'} $when${p.stale ? ' · perlu konfirmasi' : ''}',
              style: t(12, w5, C.body),
            ),
            Text(
              'Sumber: ${p.source}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t(12, FontWeight.w400, C.sub),
            ),
            const Spacer(),
            Text(
              'Cek kondisi terbaru di aplikasi SIGAP Banjir',
              style: t(11, w6, C.blueInk),
            ),
          ],
        ),
      ),
    );
  }
}
