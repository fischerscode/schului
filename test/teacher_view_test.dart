import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/authoring/teacher_view.dart';
import 'package:schului/src/schulzeug_theme.dart';

void main() {
  testWidgets('teachers add, name, reorder and preserve steps across preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: schulzeugTheme(), home: const TeacherView()),
    );
    await tester.tap(find.byTooltip('Schritt hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Schritttitel'),
      'Eigene Aufgabe',
    );
    await tester.tap(find.byTooltip('Schritt nach oben'));
    await tester.pumpAndSettle();
    expect(find.text('Ungespeichert'), findsOneWidget);
    await tester.tap(find.byTooltip('Lernansicht'));
    await tester.pumpAndSettle();
    expect(find.text('Eigene Aufgabe'), findsWidgets);
    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Eigene Aufgabe'), findsOneWidget);
    await tester.tap(find.byTooltip('Neu (Strg+N)'));
    await tester.pumpAndSettle();
    expect(find.text('Änderungen speichern?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Eigene Aufgabe'), findsOneWidget);
  });

  testWidgets('editor remains usable at narrow width with doubled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: schulzeugTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const TeacherView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Speichern (Strg+S)'), findsOneWidget);
  });

  testWidgets('render teacher workspace for visual inspection', (tester) async {
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
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(theme: schulzeugTheme(), home: const TeacherView()),
      ),
    );
    await tester.pumpAndSettle();
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) fail('Missing workspace rendering');
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) fail('Missing PNG');
      await Directory('build/visual-review').create(recursive: true);
      await File('build/visual-review/teacher.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
