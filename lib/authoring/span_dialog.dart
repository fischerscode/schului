import 'dart:convert';

import 'package:flutter/material.dart';

import '../lessons/lesson_model.dart';
import '../lessons/draw_target.dart';
import '../lessons/draw_targets.dart';
import '../src/node_selector.dart';

const targetPresets = <String, DrawTarget>{
  'Rechteck-Werkzeug': DrawTargets.rectangleTool,
  'Ellipse-Werkzeug': DrawTargets.ellipseTool,
  'Rechteck-Objekt': DrawTargets.rectangleObject,
};

Future<LessonSpan?> editSpan(BuildContext context, LessonSpan span) =>
    showDialog<LessonSpan>(
      context: context,
      builder: (_) => _SpanDialog(span: span),
    );

class _SpanDialog extends StatefulWidget {
  const _SpanDialog({required this.span});
  final LessonSpan span;
  @override
  State<_SpanDialog> createState() => _SpanDialogState();
}

class _SpanDialogState extends State<_SpanDialog> {
  late final text = TextEditingController(text: widget.span.text);
  late final help = TextEditingController(
    text: switch (widget.span) {
      LessonLink(:final help) => help,
      LessonText() => '',
    },
  );
  late final path = TextEditingController(
    text: switch (widget.span) {
      LessonLink(:final target?) => const JsonEncoder.withIndent(
        '  ',
      ).convert(target.toJson()),
      _ => '',
    },
  );
  late bool linked = widget.span is LessonLink;
  late bool bold = switch (widget.span) {
    LessonText(:final bold) => bold,
    LessonLink() => false,
  };
  String? error;
  @override
  void dispose() {
    text.dispose();
    help.dispose();
    path.dispose();
    super.dispose();
  }

  void save() {
    try {
      DrawTarget? target;
      if (linked && path.text.trim().isNotEmpty) {
        final Object? raw = jsonDecode(path.text);
        target = raw is Map<String, Object?> && raw.containsKey('selector')
            ? DrawTarget.fromJson(raw)
            : DrawTarget(NodeSelector.fromJson(raw));
      }
      if (text.text.trim().isEmpty) {
        throw const FormatException('Text eingeben.');
      }
      Navigator.pop(
        context,
        linked
            ? LessonLink(
                text.text,
                target: target,
                help: help.text.isEmpty ? null : help.text,
              )
            : LessonText(text.text, bold: bold),
      );
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Textbaustein'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Text'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Interaktiver Begriff'),
              value: linked,
              onChanged: (value) => setState(() => linked = value),
            ),
            if (!linked)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fett'),
                value: bold,
                onChanged: (value) => setState(() => bold = value ?? false),
              ),
            if (linked) ...[
              TextField(
                controller: help,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Hilfetext'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Draw-Zielvorlage',
                ),
                items: [
                  for (final name in targetPresets.keys)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: (value) {
                  final target = targetPresets[value];
                  if (target != null) {
                    path.text = const JsonEncoder.withIndent('  ')
                        .convert(target.toJson());
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: path,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Zielpfad (JSON, optional)',
                  helperText: 'Pfad aus dem Inspector einfügen.',
                ),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error ?? '',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: save, child: const Text('Übernehmen')),
    ],
  );
}
