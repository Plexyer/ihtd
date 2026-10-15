import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'shared.dart';
import 'editor_dialog.dart';
import 'item_removal.dart';

class ItemEditor extends StatefulWidget {
  const ItemEditor({super.key, required this.app});
  final AppController app;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final title = TextEditingController();
  final notes = TextEditingController();
  int? id;
  String? due;
  int priority = 0;
  Set<int> tags = {};
  Timer? timer;
  bool dirty = false;
  int generation = 0;
  Map<String, dynamic> baseItem = {};
  String? localError;
  bool savingDraft = false;
  Future<bool> _flush() async {
    await _save();
    return !dirty;
  }

  @override
  void initState() {
    super.initState();
    _load();
    widget.app.flushDraft = _flush;
  }

  @override
  void didUpdateWidget(covariant ItemEditor old) {
    super.didUpdateWidget(old);
    if (id != widget.app.selectedItemId) {
      if (dirty) _save();
      _load();
    } else if (!dirty) {
      _load();
    }
  }

  void _load() {
    id = widget.app.selectedItemId;
    final item = itemById(widget.app, id ?? -1);
    baseItem = Map.of(item);
    title.text = '${item['title'] ?? ''}';
    notes.text = '${item['notes'] ?? ''}';
    due = item['due_date'] as String?;
    priority = intValue(item['priority']);
    tags = (item['tag_ids'] as List? ?? []).map((e) => intValue(e)).toSet();
    dirty = false;
    localError = null;
  }

  void _change() {
    generation++;
    dirty = true;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 650), _save);
    setState(() {});
  }

  Future<void> _save() async {
    while (savingDraft) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    savingDraft = true;
    try {
      await _persist();
    } finally {
      savingDraft = false;
    }
  }

  Future<void> _persist() async {
    timer?.cancel();
    if (!dirty || id == null) return;
    if (title.text.trim().isEmpty) {
      if (mounted) {
        setState(
          () =>
              localError = 'Enter a title before saving or leaving this item.',
        );
      }
      return;
    }
    final savedId = id;
    final version = generation;
    final current = itemById(widget.app, id!);
    if (current['title'] != baseItem['title'] ||
        current['notes'] != baseItem['notes'] ||
        current['due_date'] != baseItem['due_date'] ||
        current['priority'] != baseItem['priority'] ||
        '${current['tag_ids']}' != '${baseItem['tag_ids']}') {
      if (mounted) {
        setState(
          () => localError = 'This item changed externally. Load the latest saved values before editing again.',
        );
      }
      return;
    }
    final command = {
      'op': 'edit_item',
      'id': id,
      'title': title.text.trim(),
      'notes': notes.text,
      'due_date': due,
      'priority': priority,
      'tag_ids': tags.toList(),
      'expected_revision': widget.app.document?['revision'],
    };
    final result = await widget.app.dispatch(command);
    if (!mounted) return;
    if (id == savedId && result != null) {
      baseItem = Map.of(itemById(widget.app, id!));
    }
    if (id == savedId && generation == version) {
      setState(() {
        dirty = result == null;
        localError = result == null ? widget.app.error : null;
      });
    }
  }

  Future<void> _preference(String key, dynamic value) async {
    final view = asMap(
      asMap(widget.app.document?['views'])['${widget.app.selectedViewId}'],
    );
    final pref = <String, dynamic>{
      'hide_completed': null,
      'inherit_hide_completed': false,
      'folder_hidden': false,
      'reappear_on_new': false,
      ...asMap(asMap(view['preferences'])['$id']),
      key: value,
    };
    await widget.app.dispatch({
      'op': 'set_preferences',
      'view_id': widget.app.selectedViewId,
      'item_id': id,
      'preferences': pref,
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    if (dirty && !savingDraft) _persist();
    if (widget.app.flushDraft == _flush) widget.app.flushDraft = null;
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final item = itemById(app, id ?? -1);
    if (item.isEmpty) return const SizedBox.shrink();
    final folder = item['kind'] == 'folder';
    final info = asMap(app.completion['$id']);
    final enforcers = (info['enforcing_ancestor_ids'] as List? ?? []);
    final view = asMap(asMap(app.document?['views'])['${app.selectedViewId}']);
    final pref = asMap(asMap(view['preferences'])['$id']);
    final links = (app.document?['links'] as List? ?? []).map(asMap).toList();
    final parents = links
        .where((l) => l['child'] == id)
        .map((l) => intValue(l['parent']))
        .toList();
    final children = links.where((l) => l['parent'] == id).toList();
    return Material(
      color: const Color(0xfff8fafc),
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  '${folder ? 'FOLDER' : 'TASK'}  #$id',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Color(0xff7b8999),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close details',
                onPressed: () => app.selectItem(null),
                icon: const Icon(Icons.close, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            onChanged: (_) => _change(),
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            onChanged: (_) => _change(),
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  dirty ? 'Saving changes…' : 'Changes saved automatically',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xff788899),
                  ),
                ),
              ),
              if (dirty)
                TextButton(onPressed: _save, child: const Text('Save now')),
            ],
          ),
          if (localError != null)
            Text(
              localError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          if (localError != null)
            TextButton(
              onPressed: () => setState(_load),
              child: const Text('Load latest saved values'),
            ),
          const SectionLabel('Details'),
          OutlinedButton.icon(
            onPressed: () async {
              final value = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(due ?? '') ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(9999),
              );
              if (value != null && mounted) {
                due = dateText(value);
                _change();
              }
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 17),
            label: Text(due ?? 'Set due date'),
          ),
          if (due != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  due = null;
                  _change();
                },
                child: const Text('Clear due date'),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: priority,
            key: ValueKey('priority-$id-$priority'),
            decoration: const InputDecoration(labelText: 'Priority'),
            items: [
              for (var p = 0; p < 4; p++)
                DropdownMenuItem(value: p, child: Text(priorityNames[p])),
            ],
            onChanged: (v) {
              priority = v ?? 0;
              _change();
            },
          ),
          SectionLabel(
            'Tags',
            trailing: IconButton(
              tooltip: 'Create tag',
              onPressed: () async {
                final tag = await showNewTag(context, app);
                if (tag != null && mounted) {
                  tags.add(tag);
                  _change();
                }
              },
              icon: const Icon(Icons.add, size: 18),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in documentValues(app, 'tags'))
                FilterChip(
                  label: Text('${tag['name']}'),
                  selected: tags.contains(intValue(tag['id'])),
                  onSelected: (v) {
                    if (v) {
                      tags.add(intValue(tag['id']));
                    } else {
                      tags.remove(intValue(tag['id']));
                    }
                    _change();
                  },
                ),
            ],
          ),
          if (!folder) ...[
            const SectionLabel('Completion'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Automatic completion',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                enforcers.isEmpty
                    ? 'Complete when all descendant tasks finish'
                    : 'Required by task IDs ${enforcers.join(', ')}',
                style: const TextStyle(fontSize: 12),
              ),
              value: info['effective_auto'] == true,
              onChanged: (value) => app.dispatch({
                'op': 'set_auto_complete',
                'id': id,
                'enabled': value,
              }),
            ),
            if (enforcers.isNotEmpty)
              const Text(
                'Turn it off on every enforcing ancestor before disabling it here.',
                style: TextStyle(fontSize: 12, color: Color(0xff7b8999)),
              ),
          ],
          const SectionLabel('Visibility in this view'),
          if (folder) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Hide from unfinished',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Keep this folder in the completed view',
                style: TextStyle(fontSize: 12),
              ),
              value: pref['folder_hidden'] == true,
              onChanged: (v) => _preference('folder_hidden', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Reappear for new subtasks',
                style: TextStyle(fontSize: 14),
              ),
              value: pref['reappear_on_new'] == true,
              onChanged: (v) => _preference('reappear_on_new', v),
            ),
          ],
          if (children.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(
                'hide-$id-${app.selectedViewId}-${pref['hide_completed']}',
              ),
              initialValue: pref['hide_completed'] == null
                  ? 'inherit'
                  : pref['hide_completed'] == true
                  ? 'hide'
                  : 'show',
              decoration: const InputDecoration(
                labelText: 'Completed children',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'inherit',
                  child: Text('Use inherited/default setting'),
                ),
                DropdownMenuItem(
                  value: 'hide',
                  child: Text('Hide completed children'),
                ),
                DropdownMenuItem(
                  value: 'show',
                  child: Text('Keep completed children'),
                ),
              ],
              onChanged: (v) => _preference(
                'hide_completed',
                v == 'inherit' ? null : v == 'hide',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Let descendants inherit',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Their own settings can override this',
                style: TextStyle(fontSize: 12),
              ),
              value: pref['inherit_hide_completed'] == true,
              onChanged: (v) => _preference('inherit_hide_completed', v),
            ),
          ],
          SectionLabel('Subitems (${children.length})'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showCreateItem(context, app, parentId: id),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Task'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    showCreateItem(context, app, parentId: id, kind: 'folder'),
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('Folder'),
              ),
              TextButton(
                onPressed: () => showLinkItem(context, app, id!),
                child: const Text('Link existing…'),
              ),
            ],
          ),
          SectionLabel(
            'Placements (${asMap(app.placements['$id'])['count'] ?? 0})',
          ),
          for (final parent in [
            if (asMap(app.placements['$id'])['root'] == true) null,
            ...parents,
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                parent == null
                    ? 'Top level'
                    : '${itemById(app, parent)['title']}',
              ),
              subtitle: parent == null ? null : Text('#$parent'),
              onTap: parent == null ? null : () => app.selectItem(parent),
              trailing: TextButton.icon(
                key: ValueKey('remove-$id-${parent ?? 'root'}'),
                onPressed: app.busy
                    ? null
                    : () => removeItemPlacement(context, app, id!, parent),
                icon: Icon(
                  removalLabel(app, id!) == 'Unlink'
                      ? Icons.link_off
                      : Icons.delete_outline,
                  size: 18,
                ),
                label: Text(removalLabel(app, id!)),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              if (await confirmAction(
                context,
                title: folder ? 'Convert to task?' : 'Convert to folder?',
                message:
                    'The ID and all parent/child links stay the same. ${folder ? 'The new task starts unfinished.' : 'Task completion settings are removed.'}',
                action: 'Convert',
              )) {
                await _save();
                await app.dispatch({
                  'op': 'convert_kind',
                  'id': id,
                  'kind': folder ? 'task' : 'folder',
                });
              }
            },
            child: Text(
              folder ? 'Convert folder to task' : 'Convert task to folder',
            ),
          ),
        ],
      ),
    );
  }
}

Future<int?> showNewTag(
  BuildContext context,
  AppController app, {
  DocumentEditIdentity? expectedDocument,
}) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create tag'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Tag name'),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null) return null;
  final result = await app.dispatch({
    'op': 'add_tag',
    'name': name,
  }, expectedDocument: expectedDocument);
  return result?['id'] as int?;
}

Future<void> showLinkItem(
  BuildContext context,
  AppController app,
  int parent,
) async {
  final query = TextEditingController();
  int? selection;
  final selected = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Link an existing item'),
        content: SizedBox(
          width: 440,
          height: 370,
          child: Column(
            children: [
              TextField(
                controller: query,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search title or ID',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in documentValues(app, 'items').where(
                      (i) =>
                          i['id'] != parent &&
                          '${i['title']} #${i['id']}'.toLowerCase().contains(
                            query.text.toLowerCase(),
                          ),
                    ))
                      ListTile(
                        selected: selection == item['id'],
                        title: Text('${item['title']}'),
                        subtitle: Text('#${item['id']} · ${item['kind']}'),
                        leading: Icon(
                          item['kind'] == 'folder'
                              ? Icons.folder_outlined
                              : Icons.task_alt,
                        ),
                        onTap: () =>
                            setState(() => selection = intValue(item['id'])),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selection == null
                ? null
                : () => Navigator.pop(context, selection),
            child: const Text('Link item'),
          ),
        ],
      ),
    ),
  );
  query.dispose();
  if (selected != null) {
    await app.dispatch({'op': 'link', 'parent': parent, 'child': selected});
  }
}

Future<void> showCreateItem(
  BuildContext context,
  AppController app, {
  int? parentId,
  String kind = 'task',
}) async {
  final defaults = await app.dispatch({
    'op': 'creation_defaults',
    'view_id': app.selectedViewId,
  });
  if (defaults == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _CreateDialog(
      app: app,
      defaults: defaults,
      parentId: parentId,
      kind: kind,
    ),
  );
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog({
    required this.app,
    required this.defaults,
    required this.kind,
    this.parentId,
  });
  final AppController app;
  final Map<String, dynamic> defaults;
  final String kind;
  final int? parentId;
  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  late final TextEditingController title, notes;
  late String kind;
  String? due;
  int priority = 0;
  Set<int> tags = {};
  int? parent;
  bool saving = false;
  bool completed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final d = widget.defaults;
    title = TextEditingController(text: d['title'] as String?);
    notes = TextEditingController(text: d['notes'] as String?);
    kind = d['kind'] as String? ?? widget.kind;
    due = d['due_date'] as String?;
    priority = intValue(d['priority']);
    tags = (d['tag_ids'] as List? ?? []).map((v) => intValue(v)).toSet();
    parent = widget.parentId;
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (title.text.trim().isEmpty) {
      setState(() => error = 'Enter a title.');
      return;
    }
    setState(() => saving = true);
    final result = await widget.app.dispatch({
      'op': 'add_item',
      'view_id': widget.app.selectedViewId,
      'kind': kind,
      'title': title.text.trim(),
      'notes': notes.text,
      'due_date': due,
      'priority': priority,
      'tag_ids': tags.toList(),
      'parent_id': parent,
      'completed': completed,
    });
    if (!mounted) return;
    if (result != null) {
      widget.app.selectItem(intValue(result['id']));
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
    title: Text(kind == 'folder' ? 'New folder' : 'New task'),
    maxWidth: 500,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((widget.defaults['requirements'] as List? ?? []).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              (widget.defaults['requirements'] as List).join('\n'),
              style: const TextStyle(fontSize: 13, color: Color(0xff536f92)),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title *'),
          onSubmitted: (_) => create(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: kind,
          decoration: const InputDecoration(labelText: 'Item type'),
          items: const [
            DropdownMenuItem(value: 'task', child: Text('Task')),
            DropdownMenuItem(value: 'folder', child: Text('Folder')),
          ],
          onChanged: (v) => setState(() => kind = v ?? 'task'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(due ?? '') ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(9999),
                  );
                  if (date != null) setState(() => due = dateText(date));
                },
                icon: const Icon(Icons.calendar_today, size: 17),
                label: Text(due ?? 'Choose due date'),
              ),
            ),
            if (due != null)
              IconButton(
                tooltip: 'Clear due date',
                onPressed: () => setState(() => due = null),
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: [
            for (var p = 0; p < 4; p++)
              DropdownMenuItem(value: p, child: Text(priorityNames[p])),
          ],
          onChanged: (v) => setState(() => priority = v ?? 0),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: parent ?? 0,
          decoration: const InputDecoration(labelText: 'Parent placement'),
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: 0, child: Text('Top level')),
            for (final item in documentValues(widget.app, 'items'))
              DropdownMenuItem(
                value: intValue(item['id']),
                child: Text(
                  '${item['title']} (#${item['id']})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => parent = v == 0 ? null : v),
        ),
        SectionLabel(
          'Tags',
          trailing: IconButton(
            tooltip: 'Create tag',
            onPressed: () async {
              final id = await showNewTag(context, widget.app);
              if (id != null && mounted) setState(() => tags.add(id));
            },
            icon: const Icon(Icons.add),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in documentValues(widget.app, 'tags'))
              FilterChip(
                label: Text('${tag['name']}'),
                selected: tags.contains(intValue(tag['id'])),
                onSelected: (v) => setState(() {
                  if (v) {
                    tags.add(intValue(tag['id']));
                  } else {
                    tags.remove(intValue(tag['id']));
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'The item must match this view’s complete filter before it can be created.',
          style: TextStyle(fontSize: 12, color: Color(0xff7b8999)),
        ),
        if (kind == 'task')
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Create as completed'),
            value: completed,
            onChanged: (v) => setState(() => completed = v ?? false),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : create,
        child: Text(saving ? 'Creating…' : 'Create'),
      ),
    ],
  );
}
