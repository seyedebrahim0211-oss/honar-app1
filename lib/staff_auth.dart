import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Site-managed SMS OTP authorization for JanFada staff.
/// Never embed credentials in an Android package.
class StaffAuth {
  StaffAuth._();
  static final instance = StaffAuth._();
  static const _vault = FlutterSecureStorage();
  static const _base = 'https://honarmardomi.ir/wp-json/negarform/v1/janfada';
  static const _sessionKey = 'janfada_sms_session_v2';
  static const _mobileKey = 'janfada_staff_mobile_v2';
  static const _deviceKey = 'janfada_staff_device_uuid_v2';

  Future<String> deviceId() async {
    final current = await _vault.read(key: _deviceKey);
    if (current != null && current.isNotEmpty) return current;
    final id = const Uuid().v4();
    await _vault.write(key: _deviceKey, value: id);
    return id;
  }
  Future<String?> token() => _vault.read(key: _sessionKey);
  Future<String?> mobile() => _vault.read(key: _mobileKey);
  Future<Map<String,String>> sessionHeaders() async => {
    'X-Janfada-Session': await token() ?? '',
    'X-Janfada-Device-Id': await deviceId(),
  };

  static String asciiDigits(String input) => input.replaceAllMapped(
    RegExp(r'[۰-۹٠-٩]'), (m) {
      final c = m.group(0)!.codeUnitAt(0);
      return ((c >= 0x6f0 && c <= 0x6f9) ? c - 0x6f0 : c - 0x660).toString();
    },
  );

  Future<Map<String, dynamic>> _post(String path, Map<String,dynamic> body) async {
    final client = http.Client();
    try {
      final result = await client.post(Uri.parse('$_base/$path'),
        headers: const {'Content-Type':'application/json; charset=utf-8'},
        body: jsonEncode(body)).timeout(const Duration(seconds: 25));
      Map<String,dynamic> data;
      try { data = jsonDecode(result.body) as Map<String,dynamic>; }
      catch (_) { throw const StaffAuthException('پاسخ معتبر از سایت دریافت نشد.'); }
      if (result.statusCode < 200 || result.statusCode >= 300 || data['ok'] != true) {
        throw StaffAuthException((data['message'] ?? 'درخواست توسط سرور رد شد.').toString());
      }
      return data;
    } on StaffAuthException { rethrow; }
    catch (_) { throw const StaffAuthException('ارتباط با سایت برقرار نشد. اینترنت را بررسی کنید.'); }
    finally { client.close(); }
  }

  Future<void> requestCode(String value) async {
    final mobile = asciiDigits(value).trim();
    if (!RegExp(r'^09[0-9]{9}$').hasMatch(mobile)) {
      throw const StaffAuthException('شماره موبایل معتبر نیست.');
    }
    await _post('login', {'mobile': mobile, 'device_id': await deviceId()});
  }

  Future<void> verifyCode(String value, String valueCode) async {
    final mobile = asciiDigits(value).trim();
    final code = asciiDigits(valueCode).trim();
    final body = await _post('verify',
      {'mobile':mobile, 'code':code, 'device_id':await deviceId()});
    final session = (body['session_token'] ?? '').toString();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(session)) {
      throw const StaffAuthException('نشست امن از سرور دریافت نشد.');
    }
    await _vault.write(key: _sessionKey, value: session);
    await _vault.write(key: _mobileKey, value: mobile);
    await _vault.delete(key: 'janfada_operator_key_v1');
  }

  /// True=valid, false=revoked, null=offline/unknown.
  Future<bool?> validate() async {
    final session = await token();
    if (session == null || session.isEmpty) return false;
    final client = http.Client();
    try {
      final reply = await client.get(Uri.parse('$_base/me'),
        headers: await sessionHeaders()).timeout(const Duration(seconds: 14));
      if (reply.statusCode == 401 || reply.statusCode == 403) {
        await clearSession();
        return false;
      }
      if (reply.statusCode != 200) return null;
      final json = jsonDecode(reply.body) as Map<String,dynamic>;
      return json['ok'] == true;
    } catch (_) { return null; }
    finally { client.close(); }
  }

  Future<void> clearSession() async {
    await _vault.delete(key: _sessionKey);
    await _vault.delete(key: _mobileKey);
  }

  Future<void> logout() async {
    final t = await token();
    if (t != null && t.isNotEmpty) {
      final client = http.Client();
      try {
        await client.post(Uri.parse('$_base/logout'), headers: await sessionHeaders())
          .timeout(const Duration(seconds: 8));
      } catch (_) {} finally { client.close(); }
    }
    await clearSession();
  }
}

class StaffAuthException implements Exception {
  const StaffAuthException(this.message);
  final String message;
  @override String toString() => message;
}
