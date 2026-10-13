import 'package:flutter_test/flutter_test.dart';
import 'package:sigap_banjir/data.dart';

void main() {
  test(
    'rain line: reda di slot pertama yang tidak hujan, kosong kalau tidak hujan',
    () {
      final t0 = DateTime(2026, 10, 13, 15);
      Slot s(int h, String k) =>
          Slot(t0.add(Duration(hours: h)), k, 27, 30, 2, 10, 80, k);
      expect(
        Forecast(
          'X',
          [s(0, 'heavy'), s(3, 'storm'), s(6, 'nightcloud')],
          t0,
          null,
        ).rainLine,
        'Hujan diperkirakan reda sekitar 21.00',
      );
      expect(
        Forecast('X', [s(0, 'rain'), s(3, 'heavy')], t0, null).rainLine,
        'Hujan diperkirakan berlanjut lebih dari 24 jam',
      );
      expect(
        Forecast('X', [s(0, 'sun'), s(3, 'heavy')], t0, null).rainLine,
        isNull,
      );
    },
  );

  test('baris RPC flood_points_near terbaca lengkap', () {
    final p = FloodPoint.fromRow({
      'id': 1,
      'name': 'Jl. Ketintang Baru',
      'district': null,
      'lat': -7.3132,
      'lng': 112.7276,
      'segment': {
        'type': 'LineString',
        'coordinates': [
          [112.7251, -7.3129],
          [112.7276, -7.3132],
        ],
      },
      'segment_length_m': 450,
      'depth': 'knee',
      'status': 'active',
      'verification': 'verified',
      'source': 'Laporan warga',
      'report_count': 4,
      'updated_at': '2026-10-13T15:42:00+07:00',
      'receded_at': null,
      'recession_estimate': {
        'median_hours': 3,
        'sample_size': 7,
        'basis': 'history',
      },
      'history': {
        'last_event_at': '2026-10-10T16:20:00+07:00',
        'count_12m': 7,
        'monthly_counts': [0, 2, 1, 0, 0, 0, 0, 0, 0, 1, 3, 0],
      },
    });
    expect(p.depth, 2);
    expect(p.district, 'Surabaya');
    expect(p.segment!.first.latitude, -7.3129);
    expect(p.estimate!.medianHours, 3);
    expect(p.history!.monthly.length, 12);
  });

  test('ago() memakai bahasa sehari-hari', () {
    expect(
      ago(DateTime.now().subtract(const Duration(minutes: 12))),
      '12 menit lalu',
    );
    expect(
      ago(DateTime.now().subtract(const Duration(minutes: 200))),
      '3 jam 20 menit lalu',
    );
  });
}
