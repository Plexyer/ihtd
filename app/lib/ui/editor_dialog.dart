import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

/// One scroll/focus layout for editors on phones and desktop windows.
/// Dialog itself applies safe-area/keyboard constraints; do not subtract them
/// again here. Floating outline labels need paint space inside the viewport.
class EditorDialog extends StatelessWidget {
  const EditorDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.maxWidth = 680,
  });

  final Widget title, content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Dialog(
    semanticsRole: SemanticsRole.alertDialog,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 760),
    child: EditorFormLayout(title: title, content: content, actions: actions),
  );
}

/// The same responsive form layout also embeds in desktop item details.
class EditorFormLayout extends StatefulWidget {
  const EditorFormLayout({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.constrainedTitle,
    this.constrainedHeader,
  });
  final Widget title, content;

  /// Optional header for shorter layouts, after dialog/keyboard insets.
  final Widget? constrainedTitle;

  /// Pinned controls for short creation forms; the caption/body/footer scroll.
  final Widget? constrainedHeader;
  final List<Widget> actions;
  @override
  State<EditorFormLayout> createState() => _EditorFormLayoutState();
}

class _EditorFormLayoutState extends State<EditorFormLayout> {
  // Keyboard/window constraints can move these subtrees between the fixed and
  // fully scrolling layouts. Preserve field selection, focus and button state
  // instead of remounting them (which would dismiss the view-name keyboard).
  final _titleKey = GlobalKey();
  final _bodyKey = GlobalKey();
  final _actionsKey = GlobalKey();
  final _constrainedHeaderKey = GlobalKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final title = constraints.maxHeight < 600 * scale
          ? widget.constrainedTitle ?? widget.title
          : widget.title;
      final titleWidget = KeyedSubtree(
        key: _titleKey,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Semantics(
            namesRoute: true,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.headlineSmall!,
              child: title,
            ),
          ),
        ),
      );
      final body = KeyedSubtree(
        key: _bodyKey,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: widget.content,
          ),
        ),
      );
      final footer = KeyedSubtree(
        key: _actionsKey,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: widget.actions,
          ),
        ),
      );
      if (constraints.maxHeight < 600 * scale &&
          widget.constrainedHeader != null) {
        final header = KeyedSubtree(
          key: _constrainedHeaderKey,
          child: widget.constrainedHeader!,
        );
        final form = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [titleWidget, body, footer],
        );
        // An exceptionally small viewport cannot fit even the controls. Retain
        // the fully scrolling fallback so enlarged controls never overflow.
        if (constraints.maxHeight < 140 * scale) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, form],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Flexible(child: SingleChildScrollView(child: form)),
          ],
        );
      }
      // At short heights/large text, even title + wrapped actions can consume
      // the entire viewport. Include them in the scroll rather than overflow.
      if (constraints.maxHeight < 360 * scale) {
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleWidget, body, footer],
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleWidget,
          Flexible(child: SingleChildScrollView(child: body)),
          footer,
        ],
      );
    },
  );
}
