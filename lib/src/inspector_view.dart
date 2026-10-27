import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'windows_bridge.dart';
import 'accessibility_node.dart';
import 'node_selector.dart';
import '../authoring/application_settings.dart';
export 'accessibility_node.dart';

List<AccessibilityNode> visibleTreeNodes(
  List<AccessibilityNode> nodes,
  Set<String> expanded,
  String query,
) {
  final filter = query.trim().toLowerCase();
  if (filter.isNotEmpty) {
    final byId = {for (final node in nodes) node.id: node};
    final keep = <String>{};
    for (final node in nodes) {
      if (!('${node.name} ${node.type}').toLowerCase().contains(filter)) {
        continue;
      }
      var current = node;
      while (keep.add(current.id)) {
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
    }
    return nodes.where((node) => keep.contains(node.id)).toList();
  }
  final visible = <AccessibilityNode>[];
  int? collapsedDepth;
  for (final node in nodes) {
    if (collapsedDepth != null) {
      if (node.depth > collapsedDepth) continue;
      collapsedDepth = null;
    }
    visible.add(node);
    if (!expanded.contains(node.id)) collapsedDepth = node.depth;
  }
  return visible;
}

class InspectorView extends StatefulWidget {
  const InspectorView({
    super.key,
    this.showLessonReturn = false,
    this.applicationName = 'Draw',
    this.legacyDraw = true,
  });
  final bool showLessonReturn;
  final String applicationName;
  final bool legacyDraw;
  @override
  State<InspectorView> createState() => _InspectorViewState();
}

class _InspectorViewState extends State<InspectorView> {
  final expanded = <String>{};
  final horizontal = ScrollController();
  final vertical = ScrollController();
  final search = TextEditingController();
  Timer? timer;
  Map<String, dynamic> state = {};
  List<AccessibilityNode> nodes = [];
  String? error, notice;
  bool polling = false, initializedTree = false;
  NodeSelector? selector;
  NodeResolution? resolution;

  @override
  void initState() {
    super.initState();
    unawaited(initialize());
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) => refresh());
  }

  Future<void> initialize() async {
    await command('inspector', true);
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
  void dispose() {
    timer?.cancel();
    horizontal.dispose();
    vertical.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> command(String method, [Object? argument]) async {
    try {
      final result = await bridge.invokeMethod<Object?>(method, argument);
      if (!mounted) return;
      setState(() {
        error = null;
        if (method == 'diagnostics' || method == 'connectionDiagnostics') {
          notice = 'Export gespeichert: $result';
        }
      });
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
    if (polling) return;
    polling = true;
    try {
      final value = await bridge.invokeMapMethod<String, dynamic>('state');
      if (!mounted || value == null) return;
      final snapshot = (value['nodes'] as List? ?? [])
          .map(
            (raw) => AccessibilityNode.fromMap(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList();
      if (selector != null) {
        resolution = selector!.resolve(snapshot);
        final nextId = resolution!.node?.id ?? '';
        if (nextId != (value['selectedNodeId'] ?? '')) {
          await bridge.invokeMethod<Object?>('selectNode', nextId);
          value['selectedNodeId'] = nextId;
          value['selection'] = resolution!.node?.toMap();
        }
      }
      if (!mounted) return;
      setState(() {
        state = value;
        nodes = snapshot;
        if (!initializedTree && nodes.isNotEmpty) {
          expanded.addAll(
            nodes.where((node) => node.depth <= 1).map((node) => node.id),
          );
          initializedTree = true;
        }
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } on MissingPluginException {
      /* Allows widget previews. */
    } finally {
      polling = false;
    }
  }

  Future<void> editSelector() async {
    final text = TextEditingController(
      text: selector == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(selector!.toJson()),
    );
    String? validation;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Dauerhafter Knotenpfad'),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: text,
              minLines: 6,
              maxLines: 14,
              decoration: InputDecoration(
                hintText: 'Selektor als JSON einfügen',
                errorText: validation,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text.text));
              },
              child: const Text('Kopieren'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final parsed = NodeSelector.fromJson(jsonDecode(text.text));
                  setState(() {
                    selector = parsed;
                  });
                  Navigator.pop(context);
                  unawaited(refresh());
                } on FormatException catch (e) {
                  update(() => validation = e.message);
                }
              },
              child: const Text('Pfad verwenden'),
            ),
          ],
        ),
      ),
    );
    // The dialog route may still animate while disposing its text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleTreeNodes(nodes, expanded, search.text);
    final parents = nodes.map((node) => node.parentId).toSet();
    final selectedId = state['selectedNodeId'] as String? ?? '';
    final selectedMap = state['selection'];
    final selected = selectedMap is Map
        ? AccessibilityNode.fromMap(Map<String, dynamic>.from(selectedMap))
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.legacyDraw && state['connected'] != true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: selectWindow,
                    icon: const Icon(Icons.window_outlined),
                    label: const Text('Fenster auswählen'),
                  ),
                ),
              if (widget.showLessonReturn)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Zurück zum Unterricht'),
                  ),
                ),
              Text(
                '${widget.applicationName} · Accessibility-Baum',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '${nodes.length} Knoten · Knoten anklicken zum Markieren',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Name oder Elementtyp suchen',
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Baumstruktur',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                      () => expanded.addAll(nodes.map((node) => node.id)),
                    ),
                    tooltip: 'Alle aufklappen',
                    icon: const Icon(Icons.unfold_more),
                  ),
                  IconButton(
                    onPressed: () => setState(() => expanded.clear()),
                    tooltip: 'Alle zuklappen',
                    icon: const Icon(Icons.unfold_less),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        selector = null;
                        resolution = null;
                      });
                      command('selectNode', '');
                    },
                    tooltip: 'Markierung entfernen',
                    icon: const Icon(Icons.layers_clear),
                  ),
                ],
              ),
              Expanded(
                child: nodes.isEmpty
                    ? Center(
                        child: Text(
                          state['connected'] == true
                              ? 'Accessibility-Baum wird gelesen …'
                              : 'Zielsoftware verbinden …',
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final maxDepth = visible.fold<int>(
                            0,
                            (value, node) => math.max(value, node.depth),
                          );
                          final width = math.max(
                            constraints.maxWidth,
                            maxDepth * 16.0 + 320,
                          );
                          return Scrollbar(
                            controller: vertical,
                            thumbVisibility: true,
                            notificationPredicate: (n) =>
                                n.metrics.axis == Axis.vertical,
                            child: Scrollbar(
                              controller: horizontal,
                              thumbVisibility: true,
                              scrollbarOrientation: ScrollbarOrientation.bottom,
                              notificationPredicate: (n) =>
                                  n.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: horizontal,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: width,
                                  height: constraints.maxHeight,
                                  child: ListView.builder(
                                    controller: vertical,
                                    itemCount: visible.length,
                                    itemBuilder: (context, index) {
                                      final node = visible[index];
                                      final hasChildren = parents.contains(
                                        node.id,
                                      );
                                      return Material(
                                        color: node.id == selectedId
                                            ? const Color(0xFFDBEAFE)
                                            : Colors.transparent,
                                        child: InkWell(
                                          key: ValueKey('node-${node.id}'),
                                          onTap: () {
                                            selector = NodeSelector.capture(
                                              node,
                                              nodes,
                                              legacyDraw: widget.legacyDraw,
                                            );
                                            command('selectNode', node.id);
                                          },
                                          child: SizedBox(
                                            height: 40,
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                left: node.depth * 16.0,
                                              ),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 28,
                                                    child: hasChildren
                                                        ? IconButton(
                                                            padding:
                                                                EdgeInsets.zero,
                                                            iconSize: 20,
                                                            tooltip:
                                                                expanded
                                                                    .contains(
                                                                      node.id,
                                                                    )
                                                                ? 'Zuklappen'
                                                                : 'Aufklappen',
                                                            onPressed: () =>
                                                                setState(() {
                                                                  if (!expanded
                                                                      .remove(
                                                                        node.id,
                                                                      )) {
                                                                    expanded.add(
                                                                      node.id,
                                                                    );
                                                                  }
                                                                }),
                                                            icon: Icon(
                                                              expanded.contains(
                                                                    node.id,
                                                                  )
                                                                  ? Icons
                                                                        .expand_more
                                                                  : Icons
                                                                        .chevron_right,
                                                            ),
                                                          )
                                                        : const Icon(
                                                            Icons.circle,
                                                            size: 5,
                                                          ),
                                                  ),
                                                  Expanded(
                                                    child: Tooltip(
                                                      message:
                                                          '${node.type}\n${node.label}',
                                                      child: Text(
                                                        '[${node.type.isEmpty ? 'Element' : node.type}] ${node.label}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: node.offscreen
                                                              ? Colors.grey
                                                              : null,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              if (resolution != null)
                Text(
                  resolution!.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              TextButton.icon(
                onPressed: editSelector,
                icon: const Icon(Icons.route),
                label: const Text('Pfad anzeigen / laden'),
              ),
              if (selected != null) ...[
                Text(
                  selected.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  selected.canHighlight
                      ? 'x=${selected.bounds.left.round()}, y=${selected.bounds.top.round()} · ${selected.bounds.width.round()} × ${selected.bounds.height.round()} px'
                      : 'Nicht sichtbar oder ohne Bildschirmrechteck – keine Markierung.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else
                Text(
                  selector == null && selectedId.isEmpty
                      ? 'Noch kein Knoten ausgewählt.'
                      : 'Der ausgewählte Knoten ist aktuell nicht eindeutig auffindbar. Markierung entfernt.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (error != null)
                Text(
                  error!,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.red),
                ),
              if (notice != null)
                Tooltip(
                  message: notice!,
                  child: Text(
                    notice!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              TextButton(
                onPressed: () => command('connectionDiagnostics'),
                child: const Text('Verbindungsdiagnose exportieren'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => command('diagnostics'),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Baum exportieren'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => command('exit'),
                      icon: const Icon(Icons.close),
                      label: const Text('Beenden'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InspectorOverlay extends StatelessWidget {
  const InspectorOverlay({super.key, required this.state});
  final Map<String, dynamic> state;
  @override
  Widget build(BuildContext context) {
    final raw = state['selection'];
    final node = raw is Map
        ? AccessibilityNode.fromMap(Map<String, dynamic>.from(raw))
        : null;
    final scale = MediaQuery.devicePixelRatioOf(context);
    final originX = (state['drawLeft'] as num? ?? 0).toDouble();
    final originY = (state['drawTop'] as num? ?? 0).toDouble();
    return ColoredBox(
      color: overlayKey,
      child: IgnorePointer(
        child: Stack(
          children: [
            if (node != null && node.canHighlight)
              Positioned(
                key: const ValueKey('inspector-highlight'),
                left: (node.bounds.left - originX) / scale,
                top: (node.bounds.top - originY) / scale,
                width: node.bounds.width / scale,
                height: node.bounds.height / scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B8FF),
                    border: Border.all(
                      color: const Color(0xFF0069FF),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
