import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const repositoryUrl = 'https://github.com/fischerscode/schului';

Future<void> showSchuluiAboutDialog(BuildContext context) async {
  var version = 'Version nicht verfügbar';
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      version =
          'Version ${info.version}${info.buildNumber.isEmpty ? '' : ' (Build ${info.buildNumber})'}';
    }
  } on Object {
    // Legal information must remain accessible if build metadata cannot be read.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.school_outlined),
          SizedBox(width: 12),
          Expanded(child: Text('schului')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(version),
              const SizedBox(height: 8),
              const Text('© 2026 Maximilian Fischer'),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => _openRepository(dialogContext),
                icon: const Icon(Icons.open_in_new),
                label: const Text('GitHub-Repository'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () =>
                        _showLegal(dialogContext, 'Impressum', 'impressum'),
                    child: const Text('Impressum'),
                  ),
                  TextButton(
                    onPressed: () => _showLegal(
                      dialogContext,
                      'Datenschutzerklärung',
                      'datenschutz',
                    ),
                    child: const Text('Datenschutzerklärung'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: dialogContext,
            applicationName: 'schului',
            applicationVersion: version,
          ),
          child: const Text('Lizenzen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}

Future<void> _openRepository(BuildContext context) async {
  try {
    if (await launchUrl(
      Uri.parse(repositoryUrl),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } on Object {
    // Offer a copyable address when no browser can be opened.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('GitHub-Repository'),
      content: const SelectableText(
        'Der Browser konnte nicht geöffnet werden. Adresse kopieren:\n\n$repositoryUrl',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}

Future<void> _showLegal(BuildContext context, String title, String name) =>
    showDialog<void>(
      context: context,
      builder: (context) =>
          _LegalDialog(title: title, asset: 'assets/legal/$name.txt'),
    );

class _LegalDialog extends StatefulWidget {
  const _LegalDialog({required this.title, required this.asset});
  final String title, asset;
  @override
  State<_LegalDialog> createState() => _LegalDialogState();
}

class _LegalDialogState extends State<_LegalDialog> {
  late final text = DefaultAssetBundle.of(context).loadString(widget.asset);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 600,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .55,
        ),
        child: FutureBuilder<String>(
          future: text,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Der Text konnte nicht geladen werden.');
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(semanticsLabel: 'Text laden'),
              );
            }
            return Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText(snapshot.requireData),
              ),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Schließen'),
      ),
    ],
  );
}
