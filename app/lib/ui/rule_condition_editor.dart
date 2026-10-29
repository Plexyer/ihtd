import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'item_editor.dart' show showNewTag;
import 'priority_icon.dart';
import 'shared.dart';

const ruleKinds = {
  'text': 'Title or notes',
  'tag': 'Has tag',
  'folder': 'Inside folder/task',
  'due': 'Due date',
  'priority': 'Priority',
  'kind': 'Item type',
  'completed': 'Task completion',
  'all': 'All items',
  'and': 'AND',
  'or': 'OR',
  'xor': 'Exactly one (XOR)',
  'not': 'NOT',
};

Map<String, dynamic> initialCondition(String op) => switch (op) {
  'text' => {
    'op': op,
    'field': 'title',
    'comparison': 'contains',
    'value': '',
    'case_sensitive': false,
  },
  'tag' => {'op': op, 'tag_id': 0},
  'folder' => {'op': op, 'folder_id': 0, 'recursive': true},
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

String _referenceName(AppController app, Map<String, dynamic> rule) {
  final tag = rule['op'] == 'tag';
  final id = intValue(rule[tag ? 'tag_id' : 'folder_id']);
  final value = asMap(asMap(app.document?[tag ? 'tags' : 'items'])['$id']);
  if (value.isNotEmpty) {
    final name = '${value[tag ? 'name' : 'title']}';
    final duplicates =
        documentValues(
          app,
          tag ? 'tags' : 'items',
        ).where((other) => '${other[tag ? 'name' : 'title']}' == name).length >
        1;
    return duplicates ? '$name (#$id)' : name;
  }
  if (!tag && (app.document?['deleted_item_ids'] as List? ?? []).contains(id)) {
    return 'Deleted container (#$id)';
  }
  return id == 0
      ? 'Choose ${tag ? 'tag' : 'container'}…'
      : 'Missing ${tag ? 'tag' : 'container'} (#$id)';
}

String conditionSummary(AppController app, Map<String, dynamic> r) {
  final comparison = '${r['comparison']}';
  return switch (r['op']) {
    'all' => 'All items',
    'text' =>
      '${r['field'] == 'notes' ? 'Notes' : 'Title'} ${{'contains': 'contains', 'equals': 'equals', 'starts_with': 'starts with', 'ends_with': 'ends with', 'not_contains': 'does not contain', 'not_equals': 'does not equal'}[comparison] ?? comparison} “${r['value'] ?? ''}”${r['case_sensitive'] == true ? ' · case sensitive' : ''}',
    'tag' => 'Tag is ${_referenceName(app, r)}',
    'folder' =>
      'Inside ${_referenceName(app, r)} · ${r['recursive'] == false ? 'direct children' : 'including subtasks'}',
    'due' => switch (comparison) {
      'is_set' => 'Has a due date',
      'is_not_set' => 'Has no due date',
      _ =>
        'Due ${{'before': 'before', 'on': 'on', 'after': 'after', 'on_or_before': 'on or before', 'on_or_after': 'on or after'}[comparison] ?? comparison} ${r['value']}',
    },
    'priority' =>
      'Priority is ${{'eq': '', 'ge': 'at least ', 'le': 'at most '}[comparison] ?? ''}${priorityLabel(r['value'])}',
    'kind' => 'Item type is ${r['kind'] == 'folder' ? 'Folder' : 'Task'}',
    'completed' =>
      'Completion is ${r['value'] == true ? 'Completed' : 'Unfinished'}',
    _ => 'Unknown condition (${r['op']})',
  };
}

Future<Map<String, dynamic>?> editCondition(
  BuildContext context,
  AppController app,
  Map<String, dynamic> rule,
  DocumentEditIdentity identity,
) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _ConditionDialog(app: app, initial: rule, identity: identity),
);

class _ConditionDialog extends StatefulWidget {
  const _ConditionDialog({
    required this.app,
    required this.initial,
    required this.identity,
  });
  final AppController app;
  final Map<String, dynamic> initial;
  final DocumentEditIdentity identity;
  @override
  State<_ConditionDialog> createState() => _ConditionDialogState();
}

class _ConditionDialogState extends State<_ConditionDialog> {
  late Map<String, dynamic> rule;
  String? error;
  @override
  void initState() {
    super.initState();
    rule = asMap(jsonDecode(jsonEncode(widget.initial)));
  }

  void done() {
    final app = widget.app;
    final op = rule['op'];
    final key = op == 'tag' ? 'tag_id' : 'folder_id';
    if (op == 'tag' || op == 'folder') {
      final id = intValue(rule[key]);
      final exists = asMap(app.document?[op == 'tag' ? 'tags' : 'items'])
          .containsKey('$id');
      final deleted =
          op == 'folder' &&
          (app.document?['deleted_item_ids'] as List? ?? []).contains(id);
      if (!exists && !deleted) {
        setState(
          () => error =
              'Choose a ${op == 'tag' ? 'tag' : 'container'} before continuing.',
        );
        return;
      }
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) => EditorDialog(
    title: Text('Edit ${ruleKinds[rule['op']] ?? 'condition'}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConditionFields(
          app: widget.app,
          rule: rule,
          identity: widget.identity,
          onChanged: (value) => setState(() {
            // Callbacks may fire before the next frame rebuilds the fields.
            // Merge patches into current state so a checkbox cannot restore
            // the previous text value captured by an older widget closure.
            rule = {...rule, ...value};
            if (rule['op'] == 'due' && value.containsKey('comparison')) {
              rule['value'] =
                  ['is_set', 'is_not_set'].contains(rule['comparison'])
                  ? null
                  : rule['value'] ?? dateText(DateTime.now());
            }
            error = null;
          }),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: done, child: const Text('Done')),
    ],
  );
}

Future<int?> _chooseReference(
  BuildContext context,
  AppController app,
  String op,
) => showDialog<int>(
  context: context,
  builder: (_) => _ReferencePicker(app: app, tag: op == 'tag'),
);

class _ReferencePicker extends StatefulWidget {
  const _ReferencePicker({required this.app, required this.tag});
  final AppController app;
  final bool tag;
  @override
  State<_ReferencePicker> createState() => _ReferencePickerState();
}

class _ReferencePickerState extends State<_ReferencePicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final values = documentValues(widget.app, widget.tag ? 'tags' : 'items')
        .where(
          (value) => '${value[widget.tag ? 'name' : 'title']} #${value['id']}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return EditorDialog(
      title: Text('Choose ${widget.tag ? 'tag' : 'container'}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Search'),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          if (values.isEmpty) const Text('No matches.'),
          for (final value in values)
            ListTile(
              key: ValueKey('reference-${value['id']}'),
              title: Text('${value[widget.tag ? 'name' : 'title']}'),
              subtitle: Text(
                '#${value['id']}${widget.tag ? '' : ' · ${value['kind']}'}',
              ),
              onTap: () => Navigator.pop(context, intValue(value['id'])),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ConditionFields extends StatelessWidget {
  const _ConditionFields({
    required this.app,
    required this.rule,
    required this.identity,
    required this.onChanged,
  });
  final AppController app;
  final Map<String, dynamic> rule;
  final DocumentEditIdentity identity;
  final ValueChanged<Map<String, dynamic>> onChanged;
  void set(String key, dynamic value) => onChanged({key: value});
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
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (op == 'tag' || op == 'folder') ...[
            OutlinedButton.icon(
              key: const ValueKey('choose-rule-reference'),
              onPressed: () async {
                final id = await _chooseReference(context, app, op);
                if (id != null && context.mounted) {
                  set(op == 'tag' ? 'tag_id' : 'folder_id', id);
                }
              },
              icon: Icon(
                op == 'tag' ? Icons.label_outline : Icons.folder_outlined,
              ),
              label: Text(_referenceName(app, rule)),
            ),
            if (op == 'tag') ...[
              TextButton.icon(
                onPressed: () async {
                  final id = await showNewTag(
                    context,
                    app,
                    expectedDocument: identity,
                  );
                  if (id != null && context.mounted) set('tag_id', id);
                },
                icon: const Icon(Icons.add),
                label: const Text('Create tag…'),
              ),
              const Text(
                'Creating a tag saves it to the collection, even if you cancel this view.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (op == 'folder') ...[
              if ((app.document?['deleted_item_ids'] as List? ?? []).contains(
                intValue(rule['folder_id']),
              ))
                const Text(
                  'This container was deleted. Replace it or remove this rule.',
                  style: TextStyle(color: Color(0xff8a5b00)),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include all descendant levels'),
                value: rule['recursive'] != false,
                onChanged: (v) => set('recursive', v),
              ),
            ],
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
              changed: (v) => set('comparison', v),
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
            DropdownButtonFormField<int>(
              key: ValueKey('Priority-${rule['value']}'),
              initialValue: intValue(rule['value']),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: [
                for (var p = 0; p < 4; p++)
                  DropdownMenuItem(
                    value: p,
                    child: PriorityChoice(priority: p),
                  ),
              ],
              onChanged: (v) => set('value', v ?? 0),
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
          if (op == 'all') const Text('Every item can match this condition.'),
        ],
      ),
    );
  }
}
