import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';
import 'package:schului/lessons/lesson_model.dart';
import 'package:schului/src/web_page_view.dart';

import 'sample_lesson.dart';

void main() {
  testWidgets(
    'page texts follow native state when two links use the same URL',
    (tester) async {
      var title = 'Erste Recherche';
      var instructions = 'Lies den Text.';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            bridge,
            (_) async => {
              'webPageVisible': false,
              'webPageUrl': 'https://example.org/info',
              'webPageTitle': title,
              'webPageInstructions': instructions,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(bridge, null),
      );
      await tester.pumpWidget(const SchoolApp(role: 'webPage'));
      await tester.pump();
      expect(find.text('Erste Recherche'), findsOneWidget);
      title = 'Zweite Recherche';
      instructions = 'Vergleiche die Beispiele.';
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Zweite Recherche'), findsOneWidget);
      expect(find.text('Vergleiche die Beispiele.'), findsOneWidget);
      expect(find.text('Erste Recherche'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
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
      calls.lastWhere((c) => c.method == 'webPage').arguments,
      (sampleSteps[4].content.single as LessonActivity).toWebPageRequest(),
    );
    expect(find.text('5 / 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('activity has visible close controls and Escape support', (
    tester,
  ) async {
    var closed = 0;
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
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          home: WebPagePanel(
            title: 'Informationen zur Recherche',
            instructions: 'Lies die Seite und notiere zwei Stichpunkte.',
            onClose: () => closed++,
            onRetry: () {},
            child: const Text('Eingebettete Aufgabe'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Eingebettete Aufgabe'), findsOneWidget);
    expect(find.text('Informationen zur Recherche'), findsOneWidget);
    expect(
      find.text('Lies die Seite und notiere zwei Stichpunkte.'),
      findsOneWidget,
    );
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) fail('Missing URL window rendering');
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) fail('Missing URL window PNG');
      await Directory('build/visual-review').create(recursive: true);
      await File('build/visual-review/url-window.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.byTooltip('Schließen'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 2);
  });

  testWidgets('load failure keeps retry and close accessible', (tester) async {
    var retried = 0, closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WebPagePanel(
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

  testWidgets('long instructions stay scrollable at doubled text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: WebPagePanel(
            title: 'Unsere gemeinsame Recherche',
            instructions: 'Lies den Text. ' * 200,
            onClose: () {},
            onRetry: () {},
            child: const Text('Webseite'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byTooltip('Schließen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
