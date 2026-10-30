import 'package:flutter/material.dart';

import 'priority_icon.dart';

/// Renders Rust's resolved metrics only. No filtering, defaults or calculations
/// belong in this widget; an absent key means the indicator is disabled.
class SummaryIndicators extends StatelessWidget {
  const SummaryIndicators({super.key, required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (summary['total'] != null)
        'Total: ${summary['completed'] != null ? '${summary['completed']} / ' : ''}${summary['total']}',
      if (summary.containsKey('next_due_date'))
        'Next: ${summary['next_due_date'] ?? '—'}',
    ];
    final priorities = <(int, String, String)>[
      if (summary['high_priority'] != null)
        (3, 'High priority', '${summary['high_priority']}'),
      if (summary['medium_priority'] != null)
        (2, 'Medium priority', '${summary['medium_priority']}'),
      if (summary['low_priority'] != null)
        (1, 'Low priority', '${summary['low_priority']}'),
    ];
    if (labels.isEmpty && priorities.isEmpty) return const SizedBox.shrink();
    final description = [
      'Direct child tasks',
      ...labels,
      ...priorities.map((p) => '${p.$2}: ${p.$3}'),
    ].join('. ');
    // Three 14px pairs fit inside the existing 48px row controls. Enlarged text
    // uses a horizontal run instead of growing a three-row stack or shrinking
    // the user's chosen font. Narrow/deep cards can scroll this compact region.
    final horizontal = MediaQuery.textScalerOf(context).scale(11) > 15;
    Widget priorityPairs() => Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in priorities)
          Padding(
            padding: EdgeInsets.only(right: horizontal ? 6 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PriorityIcon(priority: p.$1, size: 14),
                const SizedBox(width: 2),
                Text(p.$3),
              ],
            ),
          ),
      ],
    );
    Widget labelLines({required bool clipped}) => horizontal
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final label in labels)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(label),
                ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final label in labels)
                Text(
                  label,
                  maxLines: 1,
                  overflow: clipped ? TextOverflow.ellipsis : null,
                ),
            ],
          );
    final text = DefaultTextStyle.merge(
      style: const TextStyle(
        fontSize: 11,
        height: 1.2,
        color: Color(0xff526478),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scroll = horizontal || constraints.maxWidth < 96;
          final pairs = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Keep the counters visible first. A long date must never push their
              // numbers off the edge of an otherwise roomy parent card.
              if (priorities.isNotEmpty) priorityPairs(),
              if (labels.isNotEmpty && priorities.isNotEmpty)
                const SizedBox(width: 6),
              if (labels.isNotEmpty)
                scroll
                    ? labelLines(clipped: false)
                    : Flexible(child: labelLines(clipped: true)),
            ],
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: scroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: pairs,
                  )
                : pairs,
          );
        },
      ),
    );
    return Semantics(
      label: description,
      child: ExcludeSemantics(
        child: Tooltip(message: description, child: text),
      ),
    );
  }
}
