import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'shared.dart';

class ItemPlacement {
  const ItemPlacement(
    this.owner,
    this.view,
    this.completed,
    this.path,
    this.id,
    this.parent,
  );
  final DocumentEditIdentity owner;
  final int view;
  final bool completed;
  final String path;
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
          app.editIdentity,
          app.selectedViewId,
          app.completedOnly,
          '${row['path']}',
          id,
          ItemPlacement.parentFromPath('${row['path']}'),
        ),
        onDragStarted: () {
          app.draggingItem = true;
          app.notifyListeners();
        },
        onDragEnd: (_) {
          app.draggingItem = false;
          app.notifyListeners();
        },
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
        source.owner != app.editIdentity ||
        source.view != app.selectedViewId ||
        source.completed != app.completedOnly ||
        source.id == parent ||
        source.id == before) {
      return false;
    }
    return true;
  }

  Future<void> move(ItemPlacement source) async {
    if (!accepts(source)) return;
    final result = await app.moveOccurrence(
      owner: source.owner,
      view: source.view,
      completed: source.completed,
      sourcePath: source.path,
      destinationPath: targetPath ?? '',
      before: before,
      reorder: reorder,
    );
    if (result && !reorder && targetPath != null && targetPath!.isNotEmpty) {
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
    builder: (context, candidates, rejected) {
      final active = candidates.isNotEmpty;
      if (reorder) {
        return Semantics(
          label: before == null
              ? 'Insert at end of this level'
              : 'Insert before this item',
          child: SizedBox(
            height: 18,
            child: Padding(
              padding: EdgeInsets.only(
                left:
                    ((targetPath ?? '').isEmpty
                            ? 0
                            : (targetPath!.split('/').length * 22.0))
                        .clamp(
                          0,
                          MediaQuery.sizeOf(context).width < 540 ? 72 : 220,
                        )
                        .toDouble(),
              ),
              child: Opacity(
                opacity: active
                    ? 1
                    : app.draggingItem
                    ? .55
                    : 0,
                child: Row(
                  children: [
                    Container(
                      width: active ? 8 : 5,
                      height: active ? 8 : 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xff2763a5),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: active ? 3 : 1,
                        color: const Color(0xff2763a5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return Container(
        decoration: !active
            ? null
            : BoxDecoration(
                color: const Color(0xffd7e7ff),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff2763a5), width: 2),
              ),
        child: child,
      );
    },
  );
}

class PlacementRow extends StatelessWidget {
  const PlacementRow({
    super.key,
    required this.app,
    required this.row,
    required this.child,
    this.endPaths = const [],
  });
  final AppController app;
  final Map<String, dynamic> row;
  final Widget child;
  final List<String> endPaths;
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
          targetPath: path.contains('/')
              ? path.substring(0, path.lastIndexOf('/'))
              : '',
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
        for (final end in endPaths)
          ItemDropTarget(
            key: ValueKey('after-${end.isEmpty ? 'root' : end}'),
            app: app,
            parent: end.isEmpty ? null : int.parse(end.split('/').last),
            targetPath: end,
            reorder: true,
            child: const SizedBox.shrink(),
          ),
      ],
    );
  }
}
