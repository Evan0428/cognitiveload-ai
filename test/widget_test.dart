import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('widget test harness renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('CognitiveLoad AI'),
        ),
      ),
    );

    expect(find.text('CognitiveLoad AI'), findsOneWidget);
  });
}
