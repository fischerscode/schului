import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';
import 'package:schului/lessons/lesson_content.dart';

import 'sample_lesson.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'learner menu contains session actions without authoring or diagnostics',
    (tester) async {
      await tester.runAsync(() async {
        for (final (family, filename) in [
          ('Roboto', 'roboto-regular.ttf'),
          ('MaterialIcons', 'materialicons-regular.otf'),
        ]) {
          final loader = FontLoader(family)
            ..addFont(
              File(
                '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/$filename',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
        }
      });
      tester.view.physicalSize = const Size(450, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            bridge,
            (call) async => call.method == 'state' ? {'connected': true} : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(bridge, null),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: SchoolApp(role: 'lesson', document: sampleDocument()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lernumgebung'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      expect(find.text('Software starten / erneut verbinden'), findsOneWidget);
      expect(find.text('Lernumgebung beenden'), findsOneWidget);
      expect(find.text('Über dieses Programm'), findsOneWidget);
      expect(find.textContaining('Inspector'), findsNothing);
      expect(find.textContaining('exportieren'), findsNothing);
      expect(find.byTooltip('Zielsoftware'), findsNothing);
      final render = boundary.currentContext?.findRenderObject();
      if (render is! RenderRepaintBoundary) fail('Missing learner rendering');
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) fail('Missing menu PNG');
        await Directory('build/visual-review').create(recursive: true);
        await File('build/visual-review/learner-menu.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Abschnitt 2 von 7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

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

  testWidgets('students can reconnect after a startup failure', (tester) async {
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
    await tester.tap(find.text('Software starten / erneut verbinden'));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'start'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
