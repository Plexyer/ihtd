import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_controller.dart';
import '../services/item_draft.dart';
import 'shared.dart';
import 'item_removal.dart';
import 'link_copy.dart';
import 'guarded_editor_route.dart';
import 'editor_dialog.dart';
import 'collection_settings.dart';
import 'sort_settings.dart';
import 'priority_icon.dart';
import 'tag_selector.dart';

Future<DraftExitChoice> chooseItemDraftExit(
  BuildContext context,
  ItemDraft draft,
  DraftExitReason reason,
) async =>
    await showDialog<DraftExitChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          draft.isNew
              ? 'Create this ${draft.values['kind']}?'
              : 'Save unfinished changes?',
        ),
        content: Text(
          draft.isNew
              ? 'Create this item, discard the unfinished draft, or keep editing?'
              : 'Save your changes, discard them, or keep editing?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, DraftExitChoice.keepEditing),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, DraftExitChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DraftExitChoice.save),
            child: Text(draft.isNew ? 'Create' : 'Save'),
          ),
        ],
      ),
    ) ??
    DraftExitChoice.keepEditing;

Future<void> showItemDraftDialog(
  BuildContext context,
  AppController app,
) async {
  final draft = app.itemDraft;
  if (draft == null || app.editorOverlaySession == draft.sessionId) return;
  app.editorOverlaySession = draft.sessionId;
  app.notifyListeners();
  late GuardedEditorRoute route;
  bool closing = false;
  void changed() {
    if (app.itemDraft?.sessionId != draft.sessionId && !closing) {
      closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  route = GuardedEditorRoute(
    context: context,
    outside: () async {
      await app.resolveItemDraft(reason: DraftExitReason.outside, close: true);
    },
    back: () async {
      await app.resolveItemDraft(reason: DraftExitReason.back, close: true);
    },
    content: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: BoxConstraints(
        maxWidth: draft.isNew ? 500 : 620,
        maxHeight: 760,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: constraints.maxHeight,
          child: ListenableBuilder(
            listenable: app,
            builder: (_, _) => ItemEditor(app: app),
          ),
        ),
      ),
    ),
  );
  app.addListener(changed);
  try {
    await Navigator.of(context).push(route);
  } finally {
    app.removeListener(changed);
    if (app.editorOverlaySession == draft.sessionId) {
      app.editorOverlaySession = null;
    }
    app.notifyListeners();
  }
}

Future<void> showRecoveredItemDrafts(
  BuildContext context,
  AppController app,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: const Text('Unfinished drafts'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (app.itemDrafts.unreadableCount > 0)
                  const Text(
                    'Some draft files could not be read. Their original files have been retained on this device.',
                  ),
                const Text(
                  'These drafts were retained on this device. They have not automatically replaced saved items.',
                ),
                for (final draft in app.recoveredDrafts)
                  ListTile(
                    title: Text(
                      '${draft.values['title']}'.isEmpty
                          ? 'Untitled ${draft.values['kind']}'
                          : '${draft.values['title']}',
                    ),
                    subtitle: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: app.busy
                              ? null
                              : () async {
                                  if (await app.restoreItemDraft(draft) &&
                                      context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                          child: const Text('Restore'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await app.discardRecoveredItemDraft(draft);
                          },
                          child: const Text('Discard draft'),
                        ),
                        TextButton(
                          onPressed: () => app.exportItemDraft(draft),
                          child: const Text('Export draft…'),
                        ),
                      ],
                    ),
                  ),
                if (app.error != null)
                  Text(
                    app.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
        ],
      ),
    ),
  );
}

class ItemEditor extends StatefulWidget {
  const ItemEditor({super.key, required this.app});
  final AppController app;
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final title = TextEditingController(), notes = TextEditingController();
  String? session;
  int formRevision = -1;
  ItemDraft? get draft => widget.app.itemDraft;
  Future<DraftExitChoice> _choose(ItemDraft d, DraftExitReason r) => mounted
      ? chooseItemDraftExit(context, d, r)
      : Future.value(DraftExitChoice.keepEditing);
  @override
  void initState() {
    super.initState();
    widget.app.ensureItemDraft();
    widget.app.chooseDraftExit ??= _choose;
    _load();
  }

  void _load() {
    final d = draft;
    if (d == null) return;
    session = d.sessionId;
    formRevision = d.formRevision;
    if (title.text != d.values['title']) title.text = '${d.values['title']}';
    if (notes.text != d.values['notes']) notes.text = '${d.values['notes']}';
  }

  @override
  void didUpdateWidget(covariant ItemEditor old) {
    super.didUpdateWidget(old);
    if (session != draft?.sessionId || formRevision != draft?.formRevision) {
      _load();
    }
  }

  @override
  void dispose() {
    if (widget.app.chooseDraftExit == _choose) {
      widget.app.chooseDraftExit = null;
    }
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _preference(String key, dynamic value) async {
    final d = draft;
    if (d == null || d.isNew) return;
    final app = widget.app;
    final view = asMap(asMap(app.document?['views'])['${d.viewId}']);
    final pref = <String, dynamic>{
      'hide_completed': null,
      'inherit_hide_completed': false,
      'folder_hidden': false,
      'reappear_on_new': false,
      ...asMap(asMap(view['preferences'])['${d.itemId}']),
      key: value,
    };
    await app.dispatch(
      {
        'op': 'set_preferences',
        'view_id': d.viewId,
        'item_id': d.itemId,
        'preferences': pref,
      },
      expectedDocument: (workingPath: d.ownerPath, documentId: d.documentId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, d = draft;
    if (d == null) return const SizedBox.shrink();
    final id = d.itemId, folder = d.values['kind'] == 'folder';
    final tags = List<int>.from(d.values['tag_ids'] as List);
    final due = d.values['due_date'] as String?;
    final priority = intValue(d.values['priority']);
    final info = asMap(app.completion['$id']);
    final enforcers = info['enforcing_ancestor_ids'] as List? ?? [];
    final view = asMap(asMap(app.document?['views'])['${d.viewId}']);
    final pref = asMap(asMap(view['preferences'])['$id']);
    final links = (app.document?['links'] as List? ?? []).map(asMap).toList();
    final parents = links
        .where((l) => l['child'] == id)
        .map((l) => intValue(l['parent']))
        .toList();
    final children = links.where((l) => l['parent'] == id).toList();
    final disabled = app.savingItemDraft || app.discardingItemDraft || app.busy;
    void change(String key, dynamic value) =>
        app.changeItemDraft(key, value, sessionId: d.sessionId);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            ModalRoute.of(context)?.isCurrent == true) {
          unawaited(
            app.resolveItemDraft(reason: DraftExitReason.back, close: true),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: const Color(0xfff8fafc),
        child: EditorFormLayout(
          title: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                TextButton(
                  onPressed: disabled ? null : () => app.discardItemDraft(),
                  child: const Text('Cancel'),
                ),
                Expanded(
                  child: Text(
                    d.isNew
                        ? 'New ${folder ? 'folder' : 'task'}'
                        : '${folder ? 'FOLDER' : 'TASK'}  #$id',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (!d.isNew)
                  FilledButton(
                    onPressed: disabled ? null : () => app.saveItemDraft(),
                    child: const Text('Save'),
                  )
                else
                  const SizedBox(width: 64),
              ],
            ),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.isNew &&
                  (d.values['requirements'] as List? ?? []).isNotEmpty)
                Text((d.values['requirements'] as List).join('\n')),
              if (app.draftStorageError != null)
                Text(
                  app.draftStorageError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (d.error != null) ...[
                Text(
                  d.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (!d.isNew)
                  TextButton(
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        title: 'Discard this draft?',
                        message: 'Load the latest saved values and discard this unfinished draft?',
                        action: 'Load latest',
                      )) {
                        await app.reloadItemDraft();
                      }
                    },
                    child: const Text('Load latest saved values'),
                  ),
              ],
              TextField(
                controller: title,
                autofocus: d.isNew,
                readOnly:
                    app.savingItemDraft ||
                    app.discardingItemDraft ||
                    app.switchingCollection,
                onChanged: (v) => change('title', v),
                onSubmitted: (_) => app.saveItemDraft(),
                decoration: InputDecoration(
                  labelText: d.isNew ? 'Title *' : 'Title',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              if (d.isNew) ...[
                DropdownButtonFormField<String>(
                  initialValue: '${d.values['kind']}',
                  decoration: const InputDecoration(labelText: 'Item type'),
                  items: const [
                    DropdownMenuItem(value: 'task', child: Text('Task')),
                    DropdownMenuItem(value: 'folder', child: Text('Folder')),
                  ],
                  onChanged: disabled
                      ? null
                      : (v) {
                          change('kind', v);
                          if (v == 'folder') {
                            change('auto_complete', false);
                            change('completed', false);
                          }
                        },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: notes,
                readOnly:
                    app.savingItemDraft ||
                    app.discardingItemDraft ||
                    app.switchingCollection,
                onChanged: (v) => change('notes', v),
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                d.dirty
                    ? app.retainingItemDraft
                          ? 'Retaining draft on this device…'
                          : app.draftStorageError == null
                          ? 'Unsaved changes — draft retained on this device'
                          : 'Unsaved changes — draft recovery is unavailable'
                    : 'No unsaved changes',
                style: const TextStyle(fontSize: 12, color: Color(0xff788899)),
              ),
              const SectionLabel('Details'),
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.tryParse(due ?? '') ?? DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(9999),
                        );
                        if (date != null &&
                            mounted &&
                            identical(d, app.itemDraft)) {
                          change('due_date', dateText(date));
                        }
                      },
                icon: const Icon(Icons.calendar_today_outlined, size: 17),
                label: Text(
                  due ?? (d.isNew ? 'Choose due date' : 'Set due date'),
                ),
              ),
              if (due != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: disabled ? null : () => change('due_date', null),
                    child: const Text('Clear due date'),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('${d.sessionId}-${d.formRevision}-$priority'),
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: [
                  for (var p = 0; p < 4; p++)
                    DropdownMenuItem(
                      value: p,
                      child: PriorityChoice(priority: p),
                    ),
                ],
                onChanged: disabled ? null : (v) => change('priority', v ?? 0),
              ),
              if (d.isNew) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: d.parentId ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Parent placement',
                  ),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Top level')),
                    for (final item in documentValues(app, 'items'))
                      DropdownMenuItem(
                        value: intValue(item['id']),
                        child: Text(
                          '${item['title']} (#${item['id']})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: disabled
                      ? null
                      : (v) => change('parent_id', v == 0 ? null : v),
                ),
              ],
              SectionLabel(
                'Tags',
                trailing: IconButton(
                  tooltip: 'Create tag',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: disabled
                      ? null
                      : () async {
                          final tag = await showNewTag(
                            context,
                            app,
                            expectedDocument: (
                              workingPath: d.ownerPath,
                              documentId: d.documentId,
                            ),
                          );
                          if (tag != null &&
                              mounted &&
                              identical(d, app.itemDraft)) {
                            change(
                              'tag_ids',
                              ({...tags, tag}.toList()..sort()),
                            );
                          }
                        },
                ),
              ),
              TagSelector(
                key: ValueKey('tag-selector-${d.sessionId}'),
                app: app,
                sessionId: d.sessionId,
                selected: tags,
                disabled: disabled,
              ),
              if (!folder) ...[
                const SectionLabel('Completion'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic completion'),
                  subtitle: Text(
                    enforcers.isEmpty
                        ? 'Complete when all descendant tasks finish'
                        : 'Required by task IDs ${enforcers.join(', ')}',
                  ),
                  value:
                      d.values['auto_complete'] == true || enforcers.isNotEmpty,
                  onChanged: disabled || enforcers.isNotEmpty
                      ? null
                      : (v) => change('auto_complete', v),
                ),
                if (d.isNew)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Create as completed'),
                    value: d.values['completed'] == true,
                    onChanged: disabled
                        ? null
                        : (v) => change('completed', v ?? false),
                  ),
              ],
              if (!d.isNew) ...[
                OutlinedButton.icon(
                  onPressed: disabled
                      ? null
                      : () => showIndicatorSettings(
                          context,
                          app,
                          itemId: id!,
                          viewId: d.viewId,
                        ),
                  icon: const Icon(Icons.tune),
                  label: const Text('Summary indicator settings…'),
                ),
                SortControl(app: app, parent: id),
                const SectionLabel('Visibility in this view'),
                if (folder) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hide from unfinished'),
                    value: pref['folder_hidden'] == true,
                    onChanged: disabled
                        ? null
                        : (v) => _preference('folder_hidden', v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reappear for new subtasks'),
                    value: pref['reappear_on_new'] == true,
                    onChanged: disabled
                        ? null
                        : (v) => _preference('reappear_on_new', v),
                  ),
                ],
                if (children.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'hide-$id-${d.viewId}-${pref['hide_completed']}',
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
                    onChanged: disabled
                        ? null
                        : (v) => _preference(
                            'hide_completed',
                            v == 'inherit' ? null : v == 'hide',
                          ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Let descendants inherit'),
                    value: pref['inherit_hide_completed'] == true,
                    onChanged: disabled
                        ? null
                        : (v) => _preference('inherit_hide_completed', v),
                  ),
                ],
                SectionLabel('Subitems (${children.length})'),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: disabled
                          ? null
                          : () => showCreateItem(context, app, parentId: id),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Task'),
                    ),
                    OutlinedButton.icon(
                      onPressed: disabled
                          ? null
                          : () => showCreateItem(
                              context,
                              app,
                              parentId: id,
                              kind: 'folder',
                            ),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 16,
                      ),
                      label: const Text('Folder'),
                    ),
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => showLinkItem(context, app, id!),
                      child: const Text('Link / copy task to…'),
                    ),
                  ],
                ),
                SectionLabel('Parents and top-level placement'),
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
                    onTap: parent == null ? null : () => app.selectItem(parent),
                  ),
                if (hasMultipleAppearances(app, id!))
                  Text('Links: ${appearanceCount(app, id)}'),
                Text(
                  'Current place: ${(selectedOccurrence(app, id) ?? []).map((part) => '${itemById(app, part)['title']} (#$part)').join(' › ')}',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (hasMultipleAppearances(app, id))
                      TextButton.icon(
                        key: ValueKey('unlink-item-$id'),
                        onPressed: disabled
                            ? null
                            : () => removeSelectedItem(
                                context,
                                app,
                                id,
                                'unlink',
                              ),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Unlink'),
                      ),
                    TextButton.icon(
                      key: ValueKey('delete-item-$id'),
                      onPressed: disabled
                          ? null
                          : () =>
                                removeSelectedItem(context, app, id, 'delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: disabled
                      ? null
                      : () async {
                          if (!await app.finishDraft() || !context.mounted) {
                            return;
                          }
                          if (!await confirmAction(
                            context,
                            title: folder
                                ? 'Convert to task?'
                                : 'Convert to folder?',
                            message:
                                'The ID and all parent/child links stay the same. ${folder ? 'The new task starts unfinished.' : 'Task completion settings are removed.'}',
                            action: 'Convert',
                          )) {
                            return;
                          }
                          final result = await app.dispatch(
                            {
                              'op': 'convert_kind',
                              'id': id,
                              'kind': folder ? 'task' : 'folder',
                            },
                            expectedDocument: (
                              workingPath: d.ownerPath,
                              documentId: d.documentId,
                            ),
                          );
                          if (result != null) await app.reloadItemDraft();
                        },
                  child: Text(
                    folder
                        ? 'Convert folder to task'
                        : 'Convert task to folder',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (d.isNew)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: disabled ? null : () => app.saveItemDraft(),
                    child: const Text('Create'),
                  ),
                ),
              ),
          ],
        ),
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
  int source,
) => showLinkCopy(context, app, source);

Future<void> showCreateItem(
  BuildContext context,
  AppController app, {
  int? parentId,
  String kind = 'task',
}) async {
  if (!await app.finishDraft() || !context.mounted) return;
  final owner = app.editIdentity;
  final defaults = await app.dispatch({
    'op': 'creation_defaults',
    'view_id': app.selectedViewId,
  }, expectedDocument: owner);
  if (defaults == null || !context.mounted || app.editIdentity != owner) return;
  if (!await app.beginCreateDraft(defaults, parentId: parentId, kind: kind) ||
      !context.mounted) {
    return;
  }
  await showItemDraftDialog(context, app);
}
