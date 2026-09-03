import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:onion_grading_app/main.dart';

void main() {
  testWidgets('App boots straight onto the camera screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OnionGradingApp());
    await tester.pump();

    expect(find.text('🧅 Onion Quality AI'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsWidgets);
  });
}
