import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sigap_banjir/data.dart';
import 'package:sigap_banjir/main.dart';
import 'package:sigap_banjir/state.dart';

/// Smoke test: semua layar + transisi + sheet + ganti slot prakiraan dirender tanpa error/overflow.
void main() {
  const place = Place(
    '35.78.22.1001',
    'Gayungan',
    'Gayungan, Gayungan, Kota Surabaya, Jawa Timur',
  );
  for (final (size, scale) in const [
    (Size(402, 874), 1.0),
    (Size(360, 740), 1.3),
  ]) {
    testWidgets(
      'semua layar dan animasi tanpa error (${size.width.round()} dp, huruf ${(scale * 100).round()}%)',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        GoogleFonts.config.allowRuntimeFetching = false;
        final now = DateTime.now();
        app
          ..screen = Scr.map
          ..pointsLoading = false
          ..user = const User('u1', 'Warga Uji', 'uji@example.invalid', 'warga')
          ..points = [
            FloodPoint.fromRow({
              'id': 1,
              'name': 'Jl. Ketintang Baru',
              'district': 'Gayungan',
              'lat': -7.3132,
              'lng': 112.7276,
              'segment': null,
              'segment_length_m': null,
              'depth': 'waist',
              'status': 'active',
              'verification': 'verified',
              'source': 'Laporan warga',
              'report_count': 2,
              'updated_at': now.toIso8601String(),
              'receded_at': null,
              'recession_estimate': {'median_hours': 2, 'sample_size': 6},
              'history': null,
            }),
          ]
          ..fcPlace = place
          ..forecast = Forecast(
            place,
            'Asia/Jakarta',
            [
              for (var i = 0; i < 6; i++)
                Slot(
                  now.add(Duration(hours: 3 * i)),
                  [
                    'heavy',
                    'storm',
                    'nightrain',
                    'nightcloud',
                    'partly',
                    'sun',
                  ][i],
                  27 - i,
                  30,
                  2.5,
                  10,
                  80,
                  'Uji',
                ),
            ],
            now,
            'Peringatan uji',
          )
          ..fcLoading = false;

        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(const SigapApp());
        Future<void> settle() async {
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        for (final s in Scr.values) {
          if (s == Scr.reportSent) {
            app.sent = (point: app.points.first, depth: 3, photos: 2);
          }
          app.go(s);
          await settle();
        }

        // Ganti slot prakiraan beberapa kali (animasi kartu, angka, latar).
        app.go(Scr.forecast);
        await settle();
        for (final i in [1, 3, 0, 5]) {
          app.set(() => app.fcSlot = i);
          await settle();
        }

        // Sheet detail lokasi muncul lalu ditutup.
        app.go(Scr.map);
        await settle();
        app.set(() => app.selPoint = 1);
        await settle();
        app.back();
        await settle();

        // Halaman tak berujung (LiveWx, Shimmer) sengaja tidak di-pumpAndSettle.
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
