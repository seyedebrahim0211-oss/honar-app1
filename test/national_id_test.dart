import 'package:flutter_test/flutter_test.dart';
import 'package:jan_fada/data.dart';

void main() {
  test('Persian and Arabic numerals preserve leading zeros', () {
    expect(normalizeNationalId('۰۰۱۲۳۴۵۶۷۹'), '0012345679');
    expect(normalizeNationalId('٠٠١٢٣٤٥٦٧٩'), '0012345679');
  });

  test('Pasted separators and directional marks are normalized', () {
    expect(normalizeNationalId(' ۰۰۱-\u200F۲۳۴۵۶۷۹ '), '0012345679');
    expect(nationalIdError(' ۰۰۱-\u200F۲۳۴۵۶۷۹ '), isNull);
  });

  test('Invalid checksums, missing digits, repeated digits and letters are rejected', () {
    expect(nationalIdError('0012345678'), isNotNull);
    expect(nationalIdError('012345679'), isNotNull);
    expect(nationalIdError('0000000000'), isNotNull);
    expect(nationalIdError('A0012345679'), isNotNull);
    expect(nationalIdError(''), isNotNull);
  });
}
