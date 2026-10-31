import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The approved editor styling is scoped to item forms, not other app dialogs.
class ItemEditorStyle extends StatelessWidget {
  const ItemEditorStyle({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    const blue = Color(0xff2763a5);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xffbcc8d8)),
    );
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(primary: blue),
        textTheme: base.textTheme.copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: const Color(0xfffcfdff),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: blue, width: 2),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: const BorderSide(color: Color(0xffbcc8d8)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled) ? null : Colors.white,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? null
                : states.contains(WidgetState.selected)
                ? blue
                : const Color(0xffbcc8d8),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Short leading rule, readable left-aligned title and continuing trailing rule.
class ItemEditorSection extends StatelessWidget {
  const ItemEditorSection(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style.merge(
          const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xff18334c),
          ),
        );
        final maxTitleWidth = math.max(
          0.0,
          constraints.maxWidth - 64 - (trailing == null ? 0 : 48),
        );
        const line = Divider(height: 1, thickness: 1, color: Color(0xffaab8cb));
        return Semantics(
          header: true,
          child: Row(
            children: [
              const SizedBox(width: 16, child: line),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTitleWidth),
                child: Text(text, style: style),
              ),
              const SizedBox(width: 8),
              const Expanded(child: line),
              if (trailing != null) SizedBox(width: 48, child: trailing),
            ],
          ),
        );
      },
    ),
  );
}

class ItemEditorFields extends StatelessWidget {
  const ItemEditorFields({
    super.key,
    required this.first,
    required this.second,
  });
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        text: TextSpan(
          text: 'Medium',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      // Priority label, icon/gap, dropdown arrow, field padding and clearance.
      final requiredWidth = math.max(320.0, 2 * (painter.width + 90) + 12);
      painter.dispose();
      if (constraints.maxWidth >= requiredWidth && scaler.scale(14) <= 18.2) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 16), second],
      );
    },
  );
}
