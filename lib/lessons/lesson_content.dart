import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lesson_model.dart';
import '../src/windows_bridge.dart';

class LessonContent extends StatefulWidget {
  const LessonContent({
    super.key,
    required this.onHover,
    required this.onSection,
    required this.lessons,
    this.onActivity,
    this.onHint,
    this.title,
    this.notice,
    this.actions,
  });
  final ValueChanged<LessonLink?> onHover;
  final ValueChanged<int> onSection;
  final List<LessonStep> lessons;
  final ValueChanged<LessonActivity>? onActivity;
  final VoidCallback? onHint;
  final String? title;
  final Widget? notice, actions;
  @override
  State<LessonContent> createState() => _LessonContentState();
}

class _LessonContentState extends State<LessonContent> {
  final controller = ScrollController();
  final viewport = GlobalKey();
  late final sectionKeys = List.generate(
    widget.lessons.length,
    (_) => GlobalKey(),
  );
  int current = 0;
  LessonLink? hovered;
  @override
  void initState() {
    super.initState();
    controller.addListener(clearHover);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void clearHover() {
    if (hovered == null) return;
    hovered = null;
    widget.onHover(null);
  }

  void go(int index) {
    if (index == current) return;
    FocusManager.instance.primaryFocus?.unfocus();
    clearHover();
    setState(() => current = index);
    widget.onSection(index);
    // Expanding one section changes all subsequent offsets. Scroll only after
    // the new layout, and keep scrolling independent of task activation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final section = sectionKeys[index].currentContext;
      if (section == null) return;
      final sectionBox = section.findRenderObject() as RenderBox?;
      final viewportBox =
          viewport.currentContext?.findRenderObject() as RenderBox?;
      final fits =
          sectionBox != null &&
          viewportBox != null &&
          sectionBox.size.height <= viewportBox.size.height;
      Scrollable.ensureVisible(
        section,
        alignment: fits ? .5 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget section(int index) {
    final theme = Theme.of(context);
    final step = widget.lessons[index];
    final active = index == current;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: active,
          child: Text(
            step.title,
            style:
                (active
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
          ),
        ),
        if (active) ...[
          const SizedBox(height: 24),
          for (final item in step.content)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: block(item),
            ),
        ],
      ],
    );
    return Container(
      key: sectionKeys[index],
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.surface
            : theme.scaffoldBackgroundColor,
        border: Border(
          left: BorderSide(
            width: 3,
            color: active ? theme.colorScheme.primary : Colors.transparent,
          ),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: active
          ? Semantics(
              expanded: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: content,
              ),
            )
          : TextButton(
              onPressed: () => go(index),
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.all(24)),
                shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    width: 2,
                    color: states.contains(WidgetState.focused)
                        ? const Color(0xFF007AFF)
                        : Colors.transparent,
                  ),
                ),
              ),
              child: Semantics(
                label: 'Aufgabe ${index + 1} aktivieren: ${step.title}',
                expanded: false,
                child: ExcludeSemantics(child: content),
              ),
            ),
    );
  }

  Widget paragraph(LessonParagraph paragraph) => Text.rich(
    TextSpan(
      children: [
        for (final span in paragraph.spans)
          switch (span) {
            LessonText() => TextSpan(
              text: span.text,
              style: span.bold
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
            LessonLink() => WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MouseRegion(
                cursor: SystemMouseCursors.help,
                onEnter: (_) {
                  hovered = span;
                  widget.onHover(span);
                },
                onExit: (_) {
                  if (identical(hovered, span)) {
                    hovered = null;
                    widget.onHover(null);
                  }
                },
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      hovered = span;
                      widget.onHover(span);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  onFocusChange: (focused) {
                    if (focused) {
                      hovered = span;
                      widget.onHover(span);
                    } else if (identical(hovered, span)) {
                      hovered = null;
                      widget.onHover(null);
                    }
                  },
                  child: Builder(
                    builder: (context) {
                      final focus = Focus.of(context);
                      return Semantics(
                        button: true,
                        onTap: focus.requestFocus,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          onTap: focus.requestFocus,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                width: 2,
                                color: focus.hasFocus
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              span.text,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ).maybeTooltip(span.help),
            ),
          },
      ],
    ),
    style: Theme.of(context).textTheme.bodyLarge,
  );

  Widget block(LessonBlock block) => switch (block) {
    LessonActivity() => OutlinedButton.icon(
      onPressed: () async {
        widget.onHover(null);
        if (widget.onActivity case final action?) {
          action(block);
          return;
        }
        try {
          await bridge.invokeMethod<void>('webPage', block.toWebPageRequest());
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Die Webseite konnte nicht geöffnet werden. Bitte starte SchulUI vollständig neu.',
              ),
            ),
          );
        }
      },
      icon: const Icon(Icons.open_in_new),
      label: Text(block.label),
    ),
    LessonParagraph() => paragraph(block),
    LessonBulletList() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in block.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: Theme.of(context).textTheme.bodyLarge),
                Expanded(child: paragraph(item)),
              ],
            ),
          ),
      ],
    ),
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.title != null || widget.actions != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 8, 16),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              ?widget.actions,
            ],
          ),
        ),
        const Divider(),
      ],
      Expanded(
        child: Scrollbar(
          controller: controller,
          child: SingleChildScrollView(
            key: viewport,
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.lessons.length; i++) section(i),
              ],
            ),
          ),
        ),
      ),
      if (widget.notice case final notice?)
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .4,
          ),
          child: SingleChildScrollView(child: notice),
        ),
      Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: current > 0 ? () => go(current - 1) : null,
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Vorheriger Abschnitt',
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label:
                                'Abschnitt ${current + 1} von ${widget.lessons.length}',
                            child: ExcludeSemantics(
                              child: Text(
                                '${current + 1} / ${widget.lessons.length}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: (current + 1) / widget.lessons.length,
                              minHeight: 2,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: current < widget.lessons.length - 1
                        ? () => go(current + 1)
                        : null,
                    icon: Icon(
                      Icons.arrow_downward,
                      color: current < widget.lessons.length - 1
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                    tooltip: 'Nächster Abschnitt',
                  ),
                  if (widget.onHint != null &&
                      widget.lessons[current].hint.trim().isNotEmpty)
                    IconButton(
                      onPressed: widget.onHint,
                      tooltip: 'Tipp anzeigen',
                      icon: const Icon(Icons.lightbulb_outline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

extension on Widget {
  Widget maybeTooltip(String? hint) {
    if (hint == null) {
      return this;
    } else {
      return Tooltip(message: hint, child: this);
    }
  }
}
