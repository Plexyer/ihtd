import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'shared.dart';

String appearanceCount(AppController app, int id) =>
    '${app.appearances['$id'] ?? asMap(app.placements['$id'])['count'] ?? 1}';
bool hasMultipleAppearances(AppController app, int id) =>
    appearanceCount(app, id) != '1' && appearanceCount(app, id) != '0';
String removalLabel(AppController app, int id) =>
    hasMultipleAppearances(app, id) ? 'Unlink' : 'Delete';

/// Resolve a concrete hierarchy occurrence, preferring the one actually opened.
/// Details reached programmatically use a canonical path, shown in the controls.
List<int>? itemOccurrence(
  AppController app,
  int id,
  int? parent, {
  String? path,
}) {
  final supplied =
      path ?? (app.selectedItemId == id ? app.selectedItemPath : null);
  if (supplied != null) {
    final parts = supplied.split('/').map(int.tryParse).toList();
    if (parts.every((id) => id != null) &&
        parts.last == id &&
        (parts.length == 1
            ? parent == null
            : parts[parts.length - 2] == parent)) {
      return parts.cast<int>();
    }
  }
  if (parent == null && asMap(app.placements['$id'])['root'] == true) {
    return [id];
  }
  final target = parent ?? id;
  final children = <int, List<int>>{};
  final placed = <int>{};
  for (final raw in app.document?['links'] as List? ?? []) {
    final edge = asMap(raw),
        p = intValue(edge['parent']),
        c = intValue(edge['child']);
    (children[p] ??= []).add(c);
    placed.add(c);
  }
  final roots = <int>{
    ...((app.document?['root_order'] as List? ?? []).cast<int>()),
    ...documentValues(
      app,
      'items',
    ).map((i) => intValue(i['id'])).where((i) => !placed.contains(i)),
  };
  final previous = <int, int?>{for (final root in roots) root: null};
  final queue = roots.toList();
  for (var i = 0; i < queue.length; i++) {
    final node = queue[i];
    if (node == target) {
      final result = <int>[node];
      int? p = previous[node];
      while (p != null) {
        result.add(p);
        p = previous[p];
      }
      final found = result.reversed.toList();
      if (parent != null) {
        if (!(children[parent] ?? []).contains(id)) return null;
        found.add(id);
      }
      return found;
    }
    for (final c in children[node] ?? <int>[]) {
      if (!previous.containsKey(c)) {
        previous[c] = node;
        queue.add(c);
      }
    }
  }
  return null;
}

List<int>? selectedOccurrence(AppController app, int id) {
  if (app.selectedItemId == id && app.selectedItemPath != null) {
    final path = app.selectedItemPath!.split('/').map(int.tryParse).toList();
    if (path.isNotEmpty && path.every((id) => id != null) && path.last == id) {
      return path.cast<int>();
    }
  }
  return itemOccurrence(app, id, null);
}

Future<void> removeSelectedItem(
  BuildContext context,
  AppController app,
  int id,
  String action,
) async {
  final path = selectedOccurrence(app, id);
  if (path == null) return;
  await removeItemPlacement(
    context,
    app,
    id,
    path.length > 1 ? path[path.length - 2] : null,
    path: path.join('/'),
    action: action,
  );
}

Future<void> removeItemPlacement(
  BuildContext context,
  AppController app,
  int id,
  int? parent, {
  String? path,
  String? action,
}) async {
  final occurrence = itemOccurrence(app, id, parent, path: path);
  if (occurrence == null) return;
  final chosen =
      action ?? (hasMultipleAppearances(app, id) ? 'unlink' : 'delete');
  await app.performItemAction(
    occurrence,
    chosen,
    confirm: (preview) async {
      if (!context.mounted) return false;
      final blocking = preview['blocking_parent'] as int?;
      final deleted = (preview['deleted_ids'] as List? ?? []).cast<int>();
      final retained = (preview['retained_child_ids'] as List? ?? [])
          .cast<int>();
      final views = (preview['affected_view_ids'] as List? ?? []).cast<int>();
      final shared = '${preview['appearances']}' != '1';
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => EditorDialog(
              maxWidth: 520,
              title: Text(
                blocking != null
                    ? 'This child belongs to a linked parent'
                    : 'Delete “${itemById(app, id)['title']}”?',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (blocking != null) ...[
                    Text(
                      '“${itemById(app, blocking)['title']}” (#$blocking) is linked in multiple places. Unlinking this child directly would change those other appearances.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Create a full independent copy of this parent and all its children at the selected location, then delete the selected copied child and its copied descendants? Originals in other places stay untouched.',
                    ),
                  ] else ...[
                    if (shared)
                      const Text(
                        'Delete removes this task or folder everywhere. To remove it only from this place, cancel and choose Unlink instead.',
                      ),
                    Text(
                      deleted.length == 1
                          ? 'This will permanently delete this item.'
                          : 'This will permanently delete ${deleted.length} items, including children with no remaining appearance.',
                    ),
                    const SizedBox(height: 8),
                    for (final child in deleted.take(6))
                      Text('• ${itemById(app, child)['title']}  (#$child)'),
                    if (deleted.length > 6)
                      Text('… and ${deleted.length - 6} more'),
                    if (retained.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'These shared branches remain in their other places:',
                        ),
                      ),
                    for (final child in retained.take(6))
                      Text('• ${itemById(app, child)['title']}  (#$child)'),
                    if (retained.length > 6)
                      Text('… and ${retained.length - 6} more'),
                    if (views.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Views needing rule review: ${views.join(', ')}. The views will be kept.',
                        ),
                      ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    blocking != null
                        ? 'Copy parent and remove child'
                        : 'Delete',
                  ),
                ),
              ],
            ),
          ) ??
          false;
    },
  );
}
