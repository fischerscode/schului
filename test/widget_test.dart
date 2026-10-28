import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';
import 'package:schului/lessons/lesson_content.dart';
import 'package:schului/lessons/lesson_model.dart';
import 'package:schului/src/schulzeug_theme.dart';

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
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: SchoolApp(role: 'lesson', document: sampleDocument()),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'learner');
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'learner-active');
      await tester.tap(find.byTooltip('Lernumgebung'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      expect(find.text('Erneut verbinden'), findsOneWidget);
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
      expect(find.text('2 / 7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    },
  );

  testWidgets(
    'keyboard highlights targets and tips follow the reading position',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
            calls.add(call);
            return call.method == 'state' ? {'connected': true} : null;
          });
      await tester.pumpWidget(
        SchoolApp(role: 'lesson', document: sampleDocument()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tipp anzeigen'));
      await tester.pump();
      expect(
        calls.any((c) => c.method == 'hint' && c.arguments == true),
        isTrue,
      );
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
      final link = find.text('Speichern').first;
      Focus.of(tester.element(link)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        calls.lastWhere((c) => c.method == 'hover').arguments,
        saveTarget.toJson(),
      );
      expect(find.bySemanticsLabel('Abschnitt 2 von 7'), findsOneWidget);
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tipp anzeigen'), findsNothing);
      expect(calls.lastWhere((c) => c.method == 'step').arguments, 2);
      final hintBoundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: hintBoundary,
          child: SchoolApp(role: 'hint', document: sampleDocument()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ein Tipp'), findsOneWidget);
      await capture(tester, hintBoundary, 'learner-hint');
      await tester.tap(find.byTooltip('Hinweis schließen'));
      await tester.pump();
      expect(calls.lastWhere((c) => c.method == 'hint').arguments, false);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets(
    'learner recovery and navigation fit at 200 percent in a narrow window',
    (tester) async {
      tester.view.physicalSize = const Size(320, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            bridge,
            (call) async => call.method == 'state'
                ? {
                    'connected': false,
                    'startupError': 'Die Software ist nicht erreichbar.',
                  }
                : null,
          );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: schulzeugTheme(),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: SessionView(
              role: 'lesson',
              title: 'Text bearbeiten',
              lessons: sampleSteps,
              application: sampleApplication,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'learner-narrow');
      await tester.tap(find.byTooltip('Nächster Abschnitt'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tasks preserve hover targets and previous/next navigation', (
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
    expect(second - first, lessThan(tester.getSize(viewport).height / 2));
    expect(
      tester.getCenter(find.textContaining('Lerne den Editor')).dy,
      lessThan(first + 90),
    );
    await tester.tap(find.byTooltip('Nächster Abschnitt'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 7'), findsOneWidget);
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
    expect(find.text('7 / 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'previews activate explicitly by click or keyboard, never by scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(400, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = <int>[];
      final hovered = <LessonLink?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: schulzeugTheme(),
          home: Scaffold(
            body: LessonContent(
              lessons: sampleSteps,
              onHover: hovered.add,
              onSection: selected.add,
            ),
          ),
        ),
      );
      expect(find.text('Aktuelle Aufgabe'), findsNothing);
      expect(find.text('01'), findsNothing);
      expect(find.text('02'), findsNothing);
      expect(find.text('Speichern'), findsNothing);
      expect(find.text('Lies deinen Text.'), findsNothing);
      expect(find.text('Lückentext öffnen'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(find.text('1 / 7'), findsOneWidget);
      await tester.ensureVisible(find.text('Dein erster Text'));
      await tester.tap(find.text('Dein erster Text'));
      await tester.pumpAndSettle();
      expect(selected, [1]);
      expect(find.text('Speichern'), findsOneWidget);
      expect(find.text('Aktuelle Aufgabe'), findsNothing);
      expect(find.text('01'), findsNothing);
      expect(find.text('02'), findsNothing);
      await tester.ensureVisible(find.text('Abschluss'));
      Focus.of(tester.element(find.text('Abschluss'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, [1, 6]);
      expect(find.text('Speichern'), findsNothing);
      expect(hovered.whereType<LessonLink>(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'activation centers a fitting task and aligns long tasks at the top',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final steps = [...sampleSteps];
      steps[4] = LessonStep('Lange Aufgabe', [
        LessonParagraph([
          LessonText('Lies diesen Text und arbeite in der Software. ' * 100),
        ]),
        const LessonParagraph([LessonText('Ende der Aufgabe')]),
      ], '');
      final selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: schulzeugTheme(),
          home: Scaffold(
            body: LessonContent(
              lessons: steps,
              onHover: (_) {},
              onSection: selected.add,
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Prüfen'));
      await tester.tap(find.text('Prüfen'));
      await tester.pumpAndSettle();
      Finder task(String title) => find
          .ancestor(of: find.text(title), matching: find.byType(Container))
          .first;
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final short = tester.getRect(task('Prüfen'));
      expect(short.height, lessThan(viewport.height));
      expect(short.center.dy, closeTo(viewport.center.dy, 2));
      await tester.ensureVisible(find.text('Lange Aufgabe'));
      await tester.tap(find.text('Lange Aufgabe'));
      await tester.pumpAndSettle();
      final long = tester.getRect(task('Lange Aufgabe'));
      expect(long.height, greaterThan(viewport.height));
      expect(long.top, closeTo(viewport.top, 2));
      await tester.ensureVisible(find.text('Ende der Aufgabe'));
      await tester.pumpAndSettle();
      expect(selected, [3, 4]);
      expect(find.text('5 / 7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('task navigation remains usable in a short narrow window', (
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
    expect(find.text('7 / 7'), findsOneWidget);
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
    expect(find.text('Fenster auswählen'), findsOneWidget);
    expect(find.text('Testfehler beim Start'), findsOneWidget);
    await tester.tap(find.text('Software starten'));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'start'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final render = boundary.currentContext?.findRenderObject();
  if (render is! RenderRepaintBoundary) fail('Missing learner rendering');
  await tester.runAsync(() async {
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) fail('Missing learner PNG');
    await Directory('build/visual-review').create(recursive: true);
    await File('build/visual-review/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}
