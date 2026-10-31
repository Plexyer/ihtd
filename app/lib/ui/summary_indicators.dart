import 'package:flutter/material.dart';

import 'priority_icon.dart';
import '../services/app_controller.dart';

const _summaryStyle = TextStyle(
  fontSize: 11,
  height: 1.2,
  color: Color(0xff526478),
);

/// Centers the title/metadata in the main body, above a separate bottom footer.
class SummaryItemContent extends StatelessWidget {
  const SummaryItemContent({
    super.key,
    required this.summary,
    required this.child,
    this.onHiddenTap,
  });
  final Map<String, dynamic> summary;
  final Widget child;
  final VoidCallback? onHiddenTap;

  @override
  Widget build(BuildContext context) => SummaryIndicators.hasFooter(summary)
      ? ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 48 + SummaryIndicators.footerExtent(context, summary),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: child),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SummaryIndicators(
                  summary: summary,
                  onHiddenTap: onHiddenTap,
                ),
              ),
            ],
          ),
        )
      : Align(alignment: Alignment.centerLeft, child: child);
}

/// Folder/checkbox/expand controls and the action menu share the title body's
/// centerline. Priority counts remain outside this footer reservation so they
/// center against the entire card instead.
class SummaryBodyControls extends StatelessWidget {
  const SummaryBodyControls({
    super.key,
    required this.summary,
    required this.child,
  });
  final Map<String, dynamic> summary;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: SummaryIndicators.footerExtent(context, summary),
    ),
    child: child,
  );
}

/// Rust's total/ratio and next date, in that order on one footer line.
class SummaryIndicators extends StatelessWidget {
  const SummaryIndicators({super.key, required this.summary, this.onHiddenTap});
  final VoidCallback? onHiddenTap;
  final Map<String, dynamic> summary;

  static bool hasFooter(Map<String, dynamic> summary) =>
      summary['total'] != null ||
      summary['next_due_date'] != null ||
      (summary['hidden_by_rules'] as num? ?? 0) > 0;

  static double footerExtent(
    BuildContext context,
    Map<String, dynamic> summary,
  ) {
    if (!hasFooter(summary)) return 0;
    // Match the actual footer line metrics at the user's font/text scale; a
    // fixed pixel offset would drift at large text or with a different font.
    final painter = TextPainter(
      text: TextSpan(
        text: 'Total: 0',
        style: DefaultTextStyle.of(context).style.merge(_summaryStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final height = (summary['hidden_by_rules'] as num? ?? 0) > 0
        ? painter.height.clamp(24.0, double.infinity)
        : painter.height;
    painter.dispose();
    return height + 4;
  }

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (summary['total'] != null)
        'Total: ${summary['completed'] != null ? '${summary['completed']} / ' : ''}${summary['total']}',
      if (summary['next_due_date'] != null) 'Next: ${summary['next_due_date']}',
    ];
    final hidden = (summary['hidden_by_rules'] as num? ?? 0).toInt();
    if (labels.isEmpty && hidden == 0) return const SizedBox.shrink();
    return DefaultTextStyle.merge(
      style: _summaryStyle,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (labels.isNotEmpty)
              _SummaryDescription(
                description: ['Direct child tasks', ...labels].join('. '),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < labels.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Text(labels[i]),
                    ],
                  ],
                ),
              ),
            if (hidden > 0) ...[
              if (labels.isNotEmpty) const SizedBox(width: 8),
              Semantics(
                button: true,
                label: '$hidden direct child tasks hidden by view rules',
                child: Tooltip(
                  message: '$hidden direct child tasks hidden by view rules',
                  child: InkWell(
                    onTap: onHiddenTap,
                    borderRadius: BorderRadius.circular(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 24,
                        minWidth: 32,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.visibility_off_outlined,
                            size: 12,
                            color: Color(0xff526478),
                          ),
                          const SizedBox(width: 3),
                          Text('$hidden'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact, vertically centered stack containing only enabled nonzero counts.
/// Zeroes remain in the derived Rust response; this is display policy only.
class SummaryPriorityCounts extends StatelessWidget {
  const SummaryPriorityCounts({super.key, required this.summary});
  final Map<String, dynamic> summary;

  static bool hasCounts(Map<String, dynamic> summary) => const [
    'high_priority',
    'medium_priority',
    'low_priority',
  ].any((key) => (summary[key] as num? ?? 0) > 0);

  @override
  Widget build(BuildContext context) {
    final priorities = <(int, String, num)>[
      if ((summary['high_priority'] as num? ?? 0) > 0)
        (3, 'High priority', summary['high_priority'] as num),
      if ((summary['medium_priority'] as num? ?? 0) > 0)
        (2, 'Medium priority', summary['medium_priority'] as num),
      if ((summary['low_priority'] as num? ?? 0) > 0)
        (1, 'Low priority', summary['low_priority'] as num),
    ];
    if (priorities.isEmpty) return const SizedBox.shrink();
    return Center(
      widthFactor: 1,
      child: _SummaryDescription(
        description: [
          'Direct child task priorities',
          ...priorities.map((p) => '${p.$2}: ${p.$3}'),
        ].join('. '),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in priorities)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PriorityIcon(priority: p.$1, size: 14),
                  const SizedBox(width: 2),
                  Text('${p.$3}'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryDescription extends StatelessWidget {
  const _SummaryDescription({required this.description, required this.child});
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: description,
    child: ExcludeSemantics(
      child: Tooltip(
        message: description,
        child: DefaultTextStyle.merge(style: _summaryStyle, child: child),
      ),
    ),
  );
}

/// Capture the owning file/view before the explanation; stale dialogs must not
/// navigate into another collection or dismiss a newer editor draft.
Future<void> showHiddenChildren(
  BuildContext context,
  AppController app, {
  required int parent,
  required String path,
  required int count,
}) async {
  final owner = app.editIdentity;
  final view = app.selectedViewId;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hidden subtasks'),
      content: Text(
        '$count direct child tasks are hidden because they do not match this view’s rules. '
        'Open this parent in All tasks to inspect its children. Completion tabs and visibility settings still apply.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open in All tasks'),
        ),
      ],
    ),
  );
  if (open == true) {
    await app.openParentInAllTasks(
      owner: owner,
      view: view,
      parent: parent,
      path: path,
    );
  }
}
