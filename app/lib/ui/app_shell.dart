import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_controller.dart';
import 'item_editor.dart';
import 'item_drag.dart';
import 'shared.dart';
import 'view_editor.dart';
import 'document_status.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    app.confirmDocumentAction = (title, message) => context.mounted
        ? confirmDocumentAction(context, title, message)
        : Future.value(false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final drawer = constraints.maxWidth < 780;
        return Scaffold(
          drawer: drawer
              ? Drawer(
                  child: SafeArea(child: _Sidebar(app: app)),
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                _FileBar(app: app, drawer: drawer),
                if ((app.document != null ||
                        app.androidDocuments?.binding != null) &&
                    (constraints.maxWidth <= 540 || app.documentIssue))
                  DocumentStatus(app: app),
                if (app.busy) const LinearProgressIndicator(minHeight: 2),
                if (app.error != null)
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 19),
                          const SizedBox(width: 12),
                          Expanded(child: SelectableText(app.error!)),
                          IconButton(
                            tooltip: 'Dismiss error',
                            onPressed: app.clearError,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (!drawer)
                        SizedBox(width: 242, child: _Sidebar(app: app)),
                      Expanded(
                        child: app.document == null
                            ? _Welcome(app: app)
                            : _TaskPane(
                                app: app,
                                showDetail: (id) async {
                                  await app.selectItem(id);
                                  if (!context.mounted ||
                                      app.selectedItemId != id) {
                                    return;
                                  }
                                  if (!wide) {
                                    showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      isDismissible: false,
                                      enableDrag: false,
                                      constraints: const BoxConstraints(
                                        maxWidth: 620,
                                      ),
                                      builder: (context) => Padding(
                                        padding: EdgeInsets.only(
                                          bottom: MediaQuery.viewInsetsOf(
                                            context,
                                          ).bottom,
                                        ),
                                        child: PopScope(
                                          canPop: false,
                                          onPopInvokedWithResult:
                                              (didPop, result) async {
                                                if (!didPop &&
                                                    await app.finishDraft() &&
                                                    context.mounted) {
                                                  Navigator.of(context).pop();
                                                }
                                              },
                                          child: SizedBox(
                                            height:
                                                MediaQuery.sizeOf(context)
                                                    .height *
                                                .88,
                                            child: Column(
                                              children: [
                                                Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: TextButton.icon(
                                                    onPressed: () async {
                                                      if (await app
                                                              .finishDraft() &&
                                                          context.mounted) {
                                                        Navigator.of(context)
                                                            .pop();
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons.close,
                                                    ),
                                                    label: const Text('Done'),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Consumer(
                                                    builder:
                                                        (context, ref, child) =>
                                                            ItemEditor(
                                                              app: ref.watch(
                                                                appProvider,
                                                              ),
                                                            ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                      ),
                      if (wide &&
                          app.document != null &&
                          app.selectedItemId != null) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(width: 360, child: ItemEditor(app: app)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FileBar extends StatelessWidget {
  const _FileBar({required this.app, required this.drawer});
  final AppController app;
  final bool drawer;

  @override
  Widget build(BuildContext context) {
    final name = app.documentName;
    return Container(
      height: 58,
      padding: EdgeInsets.only(left: drawer ? 4 : 20, right: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffe1e7ef))),
      ),
      child: Row(
        children: [
          if (drawer)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Open views',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            ),
          const Icon(Icons.check_circle, color: Color(0xff2763a5), size: 23),
          const SizedBox(width: 10),
          const Text(
            'IHTD',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              name ?? 'Your tasks, connected',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xff657589)),
            ),
          ),
          if (MediaQuery.sizeOf(context).width > 540 && !app.documentIssue) ...[
            Icon(
              app.error == null
                  ? Icons.save_outlined
                  : Icons.warning_amber_rounded,
              size: 16,
              color: app.error == null
                  ? const Color(0xff5c7b6c)
                  : Colors.orange,
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                app.status,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xff68788a)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          PopupMenuButton<String>(
            tooltip: 'File and export',
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              switch (value) {
                case 'connection':
                  showDialog<void>(
                    context: context,
                    builder: (_) => DocumentIssueDialog(app: app),
                  );
                case 'new':
                  app.newDocument();
                case 'open':
                  app.openDocument();
                case 'save':
                  app.saveAs();
                case 'retry':
                  app.retryDocumentSave();
                default:
                  app.exportDocument(value);
              }
            },
            itemBuilder: (context) => [
              if (app.androidDocuments?.binding != null)
                const PopupMenuItem(
                  value: 'connection',
                  child: Text('File connection and saving…'),
                ),
              const PopupMenuItem(value: 'new', child: Text('New collection…')),
              const PopupMenuItem(
                value: 'open',
                child: Text('Open .ihtd file…'),
              ),
              PopupMenuItem(
                value: 'save',
                enabled: app.document != null,
                child: const Text('Save a copy as…'),
              ),
              PopupMenuItem(
                value: 'retry',
                enabled: app.document != null,
                child: const Text('Retry saving changes'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'json',
                enabled: app.document != null,
                child: const Text('Export complete JSON…'),
              ),
              PopupMenuItem(
                value: 'markdown',
                enabled: app.document != null,
                child: const Text('Export Markdown…'),
              ),
              PopupMenuItem(
                value: 'csv',
                enabled: app.document != null,
                child: const Text('Export CSV…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final views = documentValues(app, 'views');
    return Material(
      color: const Color(0xffeef2f7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 28, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'MY COLLECTION',
                style: TextStyle(
                  color: Color(0xff7b8999),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                children: [
                  for (final view in views)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        selectedTileColor: const Color(0xffdbe7f7),
                        selectedColor: const Color(0xff235b9b),
                        selected: app.selectedViewId == intValue(view['id']),
                        leading: Icon(
                          intValue(view['id']) == 1
                              ? Icons.layers_outlined
                              : Icons.filter_alt_outlined,
                          size: 21,
                        ),
                        title: Text(
                          '${view['name']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        contentPadding: const EdgeInsets.only(
                          left: 12,
                          right: 0,
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit view',
                          icon: const Icon(Icons.tune, size: 16),
                          onPressed: () =>
                              showViewEditor(context, app, existing: view),
                        ),
                        onTap: () {
                          app.selectView(intValue(view['id']));
                          if (Scaffold.of(context).isDrawerOpen) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  if (app.document != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.all(12),
                        ),
                        onPressed: () => showViewEditor(context, app),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Create a view'),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_open_outlined, size: 20),
              title: const Text('Open collection'),
              onTap: app.openDocument,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.note_add_outlined, size: 20),
              title: const Text('New collection'),
              onTap: app.newDocument,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 18, 12, 0),
              child: Text(
                'One file. All your tasks.\nShared items stay connected.',
                style: TextStyle(
                  color: Color(0xff8995a4),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.account_tree_outlined,
    title: 'A little structure.\nA clearer day.',
    description: 'Organize tasks and folders at any depth. Connect the same task to several projects, and keep everything in your own .ihtd file.',
    action: Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: app.busy ? null : app.newDocument,
          icon: const Icon(Icons.add),
          label: const Text('Create collection'),
        ),
        OutlinedButton.icon(
          onPressed: app.busy ? null : app.openDocument,
          icon: const Icon(Icons.folder_open),
          label: const Text('Open file'),
        ),
      ],
    ),
  );
}

class _TaskPane extends StatelessWidget {
  const _TaskPane({required this.app, required this.showDetail});
  final AppController app;
  final ValueChanged<int> showDetail;

  @override
  Widget build(BuildContext context) {
    final view = asMap(asMap(app.document?['views'])['${app.selectedViewId}']);
    return Padding(
      padding: MediaQuery.sizeOf(context).width < 540
          ? const EdgeInsets.fromLTRB(12, 16, 12, 12)
          : const EdgeInsets.fromLTRB(28, 28, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${view['name'] ?? 'All items'}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      app.completedOnly
                          ? 'Completed items, with their original structure'
                          : 'Make room for what matters',
                      style: const TextStyle(
                        color: Color(0xff76869a),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit this view',
                onPressed: () => showViewEditor(context, app, existing: view),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Unfinished'),
                    icon: Icon(Icons.radio_button_unchecked, size: 17),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Completed'),
                    icon: Icon(Icons.check_circle_outline, size: 17),
                  ),
                ],
                selected: {app.completedOnly},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    app.setCompletedOnly(selection.first),
              ),
              FilledButton.icon(
                onPressed: app.busy ? null : () => showCreateItem(context, app),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add task'),
              ),
              OutlinedButton.icon(
                onPressed: app.busy
                    ? null
                    : () => showCreateItem(context, app, kind: 'folder'),
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                label: const Text('Folder'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ItemDropTarget(
            key: const ValueKey('top-level-drop'),
            app: app,
            reorder: true,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.drive_file_move_outline,
                    size: 17,
                    color: Color(0xff76869a),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Drop here to move to the top level',
                      style: TextStyle(fontSize: 12, color: Color(0xff76869a)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: app.rows.isEmpty
                ? EmptyState(
                    icon: app.completedOnly
                        ? Icons.task_alt
                        : Icons.wb_sunny_outlined,
                    title: app.completedOnly
                        ? 'Nothing completed here yet'
                        : 'A fresh start',
                    description: app.completedOnly
                        ? 'Finished tasks will appear here, along with their parent folders and tasks.'
                        : 'Add a task or folder to get started. Filtered views can also be empty when no items match.',
                  )
                : ListView.builder(
                    itemCount: app.rows.length,
                    itemBuilder: (context, index) {
                      final row = app.rows[index];
                      final item = itemById(app, intValue(row['id']));
                      if (item.isEmpty) return const SizedBox.shrink();
                      final id = intValue(item['id']);
                      final folder = item['kind'] == 'folder';
                      final completed = item['completed'] == true;
                      final contextOnly = row['context_only'] == true;
                      final depth = intValue(row['depth']);
                      final tags = (item['tag_ids'] as List? ?? [])
                          .map(
                            (tag) => asMap(
                              asMap(app.document?['tags'])['$tag'],
                            )['name'],
                          )
                          .whereType<String>()
                          .toList();
                      final selected = app.selectedItemId == id;
                      return PlacementRow(
                        app: app,
                        row: row,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: (depth * 22.0).clamp(
                              0,
                              MediaQuery.sizeOf(context).width < 540 ? 72 : 220,
                            ),
                            bottom: 6,
                          ),
                          child: Material(
                            color: selected
                                ? const Color(0xffe8f0fc)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xffa9c3e6)
                                    : const Color(0xffe9edf3),
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => showDetail(id),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(3, 8, 8, 8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 30,
                                      child: row['has_children'] == true
                                          ? IconButton(
                                              tooltip: row['expanded'] == true
                                                  ? 'Collapse children'
                                                  : 'Expand children',
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                row['expanded'] == true
                                                    ? Icons.keyboard_arrow_down
                                                    : Icons
                                                          .keyboard_arrow_right,
                                                size: 21,
                                              ),
                                              onPressed: () => app.toggleExpand(
                                                '${row['path']}',
                                              ),
                                            )
                                          : null,
                                    ),
                                    if (folder)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Icon(
                                          Icons.folder_outlined,
                                          color: Color(0xffa68755),
                                          size: 23,
                                        ),
                                      )
                                    else
                                      Checkbox(
                                        value: completed,
                                        shape: const CircleBorder(),
                                        onChanged: app.busy
                                            ? null
                                            : (value) => changeCompletion(
                                                context,
                                                app,
                                                id,
                                                value!,
                                              ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item['title']}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: contextOnly
                                                  ? const Color(0xff8290a2)
                                                  : const Color(0xff233f5d),
                                              decoration: completed
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              fontSize: 14,
                                              fontWeight: folder
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                          if (tags.isNotEmpty ||
                                              item['due_date'] != null ||
                                              contextOnly ||
                                              depth > 10) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                if (contextOnly) 'Context',
                                                if (depth > 10) 'Depth $depth',
                                                if (item['due_date'] != null)
                                                  'Due ${item['due_date']}',
                                                ...tags.map((tag) => '#$tag'),
                                              ].join('  ·  '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xff7f8fa1),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (intValue(item['priority']) > 0)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Tooltip(
                                          message:
                                              '${priorityLabel(item['priority'])} priority',
                                          child: Icon(
                                            Icons.flag_outlined,
                                            size: 18,
                                            color:
                                                intValue(item['priority']) == 3
                                                ? const Color(0xffc57d49)
                                                : const Color(0xff91a3b8),
                                          ),
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Item actions',
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        size: 19,
                                      ),
                                      onSelected: (action) {
                                        if (action == 'details') showDetail(id);
                                        if (action == 'task') {
                                          showCreateItem(
                                            context,
                                            app,
                                            parentId: id,
                                          );
                                        }
                                        if (action == 'folder') {
                                          showCreateItem(
                                            context,
                                            app,
                                            parentId: id,
                                            kind: 'folder',
                                          );
                                        }
                                        if (action == 'link') {
                                          showLinkItem(context, app, id);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'details',
                                          child: Text('Open details'),
                                        ),
                                        PopupMenuItem(
                                          value: 'task',
                                          child: Text('Add subtask'),
                                        ),
                                        PopupMenuItem(
                                          value: 'folder',
                                          child: Text('Add subfolder'),
                                        ),
                                        PopupMenuItem(
                                          value: 'link',
                                          child: Text(
                                            'Add existing item here…',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
