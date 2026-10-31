import 'dart:convert';

import 'package:app/ui/link_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';
import 'support/settle_controller.dart';

class LinkHarness extends DraftHarness {
  LinkHarness() : super(memoryDrafts: true);
  @override
  Future<String> command(String input) async {
    final request = jsonDecode(input) as Map<String, dynamic>;
    if (request['op'] == 'copy_options' || request['op'] == 'link_or_copy') {
      commands.add(request);
      return jsonEncode({
        'ok': true,
        'snapshot': snapshot(),
        'data': request['op'] == 'copy_options'
            ? {
                'descendants': [3],
                'max_depth': 2,
                'revision': doc['revision'],
              }
            : {'id': 5},
      });
    }
    return super.command(input);
  }
}

void main() {
  late LinkHarness h;
  setUp(() async {
    h = LinkHarness();
    await h.initialize();
    h.doc['items']['4'] = <String, Object?>{
      ...h.doc['items']['3'],
      'id': 4,
      'title': 'Destination',
    };
    h.doc['links'] = [
      {'parent': 2, 'child': 3},
    ];
    h.doc['root_order'] = [2, 4];
  });
  tearDown(() async {
    await h.dispose();
  });
  Future<void> settle(WidgetTester tester) => settleController(tester, h.app);

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLinkCopy(context, h.app, 2),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('Open')));
    await settle(tester);
  }

  Future<void> copyMode(WidgetTester tester) async {
    final mode = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField<bool>,
    );
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Link defaults exclude source/descendants; searchable destination and one action send a guarded command',
    (tester) async {
      await mount(tester);
      expect(find.byKey(const ValueKey('destination-2')), findsNothing);
      expect(find.byKey(const ValueKey('destination-3')), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byWidgetPredicate(
                (w) => w is DropdownButtonFormField<String>,
              ),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.byTooltip('About linking and copying'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Link: show the same item'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('destination-4')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('Link to')));
      await settle(tester);
      final op = h.commands.lastWhere((c) => c['op'] == 'link_or_copy');
      expect(op['source'], 2);
      expect(op['destination'], 4);
      expect(op['mode'], 'link');
      expect(op['expected_revision'], 1);
      expect(find.text('Link / copy task to'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Copy defaults source-only, retains links, and self/child destination locks All descendants',
    (tester) async {
      await mount(tester);
      await copyMode(tester);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      var depth = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
      );
      expect(depth.initialValue, '0');
      expect(depth.onChanged, isNotNull);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('destination-3'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('destination-3')));
      await tester.pumpAndSettle();
      depth = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
      );
      expect(depth.initialValue, 'all');
      expect(depth.onChanged, isNull);
      expect(find.textContaining('requires All descendants'), findsOneWidget);
      await tester.ensureVisible(find.text('Copy to'));
      await tester.runAsync(() => tester.tap(find.text('Copy to')));
      await settle(tester);
      final op = h.commands.lastWhere((c) => c['op'] == 'link_or_copy');
      expect(op['depth'], null);
      expect(op['independent'], false);
      expect(op['destination'], 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Copy Cancel makes no model change', (tester) async {
    await mount(tester);
    await copyMode(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(h.commands.where((c) => c['op'] == 'link_or_copy'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('narrow short large-text Link/Copy controls stay reachable', (
    tester,
  ) async {
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
              onPressed: () => showLinkCopy(context, h.app, 2),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('Open')));
    await settle(tester);
    await tester.ensureVisible(find.byTooltip('About linking and copying'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('About linking and copying'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Link / copy task to'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
