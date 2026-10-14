import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// Setiap jenis cuaca yang dipakai Wx/WxAnim punya animasi Lottie yang valid dan berulang 4 detik.
void main() {
  for (final kind in [
    'sun',
    'partly',
    'cloud',
    'rain',
    'heavy',
    'storm',
    'nightcloud',
    'nightrain',
  ]) {
    test('animasi $kind terbaca', () async {
      final c = await LottieComposition.fromBytes(
        File('assets/lottie/$kind.json').readAsBytesSync(),
      );
      expect(c.duration, const Duration(seconds: 4));
      expect(c.bounds.width, 400);
    });
  }
}
