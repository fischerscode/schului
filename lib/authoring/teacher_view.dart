import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lessons/lesson_content.dart';
import '../lessons/lesson_model.dart';
import '../src/windows_bridge.dart';
import 'lesson_document.dart';
import 'lesson_files.dart';
import 'span_dialog.dart';
import 'target_application.dart';
import 'application_settings.dart';

class TeacherView extends StatefulWidget {
  const TeacherView({super.key, this.initialDocument});
  final LessonDocument? initialDocument;
  @override
  State<TeacherView> createState() => _TeacherViewState();
}

class _TeacherViewState extends State<TeacherView> {
  late LessonDocument document =
      widget.initialDocument ?? LessonDocument.empty();
  int selected = 0;
  int revision = 0;
  String? path, error;
  bool dirty = false, busy = false, preview = false, running = false;
  late final title = TextEditingController(text: document.title);
  late final stepTitle = TextEditingController(text: step.title);
  late final hint = TextEditingController(text: step.hint);
  LessonStep get step => document.steps[selected];

  @override
  void initState() {
    super.initState();
    bridge.setMethodCallHandler((call) async {
      if (call.method == 'requestClose' && await canDiscard() && mounted) {
        await bridge.invokeMethod<void>('closeEditor');
      }
    });
  }

  @override
  void dispose() {
    bridge.setMethodCallHandler(null);
    title.dispose();
    stepTitle.dispose();
    hint.dispose();
    super.dispose();
  }

  void loadFields() {
    stepTitle.text = step.title;
    hint.text = step.hint;
  }

  void update({List<LessonStep>? steps, String? name}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      document = LessonDocument(
        title: name ?? document.title,
        steps: steps ?? document.steps,
        application: document.application,
      );
      dirty = true;
      revision++;
      error = null;
    });
  }

  void updateStep({String? name, String? help, List<LessonBlock>? content}) {
    final steps = [...document.steps];
    steps[selected] = LessonStep(
      name ?? step.title,
      List.unmodifiable(content ?? step.content),
      help ?? step.hint,
    );
    update(steps: steps);
  }

  Future<bool> canDiscard() async {
    if (!dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Änderungen speichern?'),
        content: const Text(
          'Die Lernumgebung enthält ungespeicherte Änderungen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Verwerfen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (choice == 'discard') return true;
    if (choice == 'save') return save();
    return false;
  }

  Future<void> replace(LessonDocument next, {String? filePath}) async {
    setState(() {
      document = next;
      selected = 0;
      dirty = false;
      path = filePath;
      error = null;
      preview = false;
      title.text = next.title;
      loadFields();
    });
  }

  Future<void> create() async {
    if (await canDiscard() && mounted) await replace(LessonDocument.empty());
  }

  Future<void> configureApplication() async {
    final next = await editApplication(context, document.application);
    if (next == null || !mounted) return;
    final previous = document.application;
    final sameSoftware =
        previous is WindowsApplication &&
        next is WindowsApplication &&
        previous.executable.toLowerCase() == next.executable.toLowerCase();
    final hasTargets = document.steps.any(
      (step) => step.links.any((link) => link.target != null),
    );
    if (!sameSoftware && hasTargets) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Zielsoftware wechseln?'),
          content: const Text(
            'Vorhandene Zielverknüpfungen werden entfernt. Texte und Tipps bleiben erhalten.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Wechseln'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    LessonParagraph clean(LessonParagraph p) => LessonParagraph([
      for (final span in p.spans)
        switch (span) {
          LessonText() => span,
          LessonLink() => LessonLink(span.text, help: span.help),
        },
    ]);
    final steps = sameSoftware
        ? document.steps
        : [
            for (final step in document.steps)
              LessonStep(step.title, [
                for (final block in step.content)
                  switch (block) {
                    LessonParagraph() => clean(block),
                    LessonBulletList() => LessonBulletList([
                      for (final p in block.items) clean(p),
                    ]),
                    LessonActivity() => block,
                  },
              ], step.hint),
          ];
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      document = LessonDocument(
        title: document.title,
        steps: steps,
        application: next,
      );
      dirty = true;
      revision++;
    });
  }

  Future<void> open() async {
    if (!await canDiscard() || !mounted) return;
    await guard(() async {
      final file = await openFile(acceptedTypeGroups: [lessonType]);
      if (file == null) return;
      final next = await readLessonFile(file.path);
      if (mounted) await replace(next, filePath: file.path);
    });
  }

  bool validTitles() {
    if (title.text.trim().isEmpty ||
        document.steps.any((s) => s.title.trim().isEmpty)) {
      setState(
        () => error = 'Titel für die Lernumgebung und jeden Schritt eingeben.',
      );
      return false;
    }
    return true;
  }

  Future<bool> save({bool saveAs = false}) async {
    if (!validTitles()) return false;
    var saved = false;
    await guard(() async {
      final snapshot = document;
      final savedRevision = revision;
      var destination = saveAs ? null : path;
      if (destination == null) {
        final location = await getSaveLocation(
          suggestedName: 'lernumgebung.schului',
          acceptedTypeGroups: [lessonType],
        );
        if (location == null) return;
        destination = location.path;
      }
      await writeLessonFile(destination, snapshot);
      if (!mounted) return;
      setState(() {
        path = destination;
        dirty = revision != savedRevision;
      });
      saved = !dirty;
    });
    return saved;
  }

  Future<void> guard(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() => error = 'Dateizugriff fehlgeschlagen: ${e.message}');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> run({bool inspector = false}) async {
    if (!validTitles() || running) return;
    if (document.application is UnconfiguredApplication) {
      await configureApplication();
      if (!mounted || document.application is UnconfiguredApplication) return;
    }
    setState(() {
      running = true;
      error = null;
    });
    try {
      await launchLesson(document, inspector: inspector);
    } on ProcessException catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Lernumgebung konnte nicht gestartet werden: ${e.message}',
        );
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(
          () =>
              error = 'Vorschau konnte nicht gespeichert werden: ${e.message}',
        );
      }
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  void addStep() {
    final steps = [
      ...document.steps,
      LessonStep('Schritt ${document.steps.length + 1}', const [
        LessonParagraph([LessonText('Dein Arbeitsauftrag.')]),
      ], ''),
    ];
    update(steps: steps);
    setState(() {
      selected = steps.length - 1;
      loadFields();
    });
  }

  void moveStep(int direction) {
    final next = selected + direction;
    if (next < 0 || next >= document.steps.length) return;
    final steps = [...document.steps];
    steps.insert(next, steps.removeAt(selected));
    update(steps: steps);
    setState(() {
      selected = next;
      loadFields();
    });
  }

  Future<void> deleteStep() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schritt löschen?'),
        content: Text(step.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final steps = [...document.steps]..removeAt(selected);
    selected = selected.clamp(0, steps.length - 1);
    update(steps: steps);
    loadFields();
  }

  Future<void> changeSpan(int blockIndex, int spanIndex, {int? bullet}) async {
    final block = step.content[blockIndex];
    final paragraph = switch (block) {
      LessonParagraph() => block,
      LessonBulletList() => block.items[bullet ?? 0],
      LessonActivity() => throw StateError('Activity has no spans'),
    };
    final result = await editSpan(
      context,
      paragraph.spans[spanIndex],
      application: document.application,
    );
    if (result == null || !mounted) return;
    final spans = [...paragraph.spans];
    spans[spanIndex] = result;
    setParagraph(blockIndex, LessonParagraph(spans), bullet: bullet);
  }

  void setParagraph(int blockIndex, LessonParagraph paragraph, {int? bullet}) {
    final blocks = [...step.content];
    final block = blocks[blockIndex];
    if (block is LessonBulletList) {
      final items = [...block.items];
      items[bullet ?? 0] = paragraph;
      blocks[blockIndex] = LessonBulletList(items);
    } else {
      blocks[blockIndex] = paragraph;
    }
    updateStep(content: blocks);
  }

  Future<void> addSpan(
    int blockIndex,
    LessonParagraph paragraph, {
    int? bullet,
  }) async {
    final result = await editSpan(
      context,
      const LessonText('Text'),
      application: document.application,
    );
    if (result != null && mounted) {
      setParagraph(
        blockIndex,
        LessonParagraph([...paragraph.spans, result]),
        bullet: bullet,
      );
    }
  }

  Future<void> activity({int? index}) async {
    final existing = index == null ? null : step.content[index];
    final label = TextEditingController(
      text: existing is LessonActivity ? existing.label : 'Übung öffnen',
    );
    final url = TextEditingController(
      text: existing is LessonActivity ? existing.url : '',
    );
    String? validation;
    final result = await showDialog<LessonActivity>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Online-Übung'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Beschriftung',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: url,
                    decoration: InputDecoration(
                      labelText: 'HTTPS-Adresse',
                      errorText: validation,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  if (label.text.trim().isEmpty) {
                    throw const FormatException('Beschriftung eingeben.');
                  }
                  Navigator.pop(
                    context,
                    LessonActivity(
                      label.text,
                      url: validateActivityUrl(url.text),
                    ),
                  );
                } on FormatException catch (e) {
                  setDialogState(() => validation = e.message);
                }
              },
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      ),
    );
    // Dialog route transitions can still refer to the controllers until disposal.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    label.dispose();
    url.dispose();
    if (result == null || !mounted) return;
    final blocks = [...step.content];
    if (index == null) {
      blocks.add(result);
    } else {
      blocks[index] = result;
    }
    updateStep(content: blocks);
  }

  Widget action(IconData icon, String label, VoidCallback? onPressed) =>
      IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon));

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
        if (!busy) unawaited(save());
      },
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
        if (!busy) unawaited(open());
      },
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
        if (!busy) unawaited(create());
      },
    },
    child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'schului',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  action(
                    Icons.note_add_outlined,
                    'Neu (Strg+N)',
                    busy ? null : create,
                  ),
                  action(
                    Icons.folder_open_outlined,
                    'Öffnen (Strg+O)',
                    busy ? null : open,
                  ),
                  action(
                    Icons.save_outlined,
                    'Speichern (Strg+S)',
                    busy ? null : () => save(),
                  ),
                  action(
                    Icons.save_as_outlined,
                    'Speichern unter',
                    busy ? null : () => save(saveAs: true),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    isSelected: preview,
                    tooltip: preview ? 'Bearbeiten' : 'Lernansicht',
                    onPressed: () => setState(() => preview = !preview),
                    icon: const Icon(Icons.visibility_outlined),
                    selectedIcon: const Icon(Icons.edit_outlined),
                  ),
                  action(
                    Icons.settings_outlined,
                    'Zielsoftware',
                    busy ? null : configureApplication,
                  ),
                  action(
                    Icons.account_tree_outlined,
                    'Ziele erkunden',
                    running || busy ? null : () => run(inspector: true),
                  ),
                  IconButton.filled(
                    tooltip: running
                        ? 'Lernumgebung läuft'
                        : 'Lernumgebung starten',
                    onPressed: running || busy ? null : run,
                    icon: const Icon(Icons.play_arrow_outlined),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (error != null)
              MaterialBanner(
                content: Text(error ?? ''),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => error = null),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final editor = preview
                      ? ColoredBox(
                          color: Colors.white,
                          child: LessonContent(
                            key: ValueKey(document),
                            lessons: document.steps,
                            onHover: (_) {},
                            onSection: (_) {},
                            onActivity: (url) => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Online-Übung'),
                                content: SelectableText(url),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Schließen'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : editPanel();
                  return constraints.maxWidth < 760
                      ? Column(
                          children: [
                            SizedBox(height: 170, child: stepList()),
                            const Divider(),
                            Expanded(child: editor),
                          ],
                        )
                      : Row(
                          children: [
                            SizedBox(width: 248, child: stepList()),
                            const VerticalDivider(),
                            Expanded(child: editor),
                          ],
                        );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    dirty ? Icons.edit_outlined : Icons.check_circle_outline,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dirty
                          ? 'Ungespeichert'
                          : path == null
                          ? 'Neue Lernumgebung'
                          : 'Gespeichert',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Datei wird verarbeitet',
                      ),
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: TextButton(
                      onPressed: configureApplication,
                      child: Text(
                        document.application.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget stepList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Schritte',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            action(
              Icons.add,
              'Schritt hinzufügen',
              document.steps.length >= 200 ? null : addStep,
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: document.steps.length,
          itemBuilder: (context, index) => ListTile(
            selected: index == selected,
            selectedTileColor: const Color(0xFFDCEEFF),
            leading: Icon(
              index == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
            ),
            title: Text(
              document.steps[index].title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${index + 1}'.padLeft(2, '0')),
            onTap: () => setState(() {
              ScaffoldMessenger.of(context).clearSnackBars();
              selected = index;
              preview = false;
              loadFields();
            }),
          ),
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          action(
            Icons.arrow_upward,
            'Schritt nach oben',
            selected == 0 ? null : () => moveStep(-1),
          ),
          action(
            Icons.arrow_downward,
            'Schritt nach unten',
            selected == document.steps.length - 1 ? null : () => moveStep(1),
          ),
          action(
            Icons.copy_outlined,
            'Schritt duplizieren',
            document.steps.length >= 200
                ? null
                : () {
                    final steps = [...document.steps]
                      ..insert(
                        selected + 1,
                        LessonStep(
                          '${step.title} – Kopie',
                          step.content,
                          step.hint,
                        ),
                      );
                    update(steps: steps);
                    setState(() {
                      selected++;
                      loadFields();
                    });
                  },
          ),
          action(
            Icons.delete_outline,
            'Schritt löschen',
            document.steps.length == 1 ? null : deleteStep,
          ),
        ],
      ),
    ],
  );

  Widget editPanel() => ColoredBox(
    color: Colors.white,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Lernumgebung'),
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              update(name: value);
            } else {
              setState(() {
                dirty = true;
                revision++;
              });
            }
          },
        ),
        const SizedBox(height: 24),
        TextField(
          controller: stepTitle,
          decoration: const InputDecoration(labelText: 'Schritttitel'),
          onChanged: (value) => updateStep(name: value),
        ),
        const SizedBox(height: 24),
        Text('Arbeitsauftrag', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < step.content.length; i++) contentBlock(i),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => updateStep(
                content: [
                  ...step.content,
                  const LessonParagraph([LessonText('Text')]),
                ],
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Absatz'),
            ),
            TextButton.icon(
              onPressed: () => updateStep(
                content: [
                  ...step.content,
                  const LessonBulletList([
                    LessonParagraph([LessonText('Listenpunkt')]),
                  ]),
                ],
              ),
              icon: const Icon(Icons.format_list_bulleted, size: 20),
              label: const Text('Liste'),
            ),
            TextButton.icon(
              onPressed: activity,
              icon: const Icon(Icons.open_in_new, size: 20),
              label: const Text('Online-Übung'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: hint,
          decoration: const InputDecoration(labelText: 'Tipp'),
          minLines: 2,
          maxLines: 8,
          onChanged: (value) => updateStep(help: value),
        ),
      ],
    ),
  );

  Widget contentBlock(int index) {
    final block = step.content[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD9D9DF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(switch (block) {
                  LessonParagraph() => 'Absatz',
                  LessonBulletList() => 'Liste',
                  LessonActivity() => 'Online-Übung',
                }, style: Theme.of(context).textTheme.bodySmall),
              ),
              action(
                Icons.arrow_upward,
                'Baustein nach oben',
                index == 0
                    ? null
                    : () {
                        final blocks = [...step.content];
                        blocks.insert(index - 1, blocks.removeAt(index));
                        updateStep(content: blocks);
                      },
              ),
              action(
                Icons.delete_outline,
                'Baustein löschen',
                step.content.length == 1
                    ? null
                    : () {
                        final before = step.content;
                        updateStep(content: [...before]..removeAt(index));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Baustein gelöscht'),
                            action: SnackBarAction(
                              label: 'Rückgängig',
                              onPressed: () {
                                updateStep(content: before);
                              },
                            ),
                          ),
                        );
                      },
              ),
            ],
          ),
          switch (block) {
            LessonParagraph() => paragraphEditor(index, block),
            LessonBulletList() => Column(
              children: [
                for (var j = 0; j < block.items.length; j++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('•'),
                      ),
                      Expanded(
                        child: paragraphEditor(
                          index,
                          block.items[j],
                          bullet: j,
                        ),
                      ),
                      action(
                        Icons.remove,
                        'Listenpunkt löschen',
                        block.items.length == 1
                            ? null
                            : () {
                                final items = [...block.items]..removeAt(j);
                                final blocks = [...step.content];
                                blocks[index] = LessonBulletList(items);
                                updateStep(content: blocks);
                              },
                      ),
                    ],
                  ),
                TextButton(
                  onPressed: () {
                    final blocks = [...step.content];
                    blocks[index] = LessonBulletList([
                      ...block.items,
                      const LessonParagraph([LessonText('Listenpunkt')]),
                    ]);
                    updateStep(content: blocks);
                  },
                  child: const Text('Listenpunkt hinzufügen'),
                ),
              ],
            ),
            LessonActivity() => ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(block.label),
              subtitle: Text(block.url),
              onTap: () => activity(index: index),
            ),
          },
        ],
      ),
    );
  }

  Widget paragraphEditor(int index, LessonParagraph paragraph, {int? bullet}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < paragraph.spans.length; j++)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => changeSpan(index, j, bullet: bullet),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: paragraph.spans[j] is LessonLink
                          ? const Color(0xFF0066D6)
                          : const Color(0xFF1D1D1F),
                    ),
                    child: Text(
                      paragraph.spans[j].text,
                      style: TextStyle(
                        decoration: paragraph.spans[j] is LessonLink
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                  ),
                ),
                action(
                  Icons.close,
                  'Textbaustein entfernen',
                  paragraph.spans.length == 1
                      ? null
                      : () => setParagraph(
                          index,
                          LessonParagraph([...paragraph.spans]..removeAt(j)),
                          bullet: bullet,
                        ),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => addSpan(index, paragraph, bullet: bullet),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Text / Begriff'),
            ),
          ),
        ],
      );
}
