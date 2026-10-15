import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/ui/app_shell.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/item_editor.dart';
import 'package:app/ui/item_removal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'document_contract_test.dart' show FakeAdapter;

void main() {
  late Directory directory;
  late FakeAdapter adapter;
  late AppController app;
  late ProviderContainer container;
  late Map<String, dynamic> document, placements;
  late Map<String, dynamic> viewIssues;
  late List<Map<String, dynamic>> commands, rows;
  late String working;

  Map<String, dynamic> snapshot() => {
    'path': working,
    'dirty': false,
    'document': document,
    'placements': placements,
    'view_issues': viewIssues,
    'completion': {},
  };
  Future<String> command(String request) async {
    final op = Map<String, dynamic>.from(jsonDecode(request) as Map);
    commands.add(op);
    var data = <String, dynamic>{};
    var ok = true;
    if (op['op'] == 'query') data = {'rows': rows};
    if (op['op'] == 'preview_removal') {
      final shared = placements['${op['id']}']['count'] > 1;
      data = {
        'id': op['id'],
        'parent': op['parent'],
        'action': shared ? 'unlink' : 'delete',
        'document_id': document['document_id'],
        'revision': document['revision'],
        'deleted_ids': shared ? [] : [op['id']],
        'retained_child_ids': [],
        'affected_view_ids': [],
      };
    }
    if (op['op'] == 'remove_placement') {
      final preview = op['preview'] as Map;
      if (preview['revision'] != document['revision']) {
        ok = false;
      } else {
        if (preview['action'] == 'delete') {
          (document['items'] as Map).remove('${preview['id']}');
          rows.removeWhere((r) => r['id'] == preview['id']);
          placements.remove('${preview['id']}');
        } else {
          document['root_order'] = [2];
          placements['3'] = {
            'root': false,
            'parents': [2],
            'count': 1,
          };
          rows.removeWhere((r) => r['path'] == '3');
        }
        document['revision'] = (document['revision'] as int) + 1;
        File(working)
            .writeAsStringSync('local revision ${document['revision']}');
      }
    }
    return jsonEncode({
      'ok': ok,
      'error': 'The collection changed. Review removal again.',
      'data': data,
      'snapshot': snapshot(),
    });
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ihtd-removal-ui-');
    commands = [];
    adapter = FakeAdapter('filesystem');
    final coordinator = DocumentSaveCoordinator(
      adapter: adapter,
      supportDirectory: () async => directory,
    );
    await coordinator.initialize();
    working = coordinator.freshPath();
    await File(working).writeAsString(adapter.contents);
    document = {
      'document_id': 'removal-test',
      'revision': 1,
      'items': {
        '2': {
          'id': 2,
          'kind': 'folder',
          'title': 'Parent',
          'notes': '',
          'priority': 0,
        },
        '3': {
          'id': 3,
          'kind': 'task',
          'title': 'Shared task',
          'notes': '',
          'priority': 0,
        },
      },
      'links': [
        {'parent': 2, 'child': 3},
      ],
      'root_order': [2, 3],
      'tags': {},
      'deleted_item_ids': [],
      'views': {
        '1': {
          'id': 1,
          'name': 'All tasks',
          'filter': {'op': 'all'},
        },
        '7': {
          'id': 7,
          'name': 'Travel view',
          'filter': {'op': 'folder', 'folder_id': 9, 'recursive': true},
        },
      },
    };
    placements = {
      '2': {'root': true, 'parents': [], 'count': 1},
      '3': {
        'root': true,
        'parents': [2],
        'count': 2,
      },
    };
    viewIssues = {};
    rows = [
      {
        'id': 2,
        'path': '2',
        'parent_id': null,
        'placement_count': 1,
        'depth': 0,
      },
      {
        'id': 3,
        'path': '2/3',
        'parent_id': 2,
        'placement_count': 2,
        'depth': 1,
      },
      {
        'id': 3,
        'path': '3',
        'parent_id': null,
        'placement_count': 2,
        'depth': 0,
      },
    ];
    app = AppController(
      command: command,
      documentServices: coordinator,
      supportDirectory: () async => directory,
      polling: false,
    );
    await app.ready;
    container = ProviderContainer(
      overrides: [appProvider.overrideWith((_) => app)],
    );
    container.read(appProvider);
    PackageInfo.setMockInitialValues(
      appName: 'IHTD',
      packageName: 'dev.ihtd.app',
      version: '0.2.2',
      buildNumber: '10',
      buildSignature: '',
    );
  });
  tearDown(() async {
    container.dispose();
    await app.documentServices.diagnostics.flush();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 120; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      if (attempt >= 5 && !app.busy) break;
    }
    expect(app.busy, false, reason: 'Commands: $commands; error: ${app.error}');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
  }

  Future<void> shell(
    WidgetTester tester, {
    Size size = const Size(1360, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(app.refreshRows);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildIhtdTheme(), home: const AppShell()),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'root Unlink is immediate, preserves selection and changes label to Delete',
    (tester) async {
      await tester.runAsync(() => app.selectItem(3));
      await shell(tester);
      expect(await tester.runAsync(app.finishDraft), true);
      app.expandedPaths.add('!3');
      final writes = adapter.writes;
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('menu-3'))),
      );
      await settle(tester);
      await tester.runAsync(
        () => tester.tap(
          find.byWidgetPredicate(
            (w) => w is PopupMenuItem<String> && w.value == 'remove',
          ),
        ),
      );
      await settle(tester);
      expect(find.textContaining('Delete “'), findsNothing);
      expect(
        commands.where((c) => c['op'] == 'remove_placement'),
        isNotEmpty,
        reason: 'Commands: $commands, error: ${app.error}, busy: ${app.busy}',
      );
      final removal = commands.lastWhere((c) => c['op'] == 'remove_placement');
      expect(removal['preview']['parent'], isNull);
      expect(removal['preview']['action'], 'unlink');
      expect(removal['confirm_delete'], false);
      expect(app.selectedItemId, 3);
      expect(app.expandedPaths, isNot(contains('!3')));
      expect(adapter.writes, writes);
      expect(
        commands.where((c) => c['op'] == 'remove_placement'),
        hasLength(1),
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('menu-2/3'))),
      );
      await settle(tester);
      expect(find.text('Delete'), findsWidgets);
      expect(find.text('Unlink'), findsNothing);
    },
  );

  testWidgets(
    'Delete cancel does not mutate or publish; confirmation clears deleted selection',
    (tester) async {
      placements['3'] = {
        'root': false,
        'parents': [2],
        'count': 1,
      };
      document['root_order'] = [2];
      rows.removeWhere((r) => r['path'] == '3');
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      await tester.runAsync(() => app.selectItem(3));
      await shell(tester);
      final writes = adapter.writes;
      Future<void> ask() async {
        await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('menu-2/3'))),
        );
        await settle(tester);
        await tester.runAsync(
          () => tester.tap(
            find.byWidgetPredicate(
              (w) => w is PopupMenuItem<String> && w.value == 'remove',
            ),
          ),
        );
        await settle(tester);
      }

      await ask();
      expect(find.text('Delete “Shared task”?'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Cancel')));
      await settle(tester);
      expect(commands.where((c) => c['op'] == 'remove_placement'), isEmpty);
      expect(adapter.writes, writes);
      await ask();
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
      );
      await settle(tester);
      expect(app.selectedItemId, isNull);
      expect(app.document!['items']['3'], isNull);
      expect(adapter.writes, writes);
      expect(
        commands.where((c) => c['op'] == 'remove_placement'),
        hasLength(1),
      );
    },
  );

  testWidgets('details expose root and parent placement choices', (
    tester,
  ) async {
    await tester.runAsync(() => app.selectItem(3));
    await shell(tester);
    final list = find.descendant(
      of: find.byType(ItemEditor),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -1500));
    await settle(tester);
    expect(find.byKey(const ValueKey('remove-3-root')), findsOneWidget);
    expect(find.byKey(const ValueKey('remove-3-2')), findsOneWidget);
  });

  testWidgets('stale confirmation never deletes and user can preview again', (
    tester,
  ) async {
    placements['3'] = {
      'root': false,
      'parents': [2],
      'count': 1,
    };
    await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
    final removed = await tester.runAsync(
      () => app.removePlacement(
        3,
        2,
        confirmDelete: (_) async {
          document['revision'] =
              2; // simulate another accepted edit during dialog
          return true;
        },
      ),
    );
    expect(removed, false);
    expect(app.document!['items']['3'], isNotNull);
    expect(app.error, contains('changed'));
    expect(adapter.writes, 0);
  });

  testWidgets('collection switch during confirmation invalidates approval', (
    tester,
  ) async {
    placements['3'] = {
      'root': false,
      'parents': [2],
      'count': 1,
    };
    await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
    final removed = await tester.runAsync(
      () => app.removePlacement(
        3,
        2,
        confirmDelete: (_) async {
          document['document_id'] = 'different collection';
          await app.dispatch({'op': 'snapshot'});
          return true;
        },
      ),
    );
    expect(removed, false);
    expect(commands.where((c) => c['op'] == 'remove_placement'), isEmpty);
    expect(app.error, contains('collection changed'));
  });

  testWidgets(
    'unavailable external file retains removal locally without publishing',
    (tester) async {
      placements['3'] = {
        'root': false,
        'parents': [2],
        'count': 1,
      };
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      await tester.runAsync(
        () => app.documentServices.attach({
          'reference': adapter.referenceFor('external').toJson(),
          'path': working,
          'hash': adapter.contents,
          'name': adapter.name,
        }),
      );
      final preview = await tester.runAsync(
        () => app.dispatch({'op': 'preview_removal', 'id': 3, 'parent': 2}),
      );
      expect(preview, isNotNull);
      expect(
        adapter.writes,
        0,
      ); // preview must not mark or publish pending work
      adapter.available = false;
      await tester.runAsync(app.poll);
      final external = adapter.contents;
      expect(
        await tester.runAsync(
          () => app.removePlacement(3, 2, confirmDelete: (_) async => true),
        ),
        true,
      );
      expect(app.document!['items']['3'], isNull);
      expect(adapter.contents, external);
      expect(adapter.writes, 0);
      expect(app.documentServices.pending, true);
      expect(app.status, contains('Pending'));
    },
  );

  testWidgets(
    'deleted-container view has yellow tile, hierarchy warning and editable missing rule',
    (tester) async {
      document['deleted_item_ids'] = [9];
      viewIssues['7'] = [
        {'path': '1', 'container_id': 9},
      ];
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      await tester.runAsync(() => app.selectView(7));
      await shell(tester);
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey('view-7')),
      );
      expect(tile.selectedTileColor, const Color(0xffffe7a0));
      expect(find.byKey(const ValueKey('view-rule-warning')), findsOneWidget);
      expect(
        find.textContaining('Rule 1: deleted container #9'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('view-rule-warning'))),
      );
      await settle(tester);
      expect(find.textContaining('Deleted container (#9)'), findsOneWidget);
      expect(
        find.textContaining('Replace it or remove this rule'),
        findsOneWidget,
      );
      await tester.runAsync(() => tester.tap(find.text('Cancel')));
      await settle(tester);
      // Repair metadata from the authoritative backend clears warning everywhere.
      viewIssues['7'] = [];
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      await settle(tester);
      expect(find.byKey(const ValueKey('view-rule-warning')), findsNothing);
      // An empty/new container choice is not evidence of deletion.
      document['views']['7']['filter'] = {'op': 'folder', 'folder_id': 0};
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      await settle(tester);
      await tester.runAsync(() => tester.tap(find.byTooltip('Edit this view')));
      await settle(tester);
      expect(find.textContaining('This container was deleted'), findsNothing);
      await tester.runAsync(() => tester.tap(find.text('Cancel')));
      await settle(tester);
    },
  );

  testWidgets(
    'destructive preview remains usable with large text and a short viewport',
    (tester) async {
      placements['3'] = {
        'root': false,
        'parents': [2],
        'count': 1,
      };
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      tester.view.physicalSize = const Size(390, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIhtdTheme(),
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 360),
              textScaler: TextScaler.linear(1.8),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => removeItemPlacement(context, app, 3, 2),
              child: const Text('Remove'),
            ),
          ),
        ),
      );
      await tester.runAsync(() => tester.tap(find.text('Remove')));
      await settle(tester);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.runAsync(() => tester.tap(find.text('Cancel')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(commands.where((c) => c['op'] == 'remove_placement'), isEmpty);
    },
  );
  testWidgets('invalid draft blocks preview and removal', (tester) async {
    app.flushDraft = () async => false;
    expect(
      await tester.runAsync(
        () => app.removePlacement(3, null, confirmDelete: (_) async => true),
      ),
      false,
    );
    expect(
      commands.where(
        (c) => c['op'] == 'preview_removal' || c['op'] == 'remove_placement',
      ),
      isEmpty,
    );
  });

  testWidgets('deleting from phone details closes the removed item sheet', (
    tester,
  ) async {
    placements['3'] = {
      'root': false,
      'parents': [2],
      'count': 1,
    };
    document['root_order'] = [2];
    rows.removeWhere((r) => r['path'] == '3');
    await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
    await shell(tester, size: const Size(390, 844));
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('menu-2/3'))),
    );
    await settle(tester);
    await tester.runAsync(
      () => tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'details',
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    final list = find.descendant(
      of: find.byType(ItemEditor),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -1500));
    await settle(tester);
    final button = find.byKey(const ValueKey('remove-3-2'));
    await tester.ensureVisible(button);
    await tester.runAsync(() => tester.tap(button));
    await settle(tester);
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Delete')),
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(app.selectedItemId, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'switching to a copy with the same document ID invalidates approval',
    (tester) async {
      placements['3'] = {
        'root': false,
        'parents': [2],
        'count': 1,
      };
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      final removed = await tester.runAsync(
        () => app.removePlacement(
          3,
          2,
          confirmDelete: (_) async {
            working = '$working.copy';
            await app.dispatch({'op': 'snapshot'});
            return true;
          },
        ),
      );
      expect(removed, false);
      expect(commands.where((c) => c['op'] == 'remove_placement'), isEmpty);
      expect(app.error, contains('collection changed'));
    },
  );
}
