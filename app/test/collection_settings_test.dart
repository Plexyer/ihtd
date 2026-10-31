import 'dart:convert';
import 'dart:io';

import 'package:app/services/item_draft.dart';
import 'package:app/ui/collection_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';
import 'support/settle_controller.dart';

class SettingsHarness extends DraftHarness {
  SettingsHarness() : super(memoryDrafts: true);
  Map<String, dynamic> settings = {
    'tag_suggestion_count': 5,
    'tag_half_life_days': 3,
    'indicators': {
      'total': true,
      'completed_ratio': false,
      'high_priority': true,
      'medium_priority': false,
      'low_priority': false,
      'next_due_date': false,
    },
  };
  @override
  Map<String, dynamic> snapshot() => {
    ...super.snapshot(),
    'collection_settings': settings,
  };
  @override
  Future<String> command(String encoded) async {
    final request = jsonDecode(encoded) as Map<String, dynamic>;
    if (![
      'set_collection_settings',
      'set_indicator_settings',
    ].contains(request['op'])) {
      return super.command(encoded);
    }
    commands.add(request);
    if (request['op'] == 'set_collection_settings') {
      settings = cloneMap(request['settings']);
      doc['collection_settings'] = settings;
    } else {
      doc['parent_indicator_defaults'] = {
        '${request['item_id']}': request['parent_overrides'],
      };
      doc['views']['${request['view_id']}']['preferences']['${request['item_id']}'] =
          {'indicators': request['view_overrides']};
    }
    doc['revision']++;
    await File(working).writeAsString(jsonEncode(doc));
    return jsonEncode({'ok': true, 'data': {}, 'snapshot': snapshot()});
  }
}

void main() {
  late SettingsHarness h;
  setUp(() async {
    h = SettingsHarness();
    await h.initialize();
  });
  tearDown(() async {
    await h.dispose();
  });
  Future<void> settle(WidgetTester tester) => settleController(tester, h.app);

  Future<void> mount(WidgetTester tester, {bool parent = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => parent
                  ? showIndicatorSettings(context, h.app, itemId: 2, viewId: 1)
                  : showCollectionSettings(context, h.app),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> choice(
    WidgetTester tester,
    String keyPrefix,
    String label,
  ) async {
    final finder = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.key.toString().contains(keyPrefix),
    );
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('collection defaults, validation, Cancel and Save are isolated', (
    tester,
  ) async {
    await mount(tester);
    expect(
      tester
          .widget<TextField>(field('Suggested unselected tags'))
          .controller!
          .text,
      '5',
    );
    expect(
      tester
          .widget<TextField>(field('Tag usage half-life (days)'))
          .controller!
          .text,
      '3',
    );
    await tester.enterText(field('Suggested unselected tags'), '8');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(h.settings['tag_suggestion_count'], 5);
    expect(
      h.commands.where((c) => c['op'] == 'set_collection_settings'),
      isEmpty,
    );
    await tester.tap(find.text('Open settings'));
    await settle(tester);
    await tester.enterText(field('Tag usage half-life (days)'), '0');
    await tester.runAsync(() => tester.tap(find.text('Save settings')));
    await settle(tester);
    expect(find.text('Enter a positive whole number of days.'), findsOneWidget);
    expect(h.settings['tag_half_life_days'], 3);
    await tester.enterText(field('Tag usage half-life (days)'), '7');
    await tester.enterText(field('Suggested unselected tags'), '0');
    await tester.runAsync(() => tester.tap(find.text('Save settings')));
    await settle(tester);
    expect(
      find.text('Collection Settings'),
      findsNothing,
      reason: '${h.app.error}; busy=${h.app.busy}',
    );
    expect(h.settings['tag_suggestion_count'], 0);
    expect(h.settings['tag_half_life_days'], 7);
    expect(h.settings['indicators']['total'], true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'parent and view overrides save independently of an unfinished item draft',
    (tester) async {
      await h.app.selectItem(2);
      h.app.changeItemDraft('notes', 'Still private');
      await mount(tester, parent: true);
      expect(find.text('From collection defaults: On'), findsWidgets);
      await choice(tester, 'view-total-', 'Off');
      await tester.ensureVisible(find.text('Shared parent defaults'));
      await tester.tap(find.text('Shared parent defaults'));
      await tester.pumpAndSettle();
      await choice(tester, 'parent-next_due_date-', 'On');
      await tester.ensureVisible(find.text('Save settings'));
      await tester.runAsync(() => tester.tap(find.text('Save settings')));
      await settle(tester);
      final command = h.commands.lastWhere(
        (c) => c['op'] == 'set_indicator_settings',
      );
      expect(command['parent_overrides'], {'next_due_date': true});
      expect(command['view_overrides'], {'total': false});
      expect(h.app.itemDraft!.values['notes'], 'Still private');
      expect(h.doc['items']['2']['notes'], '');
      await h.app.discardItemDraft();
      expect(
        h.doc['views']['1']['preferences']['2']['indicators']['total'],
        false,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('collection Settings respects Keep editing before it opens', (
    tester,
  ) async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('title', 'Private');
    h.app.chooseDraftExit = (_, _) async => DraftExitChoice.keepEditing;
    await mount(tester);
    expect(find.text('Collection Settings'), findsNothing);
    expect(h.app.itemDraft!.values['title'], 'Private');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('settings cannot overwrite another collection after a switch', (
    tester,
  ) async {
    await mount(tester);
    h.doc['document_id'] = 'another-collection';
    await tester.runAsync(() => h.app.dispatch({'op': 'snapshot'}));
    await tester.enterText(field('Suggested unselected tags'), '9');
    await tester.runAsync(() => tester.tap(find.text('Save settings')));
    await settle(tester);
    expect(
      h.commands.where((c) => c['op'] == 'set_collection_settings'),
      isEmpty,
    );
    expect(
      find.text(
        'The open collection changed. Reopen the editor for this collection.',
      ),
      findsOneWidget,
    );
    expect(h.settings['tag_suggestion_count'], 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'short narrow large-text settings keep fields and actions reachable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCollectionSettings(context, h.app),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open settings'));
      await settle(tester);
      await tester.ensureVisible(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => tester.tap(find.text('Save settings')));
      await settle(tester);
      expect(find.text('Collection Settings'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
