import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const balaiKota = LatLng(-7.2575, 112.7479);
const distance = Distance();
double meters(LatLng a, LatLng b) => distance.as(LengthUnit.Meter, a, b);

/// Redirect tautan email (reset kata sandi, konfirmasi akun) kembali ke aplikasi.
const authCallback = 'com.rivora.sigapbanjir://login-callback';

const depthKeys = ['none', 'ankle', 'knee', 'waist', 'chest'];
int depthIndex(Object? v) => depthKeys.indexOf(v as String).clamp(0, 4);

LatLng _ll(List c) =>
    LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
DateTime? _ts(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

class FloodPoint {
  final int id;
  final String name, district, source;
  final LatLng pos;
  final List<LatLng>? segment;
  final int? segmentLengthM;
  final int depth; // 0..4 = none, ankle, knee, waist, chest
  final String status; // active | needs_confirmation | receded
  final String verification; // official | verified | unverified
  final DateTime updatedAt;
  final DateTime? recededAt;
  final int reportCount;
  final ({int medianHours, int sample})?
  estimate; // null jika < 5 kejadian (PRD §11)
  final ({DateTime last, int count12m, List<int> monthly})? history;

  FloodPoint.fromRow(Map<String, dynamic> r)
    : id = r['id'] as int,
      name = r['name'] as String,
      district = (r['district'] as String?) ?? 'Surabaya',
      source = r['source'] as String,
      pos = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
      segment = r['segment'] == null
          ? null
          : [
              for (final c in r['segment']['coordinates'] as List)
                _ll(c as List),
            ],
      segmentLengthM = r['segment_length_m'] as int?,
      depth = depthIndex(r['depth']),
      status = r['status'] as String,
      verification = r['verification'] as String,
      updatedAt = _ts(r['updated_at'])!,
      recededAt = _ts(r['receded_at']),
      reportCount = r['report_count'] as int,
      estimate = r['recession_estimate'] == null
          ? null
          : (
              medianHours: (r['recession_estimate']['median_hours'] as num)
                  .round(),
              sample: r['recession_estimate']['sample_size'] as int,
            ),
      history = r['history'] == null
          ? null
          : (
              last: _ts(r['history']['last_event_at'])!,
              count12m: r['history']['count_12m'] as int,
              monthly: (r['history']['monthly_counts'] as List).cast<int>(),
            );

  bool get receded => status == 'receded';
  bool get stale => status == 'needs_confirmation';
}

class Shelter {
  final String id,
      type,
      name,
      address,
      status; // type: posko | faskes; status: open | full | closed
  final String? note, phone;
  final LatLng pos;

  Shelter.fromRow(Map<String, dynamic> r)
    : id = '${r['id']}',
      type = r['type'] as String,
      name = r['name'] as String,
      address = r['address'] as String,
      status = r['status'] as String,
      note = r['note'] as String?,
      phone = r['phone'] as String?,
      pos = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
}

class Contact {
  final String name,
      phone,
      category; // category: bpbd | damkar | ambulans | polisi
  const Contact(this.name, this.phone, this.category);
}

class Slot {
  final DateTime time;
  final String kind, desc;
  final int temp, feels, wind, hum;
  final double rainMm;
  const Slot(
    this.time,
    this.kind,
    this.temp,
    this.feels,
    this.rainMm,
    this.wind,
    this.hum,
    this.desc,
  );

  Slot.fromJson(Map<String, dynamic> j)
    : time = _ts(j['time'])!,
      kind = j['kind'] as String,
      desc = j['desc'] as String,
      temp = (j['temp'] as num).round(),
      feels = (j['feels'] as num).round(),
      rainMm = (j['rain_mm'] as num).toDouble(),
      wind = (j['wind'] as num).round(),
      hum = (j['hum'] as num).round();

  bool get rainy =>
      const ['heavy', 'storm', 'rain', 'nightrain'].contains(kind);
}

class Forecast {
  final String district;
  final List<Slot> slots;
  final DateTime fetchedAt;
  final String? warning;
  const Forecast(this.district, this.slots, this.fetchedAt, this.warning);

  /// Data lebih tua dari 2 jam = gagal diperbarui; tampilkan dengan keterangan waktunya (US-09).
  bool get stale => DateTime.now().difference(fetchedAt).inHours >= 2;

  /// PRD US-10: jam reda = slot pertama yang tidak hujan. null = sedang tidak hujan.
  String? get rainLine {
    if (slots.isEmpty || !slots.first.rainy) return null;
    final dry = slots.where((s) => !s.rainy).firstOrNull;
    return dry == null
        ? 'Hujan diperkirakan berlanjut lebih dari 24 jam'
        : 'Hujan diperkirakan reda sekitar ${hm(dry.time)}';
  }
}

class MyReport {
  final String name, status; // pending | approved | rejected
  final int depth;
  final DateTime createdAt;
  final String? reason;
  const MyReport(
    this.name,
    this.depth,
    this.createdAt,
    this.status, [
    this.reason,
  ]);
}

class Notif {
  final int id, pointId;
  final String title, body;
  final DateTime time;
  bool unread;
  Notif(
    this.id,
    this.title,
    this.body,
    this.time,
    this.pointId, {
    this.unread = true,
  });
}

class WatchLoc {
  final int id;
  final String place;
  final LatLng pos;
  String label;
  int radius;
  WatchLoc(this.id, this.label, this.place, this.pos, this.radius);
}

class RiskArea {
  final String label, level; // kadang | sering | sangat_sering
  final int count;
  final List<LatLng> polygon;
  const RiskArea(this.label, this.level, this.count, this.polygon);
}

class User {
  final String id, name, email, role;
  final String? pendingEmail;
  const User(this.id, this.name, this.email, this.role, [this.pendingEmail]);
}

class ApiError implements Exception {
  final String code, message;
  const ApiError(this.code, this.message);
  @override
  String toString() => message;
}

class Radar {
  final String host;
  final List<({DateTime time, String path})> frames;
  const Radar(this.host, this.frames);
  String url(int i) => '$host${frames[i].path}/256/{z}/{x}/{y}/2/1_1.png';
}

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime d) => '${two(d.hour)}.${two(d.minute)}';

String ago(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'Baru saja';
  if (m < 60) return '$m menit lalu';
  final h = m ~/ 60, r = m % 60;
  if (h < 24) return '$h jam${r > 0 ? ' $r menit' : ''} lalu';
  return '${h ~/ 24} hari lalu';
}

String dayTime(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  final day = days == 0
      ? 'Hari ini'
      : days == 1
      ? 'Kemarin'
      : '${d.day} ${months[d.month - 1]}';
  return '$day, ${hm(d)}';
}

const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];
const weekdays = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

String km(double m) => m < 1000
    ? '${m.round()} m'
    : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

String _ewkt(LatLng p) => 'SRID=4326;POINT(${p.longitude} ${p.latitude})';

SupabaseClient get _db => Supabase.instance.client;

/// Semua akses data lewat Supabase (RLS menjaga hak akses di server).
class Api {
  /// Ubah error teknis jadi pesan yang bisa dibaca warga (PRD §11: tanpa detail teknis).
  static Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ApiError {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.hint == 'RATE_LIMITED' ||
          e.hint == 'WATCH_LIMIT' ||
          e.code == '28P01' ||
          e.code == '42501') {
        throw ApiError(e.hint ?? e.code ?? 'ERROR', e.message);
      }
      throw const ApiError(
        'SERVER',
        'Terjadi gangguan di server. Coba lagi sebentar lagi.',
      );
    } on AuthException catch (e) {
      throw ApiError(e.code ?? 'AUTH', switch (e.code) {
        'invalid_credentials' => 'Email atau kata sandi salah.',
        'email_not_confirmed' =>
          'Email belum dikonfirmasi. Buka link konfirmasi di emailmu dulu.',
        'user_already_exists' ||
        'email_exists' => 'Email ini sudah terdaftar. Coba masuk.',
        'weak_password' =>
          'Kata sandi terlalu lemah. Gunakan minimal 8 karakter.',
        'over_request_rate_limit' || 'over_email_send_rate_limit' =>
          'Terlalu banyak percobaan. Coba lagi dalam beberapa menit.',
        'same_password' => 'Kata sandi baru harus berbeda.',
        _ => 'Gagal memproses akun. Coba lagi.',
      });
    } on SocketException {
      throw const ApiError('OFFLINE', 'Tidak ada koneksi internet.');
    } on StorageException {
      throw const ApiError('UPLOAD', 'Foto gagal diunggah.');
    }
  }

  // --- Peta
  static Future<List<FloodPoint>> floodPoints(LatLng at) => _call(() async {
    final rows =
        await _db.rpc(
              'flood_points_near',
              params: {'at_lat': at.latitude, 'at_lng': at.longitude},
            )
            as List;
    return [
      for (final r in rows) FloodPoint.fromRow(r as Map<String, dynamic>),
    ];
  });

  static Future<List<Shelter>> shelters() => _call(() async {
    final rows = await _db.rpc('shelters_list') as List;
    return [for (final r in rows) Shelter.fromRow(r as Map<String, dynamic>)];
  });

  static Future<List<Contact>> contacts() => _call(() async {
    final rows = await _db
        .from('emergency_contacts')
        .select('name, phone, category')
        .order('sort_order');
    return [
      for (final r in rows)
        Contact(
          r['name'] as String,
          r['phone'] as String,
          r['category'] as String,
        ),
    ];
  });

  static String riskSince = '';
  static Future<List<RiskArea>> riskAreas() => _call(() async {
    final rows = await _db.rpc('risk_areas') as List;
    final first = await _db
        .from('flood_events')
        .select('started_at')
        .order('started_at')
        .limit(1)
        .maybeSingle();
    final since = _ts(first?['started_at']);
    if (since != null) riskSince = '${months[since.month - 1]} ${since.year}';
    return [
      for (final r in rows)
        RiskArea(
          r['label'] as String,
          r['level'] as String,
          r['event_count_12m'] as int,
          [
            for (final c in (r['polygon']['coordinates'] as List).first as List)
              _ll(c as List),
          ],
        ),
    ];
  });

  /// Foto laporan yang sudah disetujui, sebagai signed URL 1 jam.
  static Future<List<String>> pointPhotos(int pointId) => _call(() async {
    final paths =
        (await _db.rpc('point_photos', params: {'point_id': pointId}) as List)
            .cast<String>();
    if (paths.isEmpty) return <String>[];
    final urls = await _db.storage
        .from('report-photos')
        .createSignedUrlsResult(paths, 3600);
    return [for (final u in urls.whereType<SignedUrlSuccess>()) u.signedUrl];
  });

  // --- Prakiraan (diisi Edge Function `bmkg-forecast` tiap jam)
  static const districts = [
    'Gayungan',
    'Wonokromo',
    'Gubeng',
    'Tegalsari',
    'Rungkut',
    'Benowo',
  ];

  static Future<Forecast?> forecast(String district) => _call(() async {
    final r = await _db
        .from('forecast_cache')
        .select()
        .eq('district', district)
        .maybeSingle();
    if (r == null) return null;
    final j = r['forecast_json'] as Map<String, dynamic>;
    final now = DateTime.now().subtract(const Duration(hours: 3));
    return Forecast(
      district,
      [
        for (final s in j['slots'] as List)
          Slot.fromJson(s as Map<String, dynamic>),
      ].where((s) => s.time.isAfter(now)).toList(),
      _ts(r['fetched_at'])!,
      j['warning'] as String?,
    );
  });

  // --- Akun
  static Future<User?> currentUser() => _call(() async {
    final u = _db.auth.currentUser;
    if (u == null) return null;
    final p = await _db
        .from('profiles')
        .select('name, role')
        .eq('id', u.id)
        .maybeSingle();
    return User(
      u.id,
      (p?['name'] as String?) ?? u.email!.split('@').first,
      u.email!,
      (p?['role'] as String?) ?? 'warga',
      u.newEmail,
    );
  });

  static Future<User> login(String email, String pw) => _call(() async {
    await _db.auth.signInWithPassword(email: email, password: pw);
    return (await currentUser())!;
  });

  /// null = akun dibuat tapi perlu konfirmasi email dulu.
  static Future<User?> register(String name, String email, String pw) =>
      _call(() async {
        final r = await _db.auth.signUp(
          email: email,
          password: pw,
          data: {'name': name},
          emailRedirectTo: authCallback,
        );
        return r.session == null ? null : await currentUser();
      });

  static Future<void> logout() => _db.auth.signOut();

  /// Pesan di layar selalu sama, terdaftar atau tidak (PRD US-06).
  static Future<void> forgotPassword(String email) => _call(
    () => _db.auth.resetPasswordForEmail(email, redirectTo: authCallback),
  );

  static Future<void> resetPassword(String pw) =>
      _call(() => _db.auth.updateUser(UserAttributes(password: pw)));

  static Future<User> updateProfile({
    required String name,
    required String email,
    String? currentPw,
    String? newPw,
  }) => _call(() async {
    final u = _db.auth.currentUser!;
    await _db.from('profiles').update({'name': name}).eq('id', u.id);
    if (newPw != null) {
      // Pastikan kata sandi lama benar sebelum mengganti.
      await _db.auth.signInWithPassword(email: u.email!, password: currentPw!);
      await _db.auth.updateUser(UserAttributes(password: newPw));
    }
    if (email != u.email) {
      await _db.auth.updateUser(
        UserAttributes(email: email),
        emailRedirectTo: authCallback,
      );
    }
    return (await currentUser())!;
  });

  static Future<void> deleteAccount(String pw) => _call(() async {
    final u = _db.auth.currentUser!;
    // Cek kata sandi dulu supaya foto tidak terhapus kalau sandinya salah.
    try {
      await _db.auth.signInWithPassword(email: u.email!, password: pw);
    } on AuthException {
      throw const ApiError('28P01', 'Kata sandi salah.');
    }
    final bucket = _db.storage.from('report-photos');
    final files = await bucket.list(path: u.id);
    if (files.isNotEmpty) {
      await bucket.remove([for (final f in files) '${u.id}/${f.name}']);
    }
    await _db.rpc('delete_my_account', params: {'password': pw});
    await _db.auth.signOut();
  });

  // --- Laporan
  static Future<int> quotaLeft() => _call(() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 5;
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    final n = await _db
        .from('reports')
        .select('id')
        .eq('user_id', uid)
        .gte('created_at', since)
        .count(CountOption.exact);
    return 5 - n.count;
  });

  /// Unggah foto ke folder pengguna lalu simpan laporan. Server menempelkan ke titik ≤ 100 m.
  static Future<int> submitReport({
    required LatLng pos,
    required int depth,
    required String name,
    required List<File> photos,
    String note = '',
  }) => _call(() async {
    final uid = _db.auth.currentUser!.id;
    final bucket = _db.storage.from('report-photos');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final paths = <String>[];
    for (final (i, f) in photos.indexed) {
      final png = f.path.toLowerCase().endsWith('.png');
      final path = '$uid/${stamp}_$i.${png ? 'png' : 'jpg'}';
      await bucket.upload(
        path,
        f,
        fileOptions: FileOptions(contentType: png ? 'image/png' : 'image/jpeg'),
      );
      paths.add(path);
    }
    final r = await _db
        .from('reports')
        .insert({
          'location': _ewkt(pos),
          'place_name': name,
          'depth': depthKeys[depth],
          'photo_paths': paths,
          if (note.isNotEmpty) 'note': note,
        })
        .select('flood_point_id')
        .single();
    return r['flood_point_id'] as int;
  });

  static Future<List<MyReport>> myReports() => _call(() async {
    final rows = await _db
        .from('reports')
        .select(
          'place_name, depth, created_at, status, reject_reason, flood_points(name)',
        )
        .order('created_at', ascending: false);
    const reasons = {
      'foto_tidak_relevan': 'Foto tidak relevan',
      'lokasi_salah': 'Lokasi salah',
      'duplikat': 'Duplikat',
      'lainnya': 'Lainnya',
    };
    return [
      for (final r in rows)
        MyReport(
          (r['flood_points']?['name'] ?? r['place_name'] ?? 'Laporan')
              as String,
          depthIndex(r['depth']),
          _ts(r['created_at'])!,
          r['status'] as String,
          reasons[r['reject_reason']],
        ),
    ];
  });

  // --- Notifikasi
  static Future<List<Notif>> notifications() => _call(() async {
    final rows = await _db
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return [
      for (final r in rows)
        Notif(
          r['id'] as int,
          r['title'] as String,
          r['body'] as String,
          _ts(r['created_at'])!,
          (r['flood_point_id'] as int?) ?? 0,
          unread: r['read_at'] == null,
        ),
    ];
  });

  static Future<void> markRead(int id) => _call(
    () => _db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id),
  );

  static Future<void> clearNotifications() => _call(
    () => _db
        .from('notifications')
        .delete()
        .eq('user_id', _db.auth.currentUser!.id),
  );

  // --- Lokasi pantauan
  static Future<List<WatchLoc>> watchLocations() => _call(() async {
    final rows = await _db.rpc('my_watch_locations') as List;
    return [
      for (final r in rows)
        WatchLoc(
          r['id'] as int,
          r['label'] as String,
          r['place'] as String,
          LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
          r['radius_m'] as int,
        ),
    ];
  });

  static Future<WatchLoc> addWatch(
    String label,
    String place,
    LatLng pos,
    int radius,
  ) => _call(() async {
    final r = await _db
        .from('watch_locations')
        .insert({
          'label': label,
          'place': place,
          'location': _ewkt(pos),
          'radius_m': radius,
        })
        .select('id')
        .single();
    return WatchLoc(r['id'] as int, label, place, pos, radius);
  });

  static Future<void> updateWatch(WatchLoc w) => _call(
    () => _db
        .from('watch_locations')
        .update({'label': w.label, 'radius_m': w.radius})
        .eq('id', w.id),
  );

  static Future<void> deleteWatch(int id) =>
      _call(() => _db.from('watch_locations').delete().eq('id', id));

  /// Saran alamat untuk "Cari alamat". ponytail: daftar tetap; ganti ke geocoder (mis. Nominatim via Edge Function) bila perlu.
  static const addresses = [
    ('Jl. Candi Lempung, Benowo', LatLng(-7.2432, 112.6390)),
    ('Jl. Ketintang, Gayungan', LatLng(-7.3105, 112.7280)),
    ('Jl. Ketintang Baru, Gayungan', LatLng(-7.3132, 112.7276)),
    ('Jl. Raya Darmo, Tegalsari', LatLng(-7.2873, 112.7381)),
    ('Jl. Kertajaya Indah, Mulyorejo', LatLng(-7.2795, 112.7790)),
    ('Jl. Ahmad Yani, Wonokromo', LatLng(-7.3083, 112.7350)),
    ('Jl. Rungkut Madya, Rungkut', LatLng(-7.3330, 112.7700)),
    ('Jl. Jemursari, Wonocolo', LatLng(-7.3230, 112.7440)),
    ('Jl. Gubeng Pojok, Gubeng', LatLng(-7.2650, 112.7500)),
    ('Jl. Dharmahusada, Gubeng', LatLng(-7.2680, 112.7680)),
  ];

  /// Rain Viewer diambil langsung oleh aplikasi (PRD §10), tanpa kunci API.
  static Future<Radar> radar() async {
    final r = await http
        .get(Uri.parse('https://api.rainviewer.com/public/weather-maps.json'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      throw const ApiError('RADAR', 'Radar sedang tidak tersedia');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final past = (j['radar']['past'] as List).cast<Map<String, dynamic>>();
    if (past.isEmpty) {
      throw const ApiError('RADAR', 'Radar sedang tidak tersedia');
    }
    return Radar(j['host'] as String, [
      for (final f in past)
        (
          time: DateTime.fromMillisecondsSinceEpoch((f['time'] as int) * 1000),
          path: f['path'] as String,
        ),
    ]);
  }
}
