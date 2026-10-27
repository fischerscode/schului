import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lessons/lesson_content.dart';
import 'lessons/lesson_model.dart';
import 'src/windows_bridge.dart';
import 'src/inspector_view.dart';
import 'src/web_page_view.dart';
import 'authoring/lesson_document.dart';
import 'authoring/lesson_files.dart';
import 'authoring/teacher_view.dart';
import 'src/schulzeug_theme.dart';
import 'src/about_dialog.dart';
import 'authoring/target_application.dart';
import 'authoring/application_settings.dart';
export 'src/windows_bridge.dart' show bridge;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final fileIndex = args.indexOf('--lesson-file');
  try {
    if (fileIndex == args.length - 1 && fileIndex >= 0) {
      throw const FormatException('Dateipfad nach --lesson-file angeben.');
    }
    final document = fileIndex < 0
        ? null
        : await readLessonFile(args[fileIndex + 1]);
    final role = args.isEmpty ? 'teacher' : args.first;
    if (role != 'teacher' && role != 'webPage' && document == null) {
      throw const FormatException('Eine Unterrichtseinheit auswählen.');
    }
    if (role == 'lesson' || role == 'inspector') {
      final application =
          document?.application ?? const UnconfiguredApplication();
      if (application is UnconfiguredApplication) {
        throw const FormatException(
          'Zuerst im Editor eine Zielsoftware auswählen.',
        );
      }
      await bridge.invokeMethod<void>(
        'configureApplication',
        application.toJson(),
      );
    }
    runApp(
      SchoolApp(
        role: args.isEmpty ? 'teacher' : args.first,
        document: document,
      ),
    );
  } on Object catch (error) {
    runApp(
      MaterialApp(
        theme: schulzeugTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Lernumgebung kann nicht geöffnet werden: $error'),
            ),
          ),
        ),
      ),
    );
  }
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key, this.role = 'teacher', this.document});
  final String role;
  final LessonDocument? document;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: schulzeugTheme(),
    home: switch ((role, document)) {
      ('inspector', final lesson) => InspectorView(
        applicationName: lesson?.application.name ?? 'Zielsoftware',
      ),
      ('webPage', _) => const WebPageView(),
      ('teacher', _) => const TeacherView(),
      (_, final lesson?) => SessionView(
        role: role,
        lessons: lesson.steps,
        application: lesson.application,
      ),
      _ => const Scaffold(
        body: Center(child: Text('Eine Unterrichtseinheit auswählen.')),
      ),
    },
  );
}

class SessionView extends StatefulWidget {
  const SessionView({
    super.key,
    required this.role,
    required this.lessons,
    required this.application,
  });
  final String role;
  final List<LessonStep> lessons;
  final TargetApplication application;
  @override
  State<SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<SessionView> {
  Timer? timer;
  Map<String, dynamic> state = {};
  String? error;
  bool busy = false;
  int get index =>
      (state['step'] as int? ?? 0).clamp(0, widget.lessons.length - 1);
  bool get connected => state['connected'] == true;
  AccessibilityNode? get hoverTarget {
    final raw = state['hoverGeometry'];
    final generation = state['hoverGeneration'];
    if (state['hoverTarget'] is! Map ||
        raw is! Map ||
        generation is! int ||
        state['hoverGeometryGeneration'] != generation) {
      return null;
    }
    final geometry = AccessibilityNode.fromMap(Map<String, dynamic>.from(raw));
    return geometry.canHighlight ? geometry : null;
  }

  void hover(LessonLink? link) {
    unawaited(command('hover', link?.target?.toJson()));
  }

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    timer = Timer.periodic(
      Duration(milliseconds: widget.role == 'overlay' ? 100 : 500),
      (_) => refresh(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> command(String name, [Object? args]) async {
    try {
      await bridge.invokeMethod<Object?>(name, args);
      if (mounted) {
        setState(() {
          error = null;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } on MissingPluginException {
      if (mounted) {
        setState(() => error = 'Die Windows-Anbindung ist nicht verfügbar.');
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    try {
      final value = await bridge.invokeMapMethod<String, dynamic>('state');
      if (!mounted || value == null) return;
      setState(() => state = value);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on MissingPluginException {
      /* Widget previews have no Windows runner. */
    } finally {
      busy = false;
    }
  }

  Future<void> selectWindow() async {
    try {
      final id = await chooseSessionWindow(context);
      if (id != null && mounted) await command('selectApplicationWindow', id);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } on MissingPluginException {
      if (mounted) setState(() => error = 'Die Windows-Anbindung fehlt.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role == 'overlay') return overlay(context);
    if (widget.role == 'hint') return hint(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LessonContent(
                lessons: widget.lessons,
                onHint: () => command('hint', true),
                onHover: hover,
                onSection: (section) => command('step', section),
              ),
            ),
            if (error != null ||
                (state['startupError'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  error ?? state['startupError'] as String,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      connected
                          ? '${widget.application.name} ist verbunden.'
                          : 'Zielsoftware verbinden …',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF52627C),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Lernumgebung',
                    onSelected: (action) => switch (action) {
                      'about' => showSchuluiAboutDialog(context),
                      _ => command(action),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'start',
                        child: Text('Software starten / erneut verbinden'),
                      ),
                      PopupMenuItem(
                        value: 'exit',
                        child: Text('Lernumgebung beenden'),
                      ),
                      PopupMenuItem(
                        value: 'about',
                        child: Text('Über dieses Programm'),
                      ),
                    ],
                  ),
                  if (!connected && widget.application is WindowsApplication)
                    IconButton(
                      tooltip: 'Fenster auswählen',
                      onPressed: selectWindow,
                      icon: const Icon(Icons.window_outlined),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget overlay(BuildContext context) {
    if (state['inspectorMode'] == true) return InspectorOverlay(state: state);
    final target = hoverTarget;
    final scale = MediaQuery.devicePixelRatioOf(context);
    final originX = (state['targetLeft'] as num? ?? 0).toDouble();
    final originY = (state['targetTop'] as num? ?? 0).toDouble();
    return ColoredBox(
      color: overlayKey,
      child: Stack(
        children: [
          if (target != null && target.canHighlight)
            Positioned(
              left: (target.bounds.left - originX) / scale - 4,
              top: (target.bounds.top - originY) / scale - 4,
              width: target.bounds.width / scale + 8,
              height: target.bounds.height / scale + 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFFFAB00), width: 4),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget hint(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF8E1),
    body: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ein Tipp für dich',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => command('hint', false),
                icon: const Icon(Icons.close),
                tooltip: 'Hinweis schließen',
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                widget.lessons[index].hint,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
