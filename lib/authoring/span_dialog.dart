import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lessons/lesson_model.dart';
import '../lessons/application_target.dart';
import '../lessons/draw_targets.dart';
import '../src/node_selector.dart';
import 'target_picker.dart';
import 'target_application.dart';

const targetPresets = <String, ApplicationTarget>{
  'Rechteck-Werkzeug': DrawTargets.rectangleTool,
  'Ellipse-Werkzeug': DrawTargets.ellipseTool,
  'Rechteck-Objekt': DrawTargets.rectangleObject,
};

Future<LessonSpan?> editSpan(
  BuildContext context,
  LessonSpan span, {
  TargetApplication application = const DrawApplication(),
}) => showDialog<LessonSpan>(
  context: context,
  builder: (_) => _SpanDialog(span: span, application: application),
);

class _SpanDialog extends StatefulWidget {
  const _SpanDialog({required this.span, required this.application});
  final LessonSpan span;
  final TargetApplication application;
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
  final picker = TargetPicker();
  bool picking = false;
  String candidate = '', pickError = '';

  Future<void> pickTarget() async {
    setState(() {
      picking = true;
      error = null;
      candidate = '';
      pickError = '';
    });
    try {
      final target = await picker.pick(
        application: widget.application,
        onCandidate: (label, message) {
          if (mounted) {
            setState(() {
              candidate = label;
              pickError = message;
            });
          }
        },
      );
      if (mounted && target != null) {
        path.text = const JsonEncoder.withIndent('  ').convert(target.toJson());
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => error = 'Die Zielauswahl benötigt den Windows-Editor.');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  void dispose() {
    if (picking) unawaited(picker.cancel());
    text.dispose();
    help.dispose();
    path.dispose();
    super.dispose();
  }

  void save() {
    try {
      ApplicationTarget? target;
      if (linked && path.text.trim().isNotEmpty) {
        final Object? raw = jsonDecode(path.text);
        target = raw is Map<String, Object?> && raw.containsKey('selector')
            ? ApplicationTarget.fromJson(raw)
            : ApplicationTarget(NodeSelector.fromJson(raw));
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
  Widget build(BuildContext context) => PopScope(
    canPop: !picking,
    child: AlertDialog(
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
                onChanged: picking
                    ? null
                    : (value) => setState(() => linked = value),
              ),
              if (!linked)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fett'),
                  value: bold,
                  onChanged: (value) => setState(() => bold = value ?? false),
                ),
              if (linked) ...[
                if (!picking)
                  OutlinedButton.icon(
                    onPressed: widget.application is UnconfiguredApplication
                        ? null
                        : pickTarget,
                    icon: const Icon(Icons.my_location_outlined),
                    label: const Text('Ziel in Anwendung auswählen'),
                  )
                else ...[
                  const Text(
                    'Über ein Ziel in der Anwendung zeigen. F8 übernimmt, Esc bricht ab.',
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      pickError.isNotEmpty
                          ? pickError
                          : candidate.isEmpty
                          ? 'Zielauswahl aktiv'
                          : candidate,
                    ),
                  ),
                  TextButton(
                    onPressed: picker.cancel,
                    child: const Text('Zielauswahl abbrechen'),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: help,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Hilfetext'),
                ),
                const SizedBox(height: 16),
                if (widget.application is DrawApplication)
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: picking ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: picking ? null : save,
          child: const Text('Übernehmen'),
        ),
      ],
    ),
  );
}
