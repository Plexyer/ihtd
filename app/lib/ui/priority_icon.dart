import 'package:flutter/material.dart';

import 'shared.dart';

/// One priority design for hierarchy rows, selectors and summary counters.
/// Keep [size] explicit when using the compact counter variant.
class PriorityIcon extends StatelessWidget {
  const PriorityIcon({super.key, required this.priority, this.size = 18});

  final int priority;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      1 => const Color(0xff737b84),
      2 => const Color(0xffb78324),
      3 => const Color(0xffc44343),
      _ => null,
    };
    if (color == null) return const SizedBox.shrink();
    final label = '${priorityLabel(priority)} priority';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Icon(
        priority == 3
            ? Icons.warning_amber_rounded
            : Icons.priority_high_rounded,
        color: color,
        size: size,
        semanticLabel: label,
      ),
    );
  }
}

/// A selector's visible text supplies its accessible name; don't announce the
/// decorative icon a second time.
class PriorityChoice extends StatelessWidget {
  const PriorityChoice({super.key, required this.priority});

  final int priority;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (priority >= 1 && priority <= 3) ...[
        ExcludeSemantics(child: PriorityIcon(priority: priority)),
        const SizedBox(width: 8),
      ],
      Text(priorityLabel(priority)),
    ],
  );
}
