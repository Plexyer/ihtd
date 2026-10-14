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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final titleWidget = Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Semantics(
            namesRoute: true,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.headlineSmall!,
              child: title,
            ),
          ),
        );
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: content,
          ),
        );
        final footer = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        );
        // At short heights/large text, even title + wrapped actions can consume
        // the entire viewport. Include them in the scroll rather than overflow.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
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
    ),
  );
}
