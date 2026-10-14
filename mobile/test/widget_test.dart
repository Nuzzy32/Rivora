import 'package:flutter_test/flutter_test.dart';
import 'package:sigap_banjir/data.dart';

void main() {
  test(
    'rain line: reda di slot pertama yang tidak hujan, kosong kalau tidak hujan',
    () {
      // 08.00 UTC = 15.00 WIB = 16.00 WITA = 17.00 WIT; jam tampil menurut zona lokasi, bukan zona HP.
      final t0 = DateTime.utc(2026, 10, 13, 8);
      const p = Place('35.78.22.1001', 'Gayungan', 'Gayungan, Kota Surabaya');
      Slot s(int h, String k) =>
          Slot(t0.add(Duration(hours: h)), k, 27, 30, 2, 10, 80, k);
      Forecast f(String tz, List<Slot> slots) => Forecast(p, tz, slots, t0);
      final rain = [s(0, 'heavy'), s(3, 'storm'), s(6, 'nightcloud')];
      expect(
        f('Asia/Jakarta', rain).rainLine,
        'Hujan diperkirakan reda sekitar 21.00 WIB',
      );
      expect(
        f('Asia/Jayapura', rain).rainLine,
        'Hujan diperkirakan reda sekitar 23.00 WIT',
      );
      expect(f('Asia/Makassar', rain).at(t0), '16.00');
      expect(
        f('Asia/Jakarta', [s(0, 'rain'), s(3, 'heavy')]).rainLine,
        'Hujan diperkirakan berlanjut lebih dari 24 jam',
      );
      expect(f('Asia/Jakarta', [s(0, 'sun'), s(3, 'heavy')]).rainLine, isNull);
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
