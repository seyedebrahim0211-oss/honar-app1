import 'package:flutter_test/flutter_test.dart';
import 'package:jan_fada/data.dart';

void main() {
  test('All server field errors retain their Persian labels', () {
    expect(readableFormError({'message': 'خطای فرم', 'errors': {
      'father_name': 'الزامی است', 'birth_day': 'نامعتبر', 'notes': 'الزامی است'
    }}, 422), 'نام پدر: الزامی است\nروز تولد: نامعتبر\nتوضیحات: الزامی است');
  });
  test('Fallback retains HTTP status', () {
    expect(readableFormError({}, 503), 'خطای سرور (503)');
  });
  test('Invalid is not presented as offline pending', () {
    final r = Registrant(id: 'id', data: {}, photo: '', created: '', status: 'invalid');
    expect(r.statusLabel, 'نیازمند اصلاح فرم');
    expect(r.updated(status: 'error').statusLabel, 'ارسال ناموفق');
    expect(r.updated(status: 'synced').statusLabel, 'ثبت‌شده در سایت');
  });
}
