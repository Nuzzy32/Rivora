import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigap_banjir/data.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Supabase tidak diinisialisasi di tes, jadi setiap fetch gagal seperti saat offline.
void main() {
  test('tanpa cache: error diteruskan', () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(Api.contacts(), throwsA(anything));
  });

  test(
    'offline setelah aplikasi ditutup: pakai data terakhir dari disk',
    () async {
      final at = DateTime(2026, 10, 13, 15, 42);
      SharedPreferences.setMockInitialValues({
        'cache.contacts': jsonEncode({
          'at': at.toIso8601String(),
          'rows': [
            {
              'name': 'BPBD Kota Surabaya',
              'phone': '(031) 5312 144',
              'category': 'bpbd',
            },
          ],
        }),
        'cache.points': jsonEncode({'at': at.toIso8601String(), 'rows': []}),
      });
      final c = await Api.contacts();
      expect(c.single.name, 'BPBD Kota Surabaya');
      expect(await Api.floodPoints(startCenter), isEmpty);
      expect(Api.pointsCachedAt, at);
    },
  );
}
