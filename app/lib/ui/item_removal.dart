import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'shared.dart';

String removalLabel(AppController app, int id) =>
    intValue(asMap(app.placements['$id'])['count']) > 1 ? 'Unlink' : 'Delete';

Future<void> removeItemPlacement(
  BuildContext context,
  AppController app,
  int id,
  int? parent,
) async {
  final removed = await app.removePlacement(
    id,
    parent,
    confirmDelete: (preview) async {
      if (!context.mounted) return false;
      final deleted = (preview['deleted_ids'] as List)
          .map((id) => intValue(id))
          .toList();
      final retained = (preview['retained_child_ids'] as List)
          .map((id) => intValue(id))
          .toList();
      final views = (preview['affected_view_ids'] as List)
          .map((id) => asMap(asMap(app.document?['views'])['$id'])['name'])
          .toList();
      List<Widget> names(List<int> ids) => [
        for (final itemId in ids.take(6))
          Text('• ${itemById(app, itemId)['title']} (#$itemId)'),
        if (ids.length > 6) Text('… and ${ids.length - 6} more'),
      ];
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => EditorDialog(
              maxWidth: 480,
              title: Text('Delete “${itemById(app, id)['title']}”?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deleted.length == 1
                        ? 'This will permanently delete this item.'
                        : 'This will permanently delete ${deleted.length} items, including children with no remaining placement.',
                  ),
                  const SizedBox(height: 8),
                  ...names(deleted),
                  if (retained.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'These shared branches remain in their other places:',
                    ),
                    ...names(retained),
                  ],
                  if (parent != null &&
                      intValue(asMap(app.placements['$parent'])['count']) >
                          1) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'The parent is linked in multiple places. Its children are shared, so this removal affects every appearance.',
                    ),
                  ],
                  if (views.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Views needing rule review: ${views.join(', ')}. The views will be kept.',
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(dialogContext).colorScheme.error,
                    foregroundColor: Theme.of(dialogContext)
                        .colorScheme
                        .onError,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
    },
  );
  if (removed &&
      context.mounted &&
      app.selectedItemId == null &&
      itemById(app, id).isEmpty &&
      ModalRoute.of(context) is ModalBottomSheetRoute) {
    Navigator.of(context).pop();
  }
}
