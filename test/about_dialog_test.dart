import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:schului/main.dart';
import 'package:schului/src/about_dialog.dart';
import 'package:schului/src/schulzeug_theme.dart';

import 'sample_lesson.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <MethodCall>[];
  late AssetBundle assets;
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'schului',
      packageName: 'de.schului',
      version: '2.7.3',
      buildNumber: '42',
      buildSignature: '',
    );
    assets = _LegalAssets({
      'assets/legal/impressum.txt': await rootBundle.loadString(
        'assets/legal/impressum.txt',
      ),
      'assets/legal/datenschutz.txt': await rootBundle.loadString(
        'assets/legal/datenschutz.txt',
      ),
    });
    launches.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          launches.add(call);
          return false;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          bridge,
          (call) async => call.method == 'state' ? {'connected': true} : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null);
  });

  testWidgets(
    'teacher and pupil can read the build version and offline legal documents',
    (tester) async {
      await tester.pumpWidget(
        DefaultAssetBundle(bundle: assets, child: const SchoolApp()),
      );
      await tester.tap(find.byTooltip('Über dieses Programm'));
      await tester.pumpAndSettle();
      expect(find.text('Version 2.7.3 (Build 42)'), findsOneWidget);
      expect(find.text('GitHub-Repository'), findsOneWidget);
      expect(find.text('Lizenzen'), findsOneWidget);
      await tester.tap(find.text('Impressum'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data?.contains('Graefenhainweg 7A') ?? false),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Schließen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Datenschutzerklärung'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data?.contains('flutter_webview_windows') ?? false),
        ),
        findsOneWidget,
      );
      expect(
        launches,
        isEmpty,
        reason: 'Opening About or legal text must not open remote content.',
      );
      await tester.tap(find.text('Schließen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: assets,
          child: SchoolApp(role: 'lesson', document: sampleDocument()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lernumgebung'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Über dieses Programm'));
      await tester.pumpAndSettle();
      expect(find.text('Version 2.7.3 (Build 42)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'GitHub opens only on demand and offers its address if the browser fails',
    (tester) async {
      await tester.pumpWidget(
        DefaultAssetBundle(bundle: assets, child: const SchoolApp()),
      );
      await tester.tap(find.byTooltip('Über dieses Programm'));
      await tester.pumpAndSettle();
      expect(launches, isEmpty);
      await tester.tap(find.text('GitHub-Repository'));
      await tester.pumpAndSettle();
      final request =
          launches.singleWhere((call) => call.method == 'launch').arguments
              as Map;
      expect(request['url'], repositoryUrl);
      expect(request['useWebView'], isFalse);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data?.contains(repositoryUrl) ?? false),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('about and legal text fit a narrow screen with doubled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: assets,
        child: MaterialApp(
          theme: schulzeugTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child ?? const SizedBox(),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSchuluiAboutDialog(context),
                child: const Text('Info'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Datenschutzerklärung'));
    await tester.tap(find.text('Datenschutzerklärung'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Schließen').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('render about and imprint for visual inspection', (tester) async {
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final (family, name) in [
        ('Roboto', 'roboto-regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final loader = FontLoader(family)
          ..addFont(
            File('.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/$name')
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: DefaultAssetBundle(bundle: assets, child: const SchoolApp()),
      ),
    );
    await tester.tap(find.byTooltip('Über dieses Programm'));
    await tester.pumpAndSettle();
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) fail('Missing About rendering');
    Future<void> capture(String name) => tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) fail('Missing legal PNG');
      await Directory('build/visual-review').create(recursive: true);
      await File('build/visual-review/$name.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await capture('about');
    await tester.tap(find.text('Impressum'));
    await tester.pumpAndSettle();
    await capture('impressum');
  });
}

class _LegalAssets extends CachingAssetBundle {
  _LegalAssets(this.documents);
  final Map<String, String> documents;
  @override
  Future<ByteData> load(String key) async {
    final document = documents[key];
    if (document == null) throw FlutterError('Unexpected test asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(document)));
  }
}
