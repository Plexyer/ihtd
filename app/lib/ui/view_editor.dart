import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'shared.dart';
import 'editor_dialog.dart';
import '../services/rule_draft.dart';
import 'rule_expression.dart';

Future<void> showViewEditor(
  BuildContext context,
  AppController app, {
  Map<String, dynamic>? existing,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ViewDialog(app: app, existing: existing),
  );
}

class _ViewDialog extends StatefulWidget {
  const _ViewDialog({required this.app, this.existing});
  final AppController app;
  final Map<String, dynamic>? existing;
  @override
  State<_ViewDialog> createState() => _ViewDialogState();
}

class _ViewDialogState extends State<_ViewDialog> {
  late TextEditingController name;
  late RuleDraft draft;
  late DocumentEditIdentity identity;
  Map<String, dynamic>? original;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.existing?['name'] as String? ?? 'New view',
    );
    identity = widget.app.editIdentity;
    original = widget.existing == null
        ? null
        : asMap(jsonDecode(jsonEncode(widget.existing)));
    draft = RuleDraft(original == null ? null : asMap(original!['filter']));
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter a view name.');
      return;
    }
    if (draft.slots.isNotEmpty) {
      setState(
        () => error = 'Fill or remove each empty condition before saving.',
      );
      return;
    }
    setState(() => saving = true);
    final result = await widget.app.dispatch(
      {
        'op': widget.existing == null ? 'add_view' : 'edit_view',
        if (widget.existing != null) 'id': widget.existing!['id'],
        'name': name.text.trim(),
        'filter': draft.encode(),
      },
      expectedDocument: identity,
      expectedView: original,
    );
    if (!mounted) return;
    if (result != null) {
      if (result['id'] != null) widget.app.selectView(intValue(result['id']));
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.app.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => EditorDialog(
    maxWidth: 1120,
    title: Text(widget.existing == null ? 'Create a view' : 'Edit view'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          enabled: !saving,
          controller: name,
          decoration: const InputDecoration(labelText: 'View name'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Rules select shared items; their ancestors remain visible for context.',
          style: TextStyle(fontSize: 13, color: Color(0xff748398)),
        ),
        const SizedBox(height: 12),
        RuleExpression(
          app: widget.app,
          draft: draft,
          identity: identity,
          enabled: !saving,
          onChanged: () => setState(() => error = null),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      if (widget.existing != null &&
          documentValues(widget.app, 'views').length > 1)
        PopupMenuButton<String>(
          tooltip: 'View actions',
          enabled: !saving,
          onSelected: (_) async {
            if (await confirmAction(
              context,
              title: 'Delete this view?',
              message:
                  'Tasks, folders, and their links remain in the collection.',
              action: 'Delete view',
            )) {
              final result = await widget.app.dispatch(
                {'op': 'remove_view', 'id': widget.existing!['id']},
                expectedDocument: identity,
                expectedView: original,
              );
              if (!context.mounted) return;
              if (result != null) {
                Navigator.pop(context);
              } else {
                setState(() => error = widget.app.error);
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'delete', child: Text('Delete view')),
          ],
        ),
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save view'),
      ),
    ],
  );
}
