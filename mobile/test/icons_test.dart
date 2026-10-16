import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'semua ikon dalam manifest tersedia di bundle dan dapat didekode',
    () async {
      final sheets =
          jsonDecode(
                File(
                  'assets/icon-sheets-2d-v2/manifest.json',
                ).readAsStringSync(),
              )
              as List;
      for (final sheet in sheets) {
        for (final name in sheet['icons'] as List) {
          final data = await rootBundle.load('assets/icons/$name.png');
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 256, reason: '$name');
          expect(frame.image.height, 256, reason: '$name');
          frame.image.dispose();
          codec.dispose();
        }
      }
    },
  );
}
