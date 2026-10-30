import 'package:flutter/material.dart';

import 'priority_icon.dart';

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
  });
  final Map<String, dynamic> summary;
  final Widget child;

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
                child: SummaryIndicators(summary: summary),
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
  const SummaryIndicators({super.key, required this.summary});
  final Map<String, dynamic> summary;

  static bool hasFooter(Map<String, dynamic> summary) =>
      summary['total'] != null || summary['next_due_date'] != null;

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
    final height = painter.height;
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
    if (labels.isEmpty) return const SizedBox.shrink();
    return _SummaryDescription(
      description: ['Direct child tasks', ...labels].join('. '),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
