import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/filesystem_documents.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/view_editor.dart';
import 'package:app/ui/rule_expression.dart';
import 'package:app/ui/rule_condition_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/settle_controller.dart';

void main() {
  late Directory directory;
  late AppController app;
  late Map<String, dynamic> document;
  late List<Map<String, dynamic>> commands;
  late String working;
  bool reject = false;
  late GlobalKey captureKey;
  Map<String, dynamic> priority(int value) => {
    'op': 'priority',
    'comparison': 'eq',
    'value': value,
  };
  Map<String, dynamic> and(List<Map<String, dynamic>> values) => {
    'op': 'and',
    'rules': values,
  };
  Map<String, dynamic> or(List<Map<String, dynamic>> values) => {
    'op': 'or',
    'rules': values,
  };
  Map<String, dynamic> view() =>
      Map<String, dynamic>.from(document['views']['2'] as Map);

  setUp(() async {
    reject = false;
    captureKey = GlobalKey();
    const font = String.fromEnvironment('EXPRESSION_FONT');
    if (font.isNotEmpty) {
      await (FontLoader(
        'Segoe UI',
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
      await (FontLoader('MaterialIcons')..addFont(
            File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    }
    directory = await Directory.systemTemp.createTemp('ihtd-expression-');
    working = '${directory.path}/working.ihtd';
    commands = [];
    document = {
      'document_id': 'same-uuid',
      'revision': 1,
      'items': {
        '9': {'id': 9, 'title': 'Trip', 'kind': 'folder'},
        '10': {'id': 10, 'title': 'Trip', 'kind': 'task'},
      },
      'tags': {
        '1': {'id': 1, 'name': 'Packing'},
      },
      'deleted_item_ids': [],
      'views': {
        '1': {
          'id': 1,
          'name': 'All',
          'filter': {'op': 'all'},
        },
        '2': {
          'id': 2,
          'name': 'Travel',
          'filter': and([
            priority(1),
            or([priority(2), priority(3)]),
          ]),
          'preferences': {},
        },
      },
    };
    PackageInfo.setMockInitialValues(
      appName: 'IHTD',
      packageName: 'dev.ihtd.app',
      version: '0.2.2',
      buildNumber: '10',
      buildSignature: '',
    );
    Future<String> command(String raw) async {
      final c = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      commands.add(c);
      if (!reject && c['op'] == 'edit_view') {
        document['views']['2']['filter'] = c['filter'];
        document['views']['2']['name'] = c['name'];
      }
      return jsonEncode({
        'ok': !reject || c['op'] != 'edit_view',
        'error': 'Simulated save failure',
        'data': {'rows': [], if (c['op'] == 'add_view') 'id': 3},
        'snapshot': {
          'path': working,
          'document': document,
          'completion': {},
          'placements': {},
          'view_issues': {},
        },
      });
    }

    app = AppController(
      command: command,
      polling: false,
      supportDirectory: () async => directory,
      documentServices: DocumentSaveCoordinator(
        adapter: FilesystemDocumentAdapter(command),
        supportDirectory: () async => directory,
      ),
    );
    await app.ready;
  });
  tearDown(() async {
    app.dispose();
    await app.documentServices.diagnostics.flush();
    await directory.delete(recursive: true);
  });

  Future<void> host(
    WidgetTester tester, {
    bool create = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIhtdTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: captureKey, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showViewEditor(
                context,
                app,
                existing: create ? null : view(),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    const root = String.fromEnvironment('EXPRESSION_CAPTURE');
    if (root.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(root).create(recursive: true);
      await File('$root/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) => settleController(tester, app);

  Future<void> addHigh(WidgetTester tester, Finder plus) async {
    await tap(tester, plus);
    await tap(tester, find.byKey(const ValueKey('pick-priority')));
    final field = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<int> &&
          w.decoration.labelText == 'Priority',
    );
    await tap(tester, field);
    await tap(tester, find.text('High').last);
    await tap(tester, find.text('Done'));
  }

  testWidgets(
    'inner and outer pluses add only to selected chain; outer cancel publishes nothing',
    (tester) async {
      await host(tester);
      await capture(tester, 'phone-mixed');
      await addHigh(tester, find.byTooltip('Add OR condition'));
      final expression = tester.widget<RuleExpression>(
        find.byType(RuleExpression),
      );
      expect(
        expression.draft.encode(),
        and([
          priority(1),
          or([priority(2), priority(3), priority(3)]),
        ]),
      );
      await addHigh(tester, find.byTooltip('Add AND condition'));
      expect(
        expression.draft.encode(),
        and([
          priority(1),
          or([priority(2), priority(3), priority(3)]),
          priority(3),
        ]),
      );
      await tap(tester, find.text('Cancel'));
      expect(commands.where((c) => c['op'] == 'edit_view'), isEmpty);
      expect(
        view()['filter'],
        and([
          priority(1),
          or([priority(2), priority(3)]),
        ]),
      );
    },
  );
  testWidgets(
    'new AND starts two slots; incomplete save is blocked and form cancel keeps slot',
    (tester) async {
      await host(tester, create: true);
      await tap(tester, find.byTooltip('Fill empty condition'));
      await tap(tester, find.byKey(const ValueKey('pick-and')));
      expect(find.byTooltip('Fill empty condition'), findsNWidgets(2));
      await capture(tester, 'phone-empty-and');
      await tap(tester, find.text('Save view'));
      expect(
        find.textContaining('Fill or remove each empty condition'),
        findsOneWidget,
      );
      expect(commands.where((c) => c['op'] == 'add_view'), isEmpty);
      await tap(tester, find.byTooltip('Fill empty condition').first);
      await tap(tester, find.byKey(const ValueKey('pick-text')));
      await tester.enterText(find.byType(TextFormField), 'discard');
      await tap(tester, find.text('Cancel').last);
      expect(find.byTooltip('Fill empty condition'), findsNWidgets(2));
    },
  );
  testWidgets(
    'connector changes retain operands and save isolated draft once',
    (tester) async {
      await host(tester);
      await tap(tester, find.text('AND').first);
      await tap(tester, find.byKey(const ValueKey('connector-or')));
      expect(
        tester
            .widget<RuleExpression>(find.byType(RuleExpression))
            .draft
            .encode(),
        or([
          priority(1),
          or([priority(2), priority(3)]),
        ]),
      );
      await tester.runAsync(() => tester.tap(find.text('Save view')));
      await settle(tester);
      expect(commands.where((c) => c['op'] == 'edit_view').length, 1);
      expect(
        view()['filter'],
        or([
          priority(1),
          or([priority(2), priority(3)]),
        ]),
      );
      expect(find.byType(RuleExpression), findsNothing);
    },
  );
  testWidgets('name-only save preserves nested OR shape, IDs and preferences', (
    tester,
  ) async {
    document['views']['2']['filter'] = or([
      {'op': 'tag', 'tag_id': 1},
      or([
        {'op': 'tag', 'tag_id': 1},
      ]),
    ]);
    final original = jsonDecode(jsonEncode(view()['filter']));
    await host(tester);
    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.runAsync(() => tester.tap(find.text('Save view')));
    await settle(tester);
    expect(view()['filter'], original);
    expect(view()['preferences'], {});
    expect(view()['id'], 2);
  });
  testWidgets(
    'failed save keeps draft and a same-UUID working-copy switch is rejected',
    (tester) async {
      await host(tester);
      reject = true;
      await tester.enterText(find.byType(TextField), 'Keep draft');
      await tester.runAsync(() => tester.tap(find.text('Save view')));
      await settle(tester);
      expect(find.textContaining('Simulated save failure'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep draft',
      );
      reject = false;
      working = '${directory.path}/other-copy.ihtd';
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      final edits = commands.where((c) => c['op'] == 'edit_view').length;
      await tester.runAsync(() => tester.tap(find.text('Save view')));
      await settle(tester);
      expect(commands.where((c) => c['op'] == 'edit_view').length, edits);
      expect(find.textContaining('open collection changed'), findsOneWidget);
    },
  );
  testWidgets(
    'stale view edits are rejected without overwriting current rules',
    (tester) async {
      await host(tester);
      document['views']['2']['filter'] = priority(0);
      await tester.runAsync(() => app.dispatch({'op': 'snapshot'}));
      await tester.runAsync(() => tester.tap(find.text('Save view')));
      await settle(tester);
      expect(commands.where((c) => c['op'] == 'edit_view'), isEmpty);
      expect(find.textContaining('view changed while'), findsOneWidget);
    },
  );
  testWidgets('searchable container picker identifies duplicate names by ID', (
    tester,
  ) async {
    await host(tester, create: true);
    await tap(tester, find.byTooltip('Fill empty condition'));
    await tap(tester, find.byKey(const ValueKey('pick-folder')));
    await tap(tester, find.byKey(const ValueKey('choose-rule-reference')));
    await tester.enterText(find.byType(TextField).last, '#10');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reference-9')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('reference-10')));
    await tap(tester, find.text('Done'));
    expect(
      tester
          .widget<RuleExpression>(find.byType(RuleExpression))
          .draft
          .encode()['folder_id'],
      10,
    );
    expect(find.textContaining('Trip (#10)'), findsOneWidget);
  });
  test(
    'collection guard is checked after waiting in the command queue',
    () async {
      final identity = app.editIdentity;
      app.busy = true;
      final result = app.dispatch({
        'op': 'edit_view',
        'id': 2,
        'name': 'Queued',
        'filter': priority(0),
      }, expectedDocument: identity);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      app.document!['document_id'] = 'changed-while-waiting';
      app.busy = false;
      expect(await result, isNull);
      expect(commands.where((c) => c['op'] == 'edit_view'), isEmpty);
    },
  );
  testWidgets(
    'focused leaf forms retain case-sensitive text and remove unused date values',
    (tester) async {
      await host(tester);
      final context = tester.element(find.byType(RuleExpression));
      Future<Map<String, dynamic>?> show(Map<String, dynamic> rule) =>
          editCondition(context, app, rule, app.editIdentity);
      final text = show({
        'op': 'text',
        'field': 'notes',
        'comparison': 'not_contains',
        'value': 'old',
        'case_sensitive': false,
      });
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Invoice 123');
      await tap(tester, find.byType(CheckboxListTile));
      await tap(tester, find.text('Done'));
      expect(await text, {
        'op': 'text',
        'field': 'notes',
        'comparison': 'not_contains',
        'value': 'Invoice 123',
        'case_sensitive': true,
      });
      final date = show({
        'op': 'due',
        'comparison': 'before',
        'value': '2026-10-31',
      });
      await tester.pumpAndSettle();
      final comparison = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Comparison',
      );
      await tap(tester, comparison);
      await tap(tester, find.text('No due date').last);
      expect(find.text('2026-10-31'), findsNothing);
      await tap(tester, find.text('Done'));
      expect(await date, {
        'op': 'due',
        'comparison': 'is_not_set',
        'value': null,
      });
      final container = show({
        'op': 'folder',
        'folder_id': 10,
        'recursive': true,
      });
      await tester.pumpAndSettle();
      await tap(tester, find.byType(CheckboxListTile));
      await tap(tester, find.text('Done'));
      expect(await container, {
        'op': 'folder',
        'folder_id': 10,
        'recursive': false,
      });
      expect(commands.where((c) => c['op'] == 'edit_view'), isEmpty);
    },
  );
  for (final scenario in [
    (size: const Size(1440, 900), scale: 1.0),
    (size: const Size(320, 640), scale: 2.0),
  ]) {
    testWidgets(
      'mixed first group, exactly-one and long values fit ${scenario.size} at ${scenario.scale}x',
      (tester) async {
        document['views']['2']['filter'] = and([
          or([priority(1), priority(2)]),
          {
            'op': 'xor',
            'rules': [
              {
                'op': 'text',
                'field': 'title',
                'comparison': 'contains',
                'value': 'Long title ' * 20,
              },
              priority(2),
              priority(3),
            ],
          },
        ]);
        await host(tester, size: scenario.size, scale: scenario.scale);
        await capture(
          tester,
          'mixed-${scenario.size.width.toInt()}-${scenario.scale}',
        );
        expect(find.text('('), findsNWidgets(2));
        expect(find.text(')'), findsNWidgets(2));
        await tester.ensureVisible(find.byTooltip('Add AND condition'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Cancel'));
        await tap(tester, find.text('Cancel'));
      },
    );
  }
}
