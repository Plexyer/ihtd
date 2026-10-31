import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_controller.dart';
import '../services/item_draft.dart';
import 'item_editor.dart';
import 'collection_settings.dart';
import 'item_removal.dart';
import 'item_drag.dart';
import 'sort_settings.dart';
import 'priority_icon.dart';
import 'summary_indicators.dart';
import 'shared.dart';
import 'view_editor.dart';
import 'document_status.dart';
import 'app_theme.dart';
import 'app_updates.dart';
import 'app_license.dart';
import '../services/update_composition.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _escape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final app = ref.read(appProvider);
    if (app.itemDraft == null) return false;
    unawaited(app.resolveItemDraft(reason: DraftExitReason.back, close: true));
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_escape);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_escape);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    app.confirmDocumentAction = (title, message) => context.mounted
        ? confirmDocumentAction(context, title, message)
        : Future.value(false);
    app.chooseDraftExit = (draft, reason) => context.mounted
        ? chooseItemDraftExit(context, draft, reason)
        : Future.value(DraftExitChoice.keepEditing);
    if ((app.recoveredDrafts.isNotEmpty ||
            app.itemDrafts.unreadableCount > 0) &&
        !app.recoveryOfferShown) {
      app.recoveryOfferShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) showRecoveredItemDrafts(context, app);
      });
    }
    return PopScope<void>(
      canPop: app.itemDraft == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await app.resolveItemDraft(reason: DraftExitReason.back, close: true);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          final draft = app.itemDraft;
          if (!wide && draft != null && !app.editorOverlayVisible) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted &&
                  identical(app.itemDraft, draft) &&
                  !app.editorOverlayVisible) {
                showItemDraftDialog(context, app);
              }
            });
          }
          final drawer = constraints.maxWidth < 780;
          final surfaces = AppSurfaces.of(context);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: surfaceOverlays(
              top: surfaces.header,
              bottom: surfaces.canvas,
            ),
            child: Scaffold(
              drawer: drawer
                  ? AnnotatedRegion<SystemUiOverlayStyle>(
                      value: surfaceOverlays(
                        top: surfaces.sidebar,
                        bottom: surfaces.sidebar,
                      ),
                      child: Drawer(
                        backgroundColor: surfaces.sidebar,
                        surfaceTintColor: Colors.transparent,
                        child: SafeArea(child: _Sidebar(app: app)),
                      ),
                    )
                  : null,
              body: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () async {
                  if (!app.editorOverlayVisible) {
                    await app.resolveItemDraft(
                      reason: DraftExitReason.outside,
                      close: true,
                    );
                  }
                },
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      ColoredBox(
                        key: const ValueKey('header-surface'),
                        color: surfaces.header,
                        child: SafeArea(
                          bottom: false,
                          child: _FileBar(app: app, drawer: drawer),
                        ),
                      ),
                      if ((app.document != null ||
                              app.documentServices.binding != null ||
                              app.documentServices.migrations.hasIssue) &&
                          (constraints.maxWidth <= 540 || app.documentIssue))
                        DocumentStatus(app: app),
                      if (app.recoveredDrafts.isNotEmpty ||
                          app.itemDrafts.unreadableCount > 0)
                        Material(
                          color: const Color(0xffffefbd),
                          child: ListTile(
                            title: const Text(
                              'Unfinished drafts are available on this device',
                            ),
                            trailing: TextButton(
                              onPressed: () =>
                                  showRecoveredItemDrafts(context, app),
                              child: const Text('Review drafts…'),
                            ),
                          ),
                        ),
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
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: Row(
                            children: [
                              if (!drawer)
                                SizedBox(width: 242, child: _Sidebar(app: app)),
                              Expanded(
                                child: app.document == null
                                    ? _Welcome(app: app)
                                    : _TaskPane(
                                        app: app,
                                        showDetail: (id, path) async {
                                          await app.selectItem(id, path: path);
                                        },
                                      ),
                              ),
                              if (wide &&
                                  app.document != null &&
                                  app.itemDraft != null &&
                                  !app.editorOverlayVisible) ...[
                                const VerticalDivider(width: 1),
                                SizedBox(
                                  width: 360,
                                  child: ItemEditor(app: app),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FileBar extends ConsumerWidget {
  const _FileBar({required this.app, required this.drawer});
  final AppController app;
  final bool drawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = app.documentName;
    return Container(
      height: 58,
      padding: EdgeInsets.only(left: drawer ? 4 : 20, right: 12),
      decoration: BoxDecoration(
        color: AppSurfaces.of(context).header,
        border: const Border(bottom: BorderSide(color: Color(0xffe1e7ef))),
      ),
      child: Row(
        children: [
          AppUpdateButton(app: app),
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
                case 'settings':
                  showCollectionSettings(context, app);
                case 'about':
                  showIhtdAbout(context);
                case 'updates':
                  final updates = ref.read(updateProvider);
                  showUpdateDetails(context, updates);
                  updates.check();
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
              if (app.document != null)
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Settings…'),
                ),
              const PopupMenuItem(
                value: 'about',
                child: Text('About and licenses…'),
              ),
              const PopupMenuItem(
                value: 'updates',
                child: Text('Check for updates…'),
              ),
              if (app.documentServices.binding != null)
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
    final storedViews = documentValues(app, 'views');
    final views = [
      ...storedViews.where((v) => app.isProtectedView(intValue(v['id']))),
      ...storedViews.where((v) => !app.isProtectedView(intValue(v['id']))),
    ];
    return Material(
      color: AppSurfaces.of(context).sidebar,
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
                        key: ValueKey('view-${view['id']}'),
                        tileColor:
                            app.issuesForView(intValue(view['id'])).isNotEmpty
                            ? const Color(0xfffff4d0)
                            : null,
                        selectedTileColor:
                            app.issuesForView(intValue(view['id'])).isNotEmpty
                            ? const Color(0xffffe7a0)
                            : const Color(0xffdbe7f7),
                        selectedColor: const Color(0xff235b9b),
                        selected: app.selectedViewId == intValue(view['id']),
                        leading: Icon(
                          app.issuesForView(intValue(view['id'])).isNotEmpty
                              ? Icons.warning_amber_rounded
                              : app.isProtectedView(intValue(view['id']))
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
                          tooltip: app.isProtectedView(intValue(view['id']))
                              ? 'About All tasks'
                              : 'Edit view',
                          icon: Icon(
                            app.isProtectedView(intValue(view['id']))
                                ? Icons.info_outline
                                : Icons.tune,
                            size: 16,
                          ),
                          onPressed: () =>
                              showViewEditor(context, app, existing: view),
                        ),
                        onTap: () async {
                          final id = intValue(view['id']);
                          await app.selectView(id);
                          if (context.mounted &&
                              app.selectedViewId == id &&
                              Scaffold.of(context).isDrawerOpen) {
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
        if (Scaffold.of(context).hasDrawer)
          TextButton.icon(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
            label: const Text('Open views'),
          ),
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
  final void Function(int, String) showDetail;

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
                    Row(
                      children: [
                        if (Scaffold.of(context).hasDrawer)
                          IconButton(
                            tooltip: 'Open views',
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                        Expanded(
                          child: Text(
                            '${view['name'] ?? 'All items'}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      ],
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
                tooltip: app.isProtectedView(intValue(view['id']))
                    ? 'About All tasks'
                    : 'Edit this view',
                onPressed: () => showViewEditor(context, app, existing: view),
                icon: Icon(
                  app.isProtectedView(intValue(view['id']))
                      ? Icons.info_outline
                      : Icons.tune,
                ),
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
              SortControl(app: app),
            ],
          ),
          const SizedBox(height: 12),
          ItemDropTarget(
            key: const ValueKey('top-level-drop'),
            app: app,
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
          if (app.issuesForView(app.selectedViewId).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                key: const ValueKey('view-rule-warning'),
                color: const Color(0xfffff4d0),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => showViewEditor(context, app, existing: view),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: Color(0xff8a5b00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${app.issuesForView(app.selectedViewId).take(2).map((issue) => "Rule ${issue['path']}: deleted container #${issue['container_id']}").join('; ')}'
                            '${app.issuesForView(app.selectedViewId).length > 2 ? '; and ${app.issuesForView(app.selectedViewId).length - 2} more' : ''}. Tap to review view rules.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xff795000),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                        endPaths: [
                          for (
                            var level = depth;
                            level >
                                (index + 1 < app.rows.length
                                    ? intValue(app.rows[index + 1]['depth'])
                                    : -1);
                            level--
                          )
                            '${row['path']}'.split('/').take(level).join('/'),
                        ],
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
                              onTap: () => showDetail(id, '${row['path']}'),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(3, 8, 8, 8),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SummaryBodyControls(
                                        summary: asMap(row['summary']),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 30,
                                              child: row['has_children'] == true
                                                  ? IconButton(
                                                      tooltip:
                                                          row['expanded'] ==
                                                              true
                                                          ? 'Collapse children'
                                                          : 'Expand children',
                                                      padding: EdgeInsets.zero,
                                                      icon: Icon(
                                                        row['expanded'] == true
                                                            ? Icons
                                                                  .keyboard_arrow_down
                                                            : Icons
                                                                  .keyboard_arrow_right,
                                                        size: 21,
                                                      ),
                                                      onPressed: () =>
                                                          app.toggleExpand(
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
                                                    : (value) =>
                                                          changeCompletion(
                                                            context,
                                                            app,
                                                            id,
                                                            value!,
                                                          ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: SummaryItemContent(
                                          summary: asMap(row['summary']),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
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
                                                      ? TextDecoration
                                                            .lineThrough
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
                                                    if (depth > 10)
                                                      'Depth $depth',
                                                    if (item['due_date'] !=
                                                        null)
                                                      'Due ${item['due_date']}',
                                                    ...tags.map(
                                                      (tag) => '#$tag',
                                                    ),
                                                  ].join('  ·  '),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xff7f8fa1),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (SummaryPriorityCounts.hasCounts(
                                        asMap(row['summary']),
                                      ))
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: SummaryPriorityCounts(
                                            summary: asMap(row['summary']),
                                          ),
                                        ),
                                      SummaryBodyControls(
                                        summary: asMap(row['summary']),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (intValue(item['priority']) > 0)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                    ),
                                                child: PriorityIcon(
                                                  priority: intValue(
                                                    item['priority'],
                                                  ),
                                                ),
                                              ),
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                PopupMenuButton<String>(
                                                  key: ValueKey(
                                                    'menu-${row['path']}',
                                                  ),
                                                  tooltip: 'Item actions',
                                                  icon: const Icon(
                                                    Icons.more_horiz,
                                                    size: 19,
                                                  ),
                                                  onSelected: (action) {
                                                    if (action == 'sort') {
                                                      showSortSettings(
                                                        context,
                                                        app,
                                                        parent: id,
                                                      );
                                                    }
                                                    if (action == 'details') {
                                                      showDetail(
                                                        id,
                                                        '${row['path']}',
                                                      );
                                                    }
                                                    if (action == 'remove' ||
                                                        action == 'delete' ||
                                                        action == 'unlink') {
                                                      removeItemPlacement(
                                                        context,
                                                        app,
                                                        id,
                                                        row['parent_id']
                                                            as int?,
                                                        path: '${row['path']}',
                                                        action:
                                                            action == 'remove'
                                                            ? null
                                                            : action,
                                                      );
                                                    }
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
                                                      showLinkItem(
                                                        context,
                                                        app,
                                                        id,
                                                      );
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: 'sort',
                                                      child: Text(
                                                        'Sort children…',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'details',
                                                      child: Text(
                                                        'Open details',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'task',
                                                      child: Text(
                                                        'Add subtask',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'folder',
                                                      child: Text(
                                                        'Add subfolder',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'link',
                                                      child: Text(
                                                        'Link / copy task to…',
                                                      ),
                                                    ),
                                                    const PopupMenuDivider(),
                                                    if (hasMultipleAppearances(
                                                      app,
                                                      id,
                                                    ))
                                                      const PopupMenuItem(
                                                        value: 'unlink',
                                                        child: Text('Unlink'),
                                                      ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete'),
                                                    ),
                                                  ],
                                                ),
                                                if (hasMultipleAppearances(
                                                  app,
                                                  id,
                                                ))
                                                  SizedBox(
                                                    width: 64,
                                                    child: Tooltip(
                                                      message:
                                                          'Links: ${appearanceCount(app, id)}',
                                                      child: Text(
                                                        'Links: ${appearanceCount(app, id)}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                            0xff7f8fa1,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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
