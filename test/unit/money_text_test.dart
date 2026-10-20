import 'package:dargres/src/converters.dart';
import 'package:test/test.dart';

void main() {
  test('money text in several locales becomes the exact amount', () {
    const cases = {
      r'$12.34': '12.34',
      r'R$ 12,34': '12.34',
      r'R$ 1.234.567,89': '1234567.89',
      r'$1,234,567.89': '1234567.89',
      r'-$0.05': '-0.05',
      r'($0.05)': '-0.05',
      r'-R$ 12,34': '-12.34',
      r'R$ 0,00': '0.00',
      r'$0.00': '0.00',
      '12,34 €': '12.34',
      '-12,30 €': '-12.30',
      r'$92,233,720,368,547,758.07': '92233720368547758.07',
      r'-$92,233,720,368,547,758.08': '-92233720368547758.08',
    };
    cases.forEach((text, amount) {
      expect(TypeConverter.parseMoneyText(text), amount, reason: text);
    });
  });
}
