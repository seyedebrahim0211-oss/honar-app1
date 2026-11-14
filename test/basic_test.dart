import 'package:flutter_test/flutter_test.dart';
import 'package:jan_fada/data.dart';

void main() {
  test('campaign uses the verified Negarform id and secure endpoint', () {
    expect(formId, 8);
    expect(submitUrl.startsWith('https://honarmardomi.ir/wp-json/negarform/v1/submit/'), true);
    expect(consentValue, isNotEmpty);
  });
}
