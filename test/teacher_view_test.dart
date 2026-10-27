import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/authoring/teacher_view.dart';
import 'package:schului/authoring/lesson_document.dart';
import 'package:schului/authoring/target_application.dart';
import 'package:schului/authoring/target_picker.dart';
import 'package:schului/src/schulzeug_theme.dart';

import 'sample_lesson.dart';

void main() {
  testWidgets(
    'teachers edit and reopen the button, window title and assignment for any URL',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: TeacherView(initialDocument: sampleDocument())),
      );
      await tester.tap(find.text('Webseite').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Buttontext'),
        'Informationen öffnen',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Fenstertitel'),
        'Unsere Recherche',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Arbeitsauftrag (optional)'),
        'Finde drei Beispiele.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'HTTPS-Adresse'),
        'https://example.org/info',
      );
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Informationen öffnen'));
      await tester.tap(find.text('Informationen öffnen'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Fenstertitel'))
            .controller
            ?.text,
        'Unsere Recherche',
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Arbeitsauftrag (optional)'),
            )
            .controller
            ?.text,
        'Finde drei Beispiele.',
      );
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('cancelling student export keeps the current unsaved lesson', (
    tester,
  ) async {
    const fileSelector = MethodChannel('plugins.flutter.io/file_selector');
    var folderRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fileSelector, (call) async {
          if (call.method == 'getDirectoryPath') {
            folderRequests++;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fileSelector, null),
    );
    await tester.pumpWidget(
      MaterialApp(home: TeacherView(initialDocument: sampleDocument())),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Schritttitel'),
      'Noch ungespeichert',
    );
    await tester.tap(find.byTooltip('Schülerpaket exportieren'));
    await tester.pumpAndSettle();
    expect(folderRequests, 1);
    expect(find.text('Ungespeichert'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Noch ungespeichert'),
      findsOneWidget,
    );
    expect(find.byType(MaterialBanner), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Schülerpaket exportieren',
            ),
          )
          .onPressed,
      isNotNull,
    );
  });
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          targetPickerChannel,
          (_) async => <Object?>[],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(targetPickerChannel, null),
    );
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
        child: MaterialApp(
          theme: schulzeugTheme(),
          home: TeacherView(
            initialDocument: LessonDocument(
              title: 'Text bearbeiten',
              steps: LessonDocument.empty().steps,
              application: WindowsApplication(
                name: 'Editor',
                executable: r'C:\Windows\notepad.exe',
              ),
            ),
          ),
        ),
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
    await tester.tap(find.text('Dein Arbeitsauftrag.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interaktiver Begriff'));
    await tester.pumpAndSettle();
    expect(find.text('Ziel in Anwendung auswählen'), findsOneWidget);
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) fail('Missing dialog PNG');
      await File('build/visual-review/target-picker.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zielsoftware'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) fail('Missing settings PNG');
      await File('build/visual-review/application-settings.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webseite').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Fenstertitel'),
      'Unsere Recherche',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Arbeitsauftrag (optional)'),
      'Lies die Seite und notiere zwei Stichpunkte.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'HTTPS-Adresse'),
      'https://example.org/info',
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) fail('Missing URL dialog PNG');
      await File('build/visual-review/url-editor.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
