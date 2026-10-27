import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';
import 'package:schului/lessons/lesson_content.dart';

import 'sample_lesson.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('temporary inspector switch returns to the same lesson section', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    var inspector = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          calls.add(call);
          if (call.method == 'inspector') {
            inspector = call.arguments as bool;
          }
          if (call.method == 'state') {
            return {
              'connected': true,
              'inspectorMode': inspector,
              'nodes': <Object>[],
            };
          }
          return null;
        });
    await tester.pumpWidget(
      SchoolApp(role: 'lesson', document: sampleDocument()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nächster Abschnitt'));
    await tester.pumpAndSettle();
    expect(find.text('Abschnitt 2 von 7'), findsOneWidget);
    await tester.tap(find.byTooltip('Lernumgebung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pfade entdecken (Inspector)'));
    await tester.pumpAndSettle();
    expect(find.text('Beispiel-Editor · Accessibility-Baum'), findsOneWidget);
    expect(find.text('Pfad anzeigen / laden'), findsOneWidget);
    expect(inspector, isTrue);
    await tester.tap(find.text('Zurück zum Unterricht'));
    await tester.pumpAndSettle();
    expect(inspector, isFalse);
    expect(find.text('Abschnitt 2 von 7'), findsOneWidget);
    expect(
      calls.lastWhere((call) => call.method == 'selectNode').arguments,
      '',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sections fill viewport, scroll continuously and publish hover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          calls.add(call);
          if (call.method == 'state') {
            return {'connected': true, 'nodes': <Object>[]};
          }
          return null;
        });
    await tester.pumpWidget(
      SchoolApp(role: 'lesson', document: sampleDocument()),
    );
    await tester.pump();
    final viewport = find.descendant(
      of: find.byType(LessonContent),
      matching: find.byType(SingleChildScrollView),
    );
    final first = tester.getTopLeft(find.text('Willkommen')).dy;
    final second = tester.getTopLeft(find.text('Dein erster Text')).dy;
    expect(
      second - first,
      greaterThanOrEqualTo(tester.getSize(viewport).height),
    );
    expect(
      tester.getCenter(find.textContaining('Lerne den Editor')).dy,
      greaterThan(first + 100),
    );
    await tester.tap(find.byTooltip('Nächster Abschnitt'));
    await tester.pumpAndSettle();
    expect(find.text('Abschnitt 2 von 7'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Speichern').first));
    await tester.pump();
    expect(
      calls.lastWhere((call) => call.method == 'hover').arguments,
      saveTarget.toJson(),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(
      calls.any((c) => c.method == 'hover' && c.arguments == null),
      isTrue,
    );
    await mouse.removePointer();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Abschnitt 7 von 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long content remains scrollable in a short narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonContent(
            lessons: sampleSteps,
            onHover: (_) {},
            onSection: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Abschnitt 7 von 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connection diagnostics remain available before connecting', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          calls.add(call);
          if (call.method == 'state') {
            return {
              'connected': false,
              'startupError': 'Testfehler beim Start',
            };
          }
          if (call.method == 'connectionDiagnostics') {
            return r'C:\Temp\connection-diagnostics.txt';
          }
          return null;
        });
    await tester.pumpWidget(
      SchoolApp(role: 'lesson', document: sampleDocument()),
    );
    await tester.pump();
    expect(find.text('Zielsoftware verbinden …'), findsOneWidget);
    expect(find.text('Testfehler beim Start'), findsOneWidget);
    await tester.tap(find.byTooltip('Lernumgebung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verbindungsdiagnose exportieren'));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'connectionDiagnostics'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
