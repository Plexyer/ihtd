import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'shared.dart';

class ItemPlacement {
  const ItemPlacement(this.documentId, this.id, this.parent);
  final String documentId;
  final int id;
  final int? parent;

  static int? parentFromPath(String path) {
    final parts = path.split('/');
    return parts.length < 2 ? null : int.parse(parts[parts.length - 2]);
  }
}

/// Native Flutter drag gestures keep pointer handling shared with Linux.
class ItemDragSource extends StatelessWidget {
  const ItemDragSource({
    super.key,
    required this.app,
    required this.row,
    required this.child,
  });
  final AppController app;
  final Map<String, dynamic> row;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = intValue(row['id']);
    final item = itemById(app, id);
    // Swipes scroll on phones; holding an item starts a move.
    final drag = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => LongPressDraggable<ItemPlacement>.new,
      _ => Draggable<ItemPlacement>.new,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: drag(
        key: ValueKey('drag-${row['path']}'),
        data: ItemPlacement(
          '${app.document?['document_id']}',
          id,
          ItemPlacement.parentFromPath('${row['path']}'),
        ),
        maxSimultaneousDrags: app.busy ? 0 : 1,
        allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xffe8f0fc),
          child: SizedBox(
            width: 260,
            child: ListTile(
              leading: Icon(
                item['kind'] == 'folder'
                    ? Icons.folder_outlined
                    : Icons.task_alt,
              ),
              title: Text(
                '${item['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Move item'),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: child),
        onDragUpdate: (details) {
          final scrollable = Scrollable.maybeOf(context);
          final box = scrollable?.context.findRenderObject();
          if (scrollable == null || box is! RenderBox) return;
          final y = box.globalToLocal(details.globalPosition).dy;
          final delta = y < 55
              ? -24.0
              : y > box.size.height - 55
              ? 24.0
              : 0.0;
          if (delta != 0) {
            final position = scrollable.position;
            position.jumpTo(
              (position.pixels + delta).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
          }
        },
        child: child,
      ),
    );
  }
}

class ItemDropTarget extends StatelessWidget {
  const ItemDropTarget({
    super.key,
    required this.app,
    required this.child,
    this.parent,
    this.before,
    this.targetPath,
    this.reorder = false,
  });
  final AppController app;
  final Widget child;
  final int? parent;
  final int? before;
  final String? targetPath;
  final bool reorder;

  bool accepts(ItemPlacement source) {
    if (app.busy ||
        source.documentId != app.document?['document_id'] ||
        source.id == parent ||
        source.id == before) {
      return false;
    }
    return true;
  }

  Future<void> move(ItemPlacement source) async {
    if (!await app.finishDraft() || !accepts(source)) return;
    final result = await app.dispatch({
      'op': 'move_item',
      'id': source.id,
      'source_parent': source.parent,
      'destination_parent': parent,
      'before': before,
      'expected_revision': app.document?['revision'],
    });
    if (result != null && targetPath != null) {
      app.expandedPaths.remove('!$targetPath');
      app.expandedPaths.add(targetPath!);
      await app.refreshRows();
      app.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) => DragTarget<ItemPlacement>(
    onWillAcceptWithDetails: (details) => accepts(details.data),
    onAcceptWithDetails: (details) => move(details.data),
    builder: (context, candidates, rejected) => Container(
      decoration: candidates.isEmpty
          ? null
          : BoxDecoration(
              color: const Color(0xffd7e7ff),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xff2763a5), width: 2),
            ),
      child: child,
    ),
  );
}

class PlacementRow extends StatelessWidget {
  const PlacementRow({
    super.key,
    required this.app,
    required this.row,
    required this.child,
  });
  final AppController app;
  final Map<String, dynamic> row;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final path = '${row['path']}';
    final parent = ItemPlacement.parentFromPath(path);
    return Column(
      children: [
        ItemDropTarget(
          key: ValueKey('before-$path'),
          app: app,
          parent: parent,
          before: intValue(row['id']),
          reorder: true,
          child: const SizedBox(height: 10, width: double.infinity),
        ),
        ItemDragSource(
          app: app,
          row: row,
          child: ItemDropTarget(
            key: ValueKey('into-$path'),
            app: app,
            parent: intValue(row['id']),
            targetPath: path,
            child: Padding(padding: const EdgeInsets.all(2), child: child),
          ),
        ),
      ],
    );
  }
}
