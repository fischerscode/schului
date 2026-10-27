import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';
import 'package:schului/src/learning_app_view.dart';

import 'sample_lesson.dart';

void main() {
  testWidgets('lesson activity opens the embedded exercise and keeps section', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          calls.add(call);
          if (call.method == 'state') {
            return {'connected': true, 'nodes': <Object>[]};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, null),
    );
    await tester.pumpWidget(
      SchoolApp(role: 'lesson', document: sampleDocument()),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Lückentext öffnen'));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((c) => c.method == 'learningApp').arguments,
      'https://example.org/exercise',
    );
    expect(find.text('Abschnitt 5 von 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('activity has visible close controls and Escape support', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningAppPanel(
          onClose: () => closed++,
          onRetry: () {},
          child: const Text('Eingebettete Aufgabe'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Eingebettete Aufgabe'), findsOneWidget);
    await tester.tap(find.byTooltip('Schließen'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 2);
  });

  testWidgets('load failure keeps retry and close accessible', (tester) async {
    var retried = 0, closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningAppPanel(
          error: 'Die Internetverbindung fehlt.',
          loading: true,
          onClose: () => closed++,
          onRetry: () => retried++,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Die Internetverbindung fehlt.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Erneut laden'));
    await tester.tap(find.byTooltip('Schließen'));
    expect(retried, 1);
    expect(closed, 1);
  });
}
