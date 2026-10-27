import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'target_application.dart';
import 'target_picker.dart';
import '../src/windows_bridge.dart';

Future<int?> chooseSessionWindow(BuildContext context) async {
  final raw = await bridge.invokeListMethod<Object?>('applicationWindows');
  final windows = [
    for (final entry in raw ?? []) ApplicationWindow.decode(entry),
  ];
  if (!context.mounted) return null;
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Fenster auswählen'),
      children: [
        if (windows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Kein passendes Fenster geöffnet.'),
          ),
        for (final window in windows)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, window.id),
            child: Text(window.title),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    ),
  );
}

class ApplicationWindow {
  const ApplicationWindow(
    this.id,
    this.title,
    this.executable,
    this.windowClass,
  );
  final int id;
  final String title, executable, windowClass;
  factory ApplicationWindow.decode(Object? raw) {
    if (raw is! Map<Object?, Object?> ||
        raw['id'] is! int ||
        raw['title'] is! String ||
        raw['executable'] is! String ||
        raw['windowClass'] is! String) {
      throw const FormatException('Ungültige Fensterinformationen.');
    }
    return ApplicationWindow(
      raw['id'] as int,
      raw['title'] as String,
      raw['executable'] as String,
      raw['windowClass'] as String,
    );
  }
}

Future<TargetApplication?> editApplication(
  BuildContext context,
  TargetApplication application,
) => showDialog<TargetApplication>(
  context: context,
  builder: (_) => _Settings(application: application),
);

class _Settings extends StatefulWidget {
  const _Settings({required this.application});
  final TargetApplication application;
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late final name = TextEditingController(
    text: widget.application is UnconfiguredApplication
        ? ''
        : widget.application.name,
  );
  late final executable = TextEditingController(
    text: switch (widget.application) {
      WindowsApplication(:final executable) => executable,
      _ => '',
    },
  );
  late final arguments = TextEditingController(
    text: switch (widget.application) {
      WindowsApplication(:final arguments) => arguments.join('\n'),
      _ => '',
    },
  );
  late final windowClass = TextEditingController(
    text: switch (widget.application) {
      WindowsApplication(:final windowClass) => windowClass,
      _ => '',
    },
  );
  late final title = TextEditingController(
    text: switch (widget.application) {
      WindowsApplication(:final titleContains) => titleContains,
      _ => '',
    },
  );
  late bool draw = widget.application is DrawApplication;
  List<ApplicationWindow> windows = [];
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    name.dispose();
    executable.dispose();
    arguments.dispose();
    windowClass.dispose();
    title.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final raw = await targetPickerChannel.invokeListMethod<Object?>(
        'windows',
      );
      if (mounted) {
        setState(
          () => windows = [
            for (final item in raw ?? []) ApplicationWindow.decode(item),
          ],
        );
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => error = 'Fenster sind nur unter Windows verfügbar. Programmpfad manuell wählen.',
        );
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> browse() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Windows-Programm', extensions: ['exe', 'bin']),
        ],
      );
      if (file != null && mounted) {
        setState(() {
          draw = false;
          executable.text = file.path;
          if (name.text.isEmpty) name.text = file.name;
          windowClass.clear();
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    }
  }

  void save() {
    try {
      Navigator.pop(
        context,
        draw
            ? const DrawApplication()
            : WindowsApplication(
                name: name.text,
                executable: executable.text,
                arguments: arguments.text.isEmpty
                    ? []
                    : arguments.text.split('\n'),
                windowClass: windowClass.text,
                titleContains: title.text,
              ),
      );
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Zielsoftware'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Geöffnetes Fenster')),
                IconButton(
                  tooltip: 'Fenster aktualisieren',
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (loading)
              const LinearProgressIndicator(semanticsLabel: 'Fenster laden'),
            DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Software auswählen',
              ),
              items: [
                for (final window in windows)
                  DropdownMenuItem(
                    value: window.id,
                    child: Text(window.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) {
                final candidates = windows.where((w) => w.id == id);
                if (candidates.isEmpty) return;
                final window = candidates.first;
                setState(() {
                  draw = false;
                  executable.text = window.executable;
                  name.text = window.executable.split(RegExp(r'[\\/]')).last;
                  windowClass.text = window.windowClass;
                  arguments.clear();
                  title.clear();
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              enabled: !draw,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() => draw = false),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: executable,
              enabled: !draw,
              decoration: InputDecoration(
                labelText: 'Programmpfad',
                suffixIcon: IconButton(
                  tooltip: 'Programm auswählen',
                  onPressed: browse,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ),
              onChanged: (_) => setState(() => draw = false),
            ),
            if (!draw)
              ExpansionTile(
                title: const Text('Start und Fenster'),
                children: [
                  TextField(
                    controller: arguments,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Startargumente',
                      helperText: 'Ein Argument pro Zeile. Kein Shell-Befehl.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: windowClass,
                    decoration: const InputDecoration(
                      labelText: 'Fensterklasse (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Fenstertitel enthält (optional)',
                    ),
                  ),
                ],
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('LibreOffice Draw'),
              value: draw,
              onChanged: (value) => setState(() {
                draw = value ?? false;
                if (draw) {
                  name.text = 'LibreOffice Draw';
                  executable.clear();
                  arguments.clear();
                  windowClass.clear();
                  title.clear();
                }
              }),
            ),
            if (error != null)
              Text(
                error ?? '',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
