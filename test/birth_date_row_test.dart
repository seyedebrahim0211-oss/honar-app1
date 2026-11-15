import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jan_fada/main.dart';

void main() {
  testWidgets('Jalali birth year, month, day stay in the same row on small phones',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in <double>[320, 360, 430, 640]) {
      tester.view.physicalSize = Size(width, 1200);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fa'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: RegistrationForm(onSaved: () {})),
        ),
      ));
      await tester.pumpAndSettle();
      final year = find.text('سال تولد');
      final month = find.text('ماه تولد');
      final day = find.text('روز تولد');
      expect(year, findsOneWidget);
      expect(month, findsOneWidget);
      expect(day, findsOneWidget);
      final a = tester.getTopLeft(year);
      final b = tester.getTopLeft(month);
      final c = tester.getTopLeft(day);
      expect((a.dy - b.dy).abs(), lessThan(2), reason: 'Year/month mismatch at width $width');
      expect((b.dy - c.dy).abs(), lessThan(2), reason: 'Month/day mismatch at width $width');
      expect(a.dx, greaterThan(b.dx), reason: 'Persian RTL order at width $width');
      expect(b.dx, greaterThan(c.dx), reason: 'Persian RTL order at width $width');
      expect(tester.takeException(), isNull, reason: 'A render overflow occurred at width $width');
    }
  });
}
