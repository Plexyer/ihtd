import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'shared.dart';
import 'editor_dialog.dart';
import 'item_editor.dart' show showNewTag;

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
  late Map<String, dynamic> rule;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.existing?['name'] as String? ?? 'New view',
    );
    rule = asMap(
      jsonDecode(jsonEncode(widget.existing?['filter'] ?? {'op': 'all'})),
    );
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter a view name.');
      return;
    }
    setState(() => saving = true);
    final result = await widget.app.dispatch({
      'op': widget.existing == null ? 'add_view' : 'edit_view',
      if (widget.existing != null) 'id': widget.existing!['id'],
      'name': name.text.trim(),
      'filter': rule,
    });
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
    title: Text(widget.existing == null ? 'Create a view' : 'Edit view'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'View name'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Rules select shared items; their ancestors remain visible for context.',
          style: TextStyle(fontSize: 13, color: Color(0xff748398)),
        ),
        const SizedBox(height: 12),
        _RuleEditor(
          app: widget.app,
          rule: rule,
          onChanged: (r) => setState(() => rule = r),
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
      TextButton(
        onPressed: () async {
          final tag = await showNewTag(context, widget.app);
          if (tag != null && mounted) setState(() {});
        },
        child: const Text('New tag…'),
      ),
      if (widget.existing != null &&
          documentValues(widget.app, 'views').length > 1)
        TextButton(
          onPressed: () async {
            if (await confirmAction(
              context,
              title: 'Delete this view?',
              message:
                  'Tasks, folders, and their links remain in the collection.',
              action: 'Delete view',
            )) {
              final result = await widget.app.dispatch({
                'op': 'remove_view',
                'id': widget.existing!['id'],
              });
              if (result != null && context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Delete view'),
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

const _ops = {
  'all': 'All items',
  'and': 'ALL conditions (AND)',
  'or': 'ANY condition (OR)',
  'xor': 'Exactly one (XOR)',
  'not': 'NOT condition',
  'text': 'Title or notes',
  'tag': 'Has tag',
  'folder': 'Inside folder/task',
  'due': 'Due date',
  'priority': 'Priority',
  'kind': 'Item type',
  'completed': 'Task completion',
};

Map<String, dynamic> _initialRule(String op, AppController app) {
  final tags = documentValues(app, 'tags');
  final items = documentValues(app, 'items');
  return switch (op) {
    'and' || 'or' || 'xor' => {
      'op': op,
      'rules': [
        {'op': 'all'},
      ],
    },
    'not' => {
      'op': op,
      'rule': {'op': 'all'},
    },
    'text' => {
      'op': op,
      'field': 'title',
      'comparison': 'contains',
      'value': '',
      'case_sensitive': false,
    },
    'tag' => {'op': op, 'tag_id': tags.isEmpty ? 0 : tags.first['id']},
    'folder' => {
      'op': op,
      'folder_id': items.isEmpty ? 0 : items.first['id'],
      'recursive': true,
    },
    'due' => {
      'op': op,
      'comparison': 'before',
      'value': dateText(DateTime.now()),
    },
    'priority' => {'op': op, 'comparison': 'eq', 'value': 0},
    'kind' => {'op': op, 'kind': 'task'},
    'completed' => {'op': op, 'value': false},
    _ => {'op': 'all'},
  };
}

class _RuleEditor extends StatelessWidget {
  const _RuleEditor({
    required this.app,
    required this.rule,
    required this.onChanged,
  });
  final AppController app;
  final Map<String, dynamic> rule;
  final ValueChanged<Map<String, dynamic>> onChanged;
  void set(String key, dynamic value) => onChanged({...rule, key: value});
  Widget dropdown<T>({
    required T value,
    required String label,
    required Map<T, String> choices,
    required ValueChanged<T> changed,
  }) => DropdownButtonFormField<T>(
    key: ValueKey('$label-$value'),
    initialValue: choices.containsKey(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in choices.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      if (value != null) changed(value);
    },
  );
  @override
  Widget build(BuildContext context) {
    final op = '${rule['op']}';
    final group = ['and', 'or', 'xor'].contains(op);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffdce4ee)),
      ),
      // Give checkbox rows an ink surface inside the decorated rule card.
      child: Material(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dropdown(
              value: op,
              label: 'Rule',
              choices: _ops,
              changed: (value) => onChanged(_initialRule(value, app)),
            ),
            const SizedBox(height: 12),
            if (group) ...[
              for (var i = 0; i < (rule['rules'] as List).length; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _RuleEditor(
                        app: app,
                        rule: asMap((rule['rules'] as List)[i]),
                        onChanged: (value) {
                          final rules = List<dynamic>.from(
                            rule['rules'] as List,
                          );
                          rules[i] = value;
                          set('rules', rules);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove condition',
                      onPressed: (rule['rules'] as List).length <= 1
                          ? null
                          : () {
                              final rules = List<dynamic>.from(
                                rule['rules'] as List,
                              )..removeAt(i);
                              set('rules', rules);
                            },
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                    ),
                  ],
                ),
              TextButton.icon(
                onPressed: () => set('rules', [
                  ...(rule['rules'] as List),
                  {'op': 'all'},
                ]),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add condition'),
              ),
            ],
            if (op == 'not')
              _RuleEditor(
                app: app,
                rule: asMap(rule['rule']),
                onChanged: (r) => set('rule', r),
              ),
            if (op == 'text') ...[
              dropdown(
                value: '${rule['field']}',
                label: 'Field',
                choices: const {'title': 'Title', 'notes': 'Notes'},
                changed: (v) => set('field', v),
              ),
              const SizedBox(height: 10),
              dropdown(
                value: '${rule['comparison']}',
                label: 'Comparison',
                choices: const {
                  'contains': 'Contains',
                  'equals': 'Equals',
                  'starts_with': 'Starts with',
                  'ends_with': 'Ends with',
                  'not_contains': 'Does not contain',
                  'not_equals': 'Does not equal',
                },
                changed: (v) => set('comparison', v),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: '${rule['value'] ?? ''}',
                decoration: const InputDecoration(
                  labelText: 'Text (including numbers)',
                ),
                onChanged: (v) => set('value', v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Case sensitive'),
                value: rule['case_sensitive'] == true,
                onChanged: (v) => set('case_sensitive', v),
              ),
            ],
            if (op == 'tag') ...[
              if (documentValues(app, 'tags').isEmpty)
                const Text('Create a tag using “New tag…” below.'),
              dropdown(
                value: intValue(rule['tag_id']),
                label: 'Tag',
                choices: {
                  for (final tag in documentValues(app, 'tags'))
                    intValue(tag['id']): '${tag['name']} (#${tag['id']})',
                },
                changed: (v) => set('tag_id', v),
              ),
            ],
            if (op == 'folder') ...[
              dropdown(
                value: intValue(rule['folder_id']),
                label: 'Container',
                choices: {
                  if (itemById(app, intValue(rule['folder_id'])).isEmpty &&
                      (app.document?['deleted_item_ids'] as List? ?? [])
                          .contains(intValue(rule['folder_id'])))
                    intValue(rule['folder_id']):
                        'Deleted container (#${rule['folder_id']})',
                  for (final item in documentValues(app, 'items'))
                    intValue(item['id']): '${item['title']} (#${item['id']})',
                },
                changed: (v) => set('folder_id', v),
              ),
              if (itemById(app, intValue(rule['folder_id'])).isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'This container was deleted. Replace it or remove this rule.',
                    style: TextStyle(color: Color(0xff8a5b00)),
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Include all descendant levels'),
                value: rule['recursive'] != false,
                onChanged: (v) => set('recursive', v),
              ),
            ],
            if (op == 'due') ...[
              dropdown(
                value: '${rule['comparison']}',
                label: 'Comparison',
                choices: const {
                  'before': 'Before',
                  'on': 'On',
                  'after': 'After',
                  'on_or_before': 'On or before',
                  'on_or_after': 'On or after',
                  'is_set': 'Has a due date',
                  'is_not_set': 'No due date',
                },
                changed: (v) => onChanged({
                  ...rule,
                  'comparison': v,
                  'value': ['is_set', 'is_not_set'].contains(v)
                      ? null
                      : rule['value'] ?? dateText(DateTime.now()),
                }),
              ),
              if (!['is_set', 'is_not_set'].contains(rule['comparison']))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.tryParse('${rule['value']}') ??
                            DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(9999),
                      );
                      if (selected != null) set('value', dateText(selected));
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text('${rule['value']}'),
                  ),
                ),
            ],
            if (op == 'priority') ...[
              dropdown(
                value: '${rule['comparison']}',
                label: 'Comparison',
                choices: const {'eq': 'Is', 'ge': 'At least', 'le': 'At most'},
                changed: (v) => set('comparison', v),
              ),
              const SizedBox(height: 10),
              dropdown(
                value: intValue(rule['value']),
                label: 'Priority',
                choices: {for (var i = 0; i < 4; i++) i: priorityNames[i]},
                changed: (v) => set('value', v),
              ),
            ],
            if (op == 'kind')
              dropdown(
                value: '${rule['kind']}',
                label: 'Type',
                choices: const {'task': 'Task', 'folder': 'Folder'},
                changed: (v) => set('kind', v),
              ),
            if (op == 'completed')
              dropdown(
                value: rule['value'] == true,
                label: 'State',
                choices: const {false: 'Unfinished', true: 'Completed'},
                changed: (v) => set('value', v),
              ),
            if (op == 'all')
              const Text(
                'Every item can appear in this view.',
                style: TextStyle(color: Color(0xff7b8999), fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
