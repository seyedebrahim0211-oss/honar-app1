import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:excel/excel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'staff_auth.dart';

const formId = 8;
const formUrl = 'https://honarmardomi.ir/form/jan-fada/';
const submitUrl = 'https://honarmardomi.ir/wp-json/negarform/v1/submit/$formId';
const consentValue = 'با ثبت و نگهداری مشخصات و عکس برای مدیریت پویش موافقم';

class Registrant {
  Registrant({required this.id, required this.data, required this.photo, this.status = 'pending', this.code = '', this.error = '', required this.created});
  final String id;
  final Map<String, String> data;
  final String photo;
  final String status;
  final String code;
  final String error;
  final String created;
  String get name => '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'.trim();
  String get mobile => data['mobile'] ?? '';
  Registrant updated({String? status, String? code, String? error}) => Registrant(
    id: id, data: data, photo: photo, status: status ?? this.status, code: code ?? this.code,
    error: error ?? this.error, created: created,
  );
  Map<String, Object?> toDb() => {
    'id': id, 'payload': jsonEncode(data), 'photo': photo, 'status': status,
    'code': code, 'error': error, 'created_at': created,
  };
  factory Registrant.fromDb(Map<String, Object?> row) => Registrant(
    id: row['id']! as String,
    data: (jsonDecode(row['payload']! as String) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v.toString())),
    photo: row['photo']! as String,
    status: row['status']! as String,
    code: row['code']! as String,
    error: row['error']! as String,
    created: row['created_at']! as String,
  );
}

class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();
  static const _vault = FlutterSecureStorage();
  Database? _db;
  SecretKey? _imageKey;
  final _cipher = AesGcm.with256bits();
  final _uuid = const Uuid();

  Future<void> initialize() async {
    if (_db != null) return;
    var dbSecret = await _vault.read(key: 'db_secret_v1');
    if (dbSecret == null) {
      dbSecret = base64UrlEncode(_randomBytes(32));
      await _vault.write(key: 'db_secret_v1', value: dbSecret);
    }
    var imageSecret = await _vault.read(key: 'photo_secret_v1');
    if (imageSecret == null) {
      imageSecret = base64Encode(_randomBytes(32));
      await _vault.write(key: 'photo_secret_v1', value: imageSecret);
    }
    _imageKey = SecretKey(base64Decode(imageSecret));
    final folder = await getApplicationSupportDirectory();
    _db = await openDatabase(
      p.join(folder.path, 'janfada.enc.db'), password: dbSecret, version: 1,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE registrants (
          id TEXT PRIMARY KEY, payload TEXT NOT NULL, photo TEXT NOT NULL,
          status TEXT NOT NULL, code TEXT NOT NULL, error TEXT NOT NULL,
          created_at TEXT NOT NULL)''');
      },
    );
  }

  List<int> _randomBytes(int count) {
    final r = Random.secure();
    return List<int>.generate(count, (_) => r.nextInt(256));
  }
  Future<String> _photoDir() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
  Future<String> writeEncryptedImage(Uint8List raw, String id) async {
    final box = await _cipher.encrypt(raw, secretKey: _imageKey!);
    final encrypted = Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
    final location = p.join(await _photoDir(), '$id.enc');
    await File(location).writeAsBytes(encrypted, flush: true);
    return location;
  }
  Future<Uint8List> readImage(String location) async {
    final raw = await File(location).readAsBytes();
    if (raw.length < 29) throw const FormatException('تصویر رمزنگاری‌شده معتبر نیست.');
    final box = SecretBox(raw.sublist(12, raw.length - 16), nonce: raw.sublist(0, 12), mac: Mac(raw.sublist(raw.length - 16)));
    return Uint8List.fromList(await _cipher.decrypt(box, secretKey: _imageKey!));
  }
  Future<Registrant> create(Map<String, String> data, Uint8List photo) async {
    final id = _uuid.v4();
    final encryptedFile = await writeEncryptedImage(photo, id);
    final reg = Registrant(
      id: id, data: {...data, 'device_uid': id}, photo: encryptedFile,
      created: DateTime.now().toIso8601String(),
    );
    try { await _db!.insert('registrants', reg.toDb()); } catch (_) { await File(encryptedFile).delete(); rethrow; }
    return reg;
  }
  Future<void> edit(Registrant existing, Map<String, String> data, Uint8List jpeg) async {
    if (existing.status == 'synced') throw StateError('ویرایش پرونده ارسال‌شده باید در پنل مدیر انجام شود.');
    await writeEncryptedImage(jpeg, existing.id);
    await update(Registrant(
      id: existing.id, data: {...data, 'device_uid': existing.id}, photo: existing.photo,
      status: 'pending', code: existing.code, error: '', created: existing.created,
    ));
  }
  Future<List<Registrant>> all() async {
    final rows = await _db!.query('registrants', orderBy: 'created_at DESC');
    return rows.map(Registrant.fromDb).toList();
  }
  Future<void> update(Registrant reg) async {
    await _db!.update('registrants', reg.toDb(), where: 'id=?', whereArgs: [reg.id]);
  }
  Future<bool> isNationalIdDuplicate(String nationalId, {String? excludeId}) async {
    final digits = nationalId.trim();
    if (digits.isEmpty) return false;
    final records = await all();
    return records.any((r) => r.id != excludeId &&
      (r.data['nid'] ?? '').trim() == digits);
  }

  Future<bool> isDuplicate(String first, String last, String mobile) async {
    final full = (await all()).where((r) => r.data['first_name'] == first && r.data['last_name'] == last && r.mobile == mobile);
    return full.isNotEmpty;
  }
  Future<void> close() async => _db?.close();
}

class FormSync {
  FormSync(this.store);
  final LocalStore store;
  bool busy = false;
  Future<int> pendingCount() async => (await store.all()).where((r) => r.status != 'synced').length;

  Future<(int synced, int failed)> sync() async {
    if (busy) return (0, 0);
    busy = true;
    var success = 0, failed = 0;
    try {
      final session = await StaffAuth.instance.token();
      if (session == null || session.isEmpty) return (0, 0);
      final authHeaders = await StaffAuth.instance.sessionHeaders();
      final records = (await store.all()).where((r) => r.status != 'synced').toList();
      for (final record in records) {
        try {
          final req = http.MultipartRequest('POST', Uri.parse(submitUrl));
          req.headers.addAll(authHeaders);
          for (final entry in record.data.entries) {
            if (entry.key != 'consent' && entry.key != 'activity' &&
                entry.key != 'birth_date' && entry.value.trim().isNotEmpty) {
              req.fields[entry.key] = entry.value;
            }
          }
          // Upgrade earlier offline records that stored a single Jalali date.
          if (!req.fields.containsKey('birth_year')) {
            final parts = (record.data['birth_date'] ?? '').split('/');
            const months = ['فروردین','اردیبهشت','خرداد','تیر','مرداد','شهریور',
              'مهر','آبان','آذر','دی','بهمن','اسفند'];
            if (parts.length == 3) {
              final m = int.tryParse(parts[1]);
              if (m != null && m >= 1 && m <= 12) {
                req.fields['birth_year'] = parts[0];
                req.fields['birth_month'] = months[m - 1];
                req.fields['birth_day'] = parts[2].padLeft(2, '0');
              }
            }
          }
          req.fields['consent[0]'] = consentValue;
          final image = await store.readImage(record.photo);
          req.files.add(http.MultipartFile.fromBytes('photo', image,
            filename: '${record.id}.jpg', contentType: MediaType('image', 'jpeg')));
          final client = http.Client();
          late http.StreamedResponse response;
          late String body;
          try {
            response = await client.send(req).timeout(const Duration(seconds: 50));
            body = await response.stream.bytesToString();
          } finally { client.close(); }
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          if (response.statusCode == 401 || response.statusCode == 403) {
            await StaffAuth.instance.clearSession();
            await store.update(record.updated(status: 'error', error: 'دسترسی این شماره منقضی یا لغو شده است. دوباره با پیامک وارد شوید.'));
            failed++;
            break;
          } else if (response.statusCode == 200 && decoded['ok'] == true) {
            await store.update(record.updated(status: 'synced', code: (decoded['code'] ?? '').toString(), error: ''));
            success++;
          } else if (response.statusCode == 422 && decoded['errors'] is Map &&
              (decoded['errors'] as Map).containsKey('device_uid') &&
              (decoded['errors'] as Map).length == 1) {
            // The first submission may have succeeded but its HTTP reply was lost.
            // Only the authenticated receipt endpoint can confirm the real code.
            final client = http.Client();
            String? code;
            try {
              final check = await client.get(
                Uri.parse('https://honarmardomi.ir/wp-json/negarform/v1/janfada/receipt/${record.id}'),
                headers: authHeaders,
              ).timeout(const Duration(seconds: 20));
              if (check.statusCode == 200) {
                final answer = jsonDecode(check.body) as Map<String, dynamic>;
                if (answer['ok'] == true) code = answer['code']?.toString();
              }
            } finally { client.close(); }
            if (code != null && code.isNotEmpty) {
              await store.update(record.updated(status: 'synced', code: code, error: ''));
              success++;
            } else {
              await store.update(record.updated(status: 'error', error: 'رسید قبلی هنوز تأیید نشده است.'));
              failed++;
            }
          } else {
            final errorFields = decoded['errors'];
            final nationalIdError = errorFields is Map ? errorFields['nid'] : null;
            final readableError = nationalIdError != null
              ? 'کد ملی: $nationalIdError'
              : (decoded['message'] ?? 'خطای سرور ${response.statusCode}').toString();
            await store.update(record.updated(status: 'error', error: readableError));
            failed++;
            if (response.statusCode == 429 || response.statusCode >= 500) break;
          }
          if (success > 0) await Future<void>.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          await store.update(record.updated(status: 'error', error: 'ارسال ممکن نشد؛ پرونده آفلاین محفوظ است.'));
          failed++;
          break; // Network unavailable: do not hammer server.
        }
      }
    } finally { busy = false; }
    return (success, failed);
  }
}

class ExportedFiles {
  ExportedFiles({required this.xlsx, required this.zip});
  final File xlsx;
  final File zip;
}

class DossierExporter {
  DossierExporter(this.store);
  final LocalStore store;
  static const _headers = <String>[
    'شناسه آفلاین','کد نگارفرم','وضعیت ارسال','نام','نام خانوادگی',
    'نام پدر','شماره همراه','کد ملی','تاریخ تولد یکپارچه','سال تولد',
    'ماه تولد','روز تولد','شهر یا روستا','مدرک تحصیلی',
    'محل تحصیل','محل کار','وضعیت نظام وظیفه','تخصص و مهارت‌ها',
    'علاقه‌مندی‌ها','نشانی','توضیحات','عکس در بسته پیوست','زمان ثبت',
  ];
  static const _fieldKeys = <String>[
    'first_name','last_name','father_name','mobile','nid','birth_date',
    'birth_year','birth_month','birth_day','city','education_level',
    'study_place','work_place','military_status','specialty','interests',
    'address','notes',
  ];
  static const _fieldLabels = <String>[
    'نام','نام خانوادگی','نام پدر','شماره همراه','کد ملی',
    'تاریخ تولد (متنی)','سال تولد','ماه تولد','روز تولد',
    'شهر یا روستا','مدرک تحصیلی','محل تحصیل','محل کار',
    'وضعیت نظام وظیفه','تخصص و مهارت‌ها','علاقه‌مندی‌ها',
    'نشانی','توضیحات',
  ];
  List<CellValue> _cells(Iterable<String> values) => values.map((v) => TextCellValue(v) as CellValue).toList();

  Future<ExportedFiles> export() async {
    final people = await store.all();
    final book = Excel.createExcel();
    book.rename('Sheet1', 'فهرست ثبت‌نام');
    final summary = book['فهرست ثبت‌نام'];
    summary.appendRow(_cells(_headers));
    final bundle = Archive();
    for (var i = 0; i < people.length; i++) {
      final r = people[i];
      final photoName = 'images/${r.id}.jpg';
      summary.appendRow(_cells([
        r.id, r.code, r.status == 'synced' ? 'ارسال‌شده' : 'در انتظار ارسال',
        ..._fieldKeys.map((k) => r.data[k] ?? ''), photoName, r.created,
      ]));
      final sheet = book['پرونده ${i + 1}'];
      sheet.appendRow(_cells(['پرونده اختصاصی پویش جان‌فدا', r.name]));
      sheet.appendRow(_cells(['کد رهگیری نگارفرم', r.code]));
      sheet.appendRow(_cells(['شناسه دستگاه', r.id]));
      sheet.appendRow(_cells(['وضعیت', r.status == 'synced' ? 'ثبت‌شده در سایت' : 'آفلاین']));
      for (var j = 0; j < _fieldKeys.length; j++) {
        sheet.appendRow(_cells([_fieldLabels[j], r.data[_fieldKeys[j]] ?? '']));
      }
      sheet.appendRow(_cells(['رضایت ثبت اطلاعات و عکس', 'دریافت شده']));
      sheet.appendRow(_cells(['مسیر تصویر در بسته ZIP', photoName]));
      sheet.appendRow(_cells(['تاریخ ثبت', r.created]));
      try {
        final bytes = await store.readImage(r.photo);
        bundle.addFile(ArchiveFile(photoName, bytes.length, bytes));
      } catch (_) {
        sheet.appendRow(_cells(['هشدار تصویر', 'فایل تصویر در حافظه یافت نشد']));
      }
    }
    final output = book.encode();
    if (output == null) throw StateError('ساخت اکسل ناموفق بود.');
    final dir = await getTemporaryDirectory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final xlsx = File(p.join(dir.path, 'janfada_$now.xlsx'));
    await xlsx.writeAsBytes(output, flush: true);
    bundle.addFile(ArchiveFile('janfada_$now.xlsx', output.length, output));
    final zipBytes = ZipEncoder().encode(bundle);
    if (zipBytes == null) throw StateError('ایجاد بسته خروجی ناموفق بود.');
    final zip = File(p.join(dir.path, 'janfada_$now.zip'));
    await zip.writeAsBytes(zipBytes, flush: true);
    return ExportedFiles(xlsx: xlsx, zip: zip);
  }
}
