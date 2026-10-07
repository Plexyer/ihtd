import 'package:flutter/material.dart';

import '../services/app_controller.dart';

Map<String, dynamic> asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> documentValues(AppController app, String key) =>
    asMap(app.document?[key]).values.map(asMap).toList();

Map<String, dynamic> itemById(AppController app, int id) =>
    asMap(asMap(app.document?['items'])['$id']);

int intValue(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

const priorityNames = ['None', 'Low', 'Medium', 'High'];

String priorityLabel(dynamic value) =>
    priorityNames[intValue(value).clamp(0, priorityNames.length - 1)];

String dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> changeCompletion(
  BuildContext context,
  AppController app,
  int id,
  bool completed,
) async {
  final result = await app.dispatch({
    'op': 'set_completed',
    'id': id,
    'completed': completed,
    'confirm_descendants': false,
  });
  if (result?['confirmation_required'] == true && context.mounted) {
    final count = result?['descendant_count'];
    final confirmed = await confirmAction(
      context,
      title: 'Complete this task and its subtasks?',
      message:
          'This will complete ${count ?? 'all'} unfinished descendant tasks, at every depth. '
          'Shared tasks will be completed in every place they appear.',
      action: 'Complete all',
    );
    if (confirmed) {
      await app.dispatch({
        'op': 'set_completed',
        'id': id,
        'completed': completed,
        'confirm_descendants': true,
      });
    }
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xff66778a),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(21),
              decoration: const BoxDecoration(
                color: Color(0xffe8eff8),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: const Color(0xff4773a6)),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff69788b), height: 1.6),
            ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 22), child: action),
          ],
        ),
      ),
    ),
  );
}
