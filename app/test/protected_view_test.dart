import 'dart:convert';
import 'dart:io';

import 'package:app/services/item_draft.dart';
import 'package:app/ui/view_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';

void main() {
  late DraftHarness h;
  setUp(() async {
    h = DraftHarness(memoryDrafts: true);
    h.doc['all_tasks_view_id'] = 9;
    h.doc['views']['1']['name'] = 'Preserved customized view';
    h.doc['views']['9'] = {
      'id': 9,
      'name': 'All tasks',
      'filter': {'op': 'all'},
      'preferences': {},
      'sorting': {},
    };
    h.doc['next_id'] = 10;
    await h.initialize();
  });
  tearDown(() async => h.dispose());

  test(
    'new owners select the protected ID rather than the customized original',
    () async {
      expect(h.app.selectedViewId, 9);
      expect(h.app.isProtectedView(9), true);
      expect(h.app.isProtectedView(1), false);
      await h.app.selectView(1);
      expect(h.app.selectedViewId, 1);
      h.working = '${h.working}-different-copy';
      await h.app.dispatch({'op': 'snapshot'});
      expect(h.app.selectedViewId, 9);
    },
  );
  test(
    'a newer recovery that consumed a proposed item ID cannot replay creation',
    () async {
      h.doc = Map<String, dynamic>.from(jsonDecode(jsonEncode(h.doc)) as Map);
      final protected = Map<String, dynamic>.from(h.doc['views']['9'] as Map);
      h.doc['views'].remove('9');
      h.doc['views']['10'] = {...protected, 'id': 10};
      h.doc['all_tasks_view_id'] = 10;
      h.doc['next_id'] = 11;
      h.doc['items']['9'] = {
        ...h.doc['items']['3'] as Map,
        'id': 9,
        'title': 'Saved before interruption',
      };
      await h.app.dispatch({'op': 'snapshot'});
      final old = File('${h.directory.path}/original-working');
      await old.writeAsString('immutable-old-source');
      final job = {
        'id': '1793404800000000-abc',
        'status': 'completed',
        'plans': ['protected-all-tasks'],
        'candidateValidated': true,
        'prepared': {'path': h.working},
        'candidates': [
          {
            'role': 'path',
            'path': h.working,
            'sourcePath': old.path,
            'sourceHash': 'immutable-old-source',
            'sourceDigest': 'older-working-digest',
            'sourceNextId': 9,
          },
        ],
      };
      await File(
        '${h.storage.migrations.directory.path}/${job['id']}.attempt.json',
      ).writeAsString(jsonEncode(job));
      final draft = ItemDraft(
        ownerPath: old.path,
        documentId: 'draft-test',
        viewId: 1,
        view: Map<String, dynamic>.from(h.doc['views']['1'] as Map),
        base: {},
        values: ItemDraft.editable(h.doc['items']['9'] as Map),
      );
      draft.intent = {
        'id': 9,
        'digest': 'creation-saved-in-newer-recovery',
        'revision': 1,
      };
      final before = jsonEncode(h.doc);
      expect(await h.app.restoreItemDraft(draft), false);
      expect(h.app.error, contains('may already have been saved'));
      expect(h.app.itemDraft, null);
      expect(jsonEncode(h.doc), before);
      expect(draft.intent!['id'], 9);
      expect(h.commands.where((c) => c['op'] == 'save_item_draft'), isEmpty);
    },
  );
  testWidgets(
    'protected information cannot rename/filter/delete or resolve a private draft',
    (tester) async {
      await tester.runAsync(() => h.app.selectItem(3));
      h.app.changeItemDraft('notes', 'Keep editing');
      var resolutions = 0;
      h.app.flushDraft = () async {
        resolutions++;
        return false;
      };
      final session = h.app.itemDraft!.sessionId;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showViewEditor(
                  context,
                  h.app,
                  existing: Map<String, dynamic>.from(
                    h.doc['views']['9'] as Map,
                  ),
                ),
                child: const Text('About'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.text('All tasks'), findsOneWidget);
      expect(
        find.textContaining('sorting and display preferences'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Save view'), findsNothing);
      expect(find.text('Delete view'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(resolutions, 0);
      expect(h.app.itemDraft!.sessionId, session);
      expect(h.app.itemDraft!.values['notes'], 'Keep editing');
      expect(
        h.commands.where((c) => ['edit_view', 'remove_view'].contains(c['op'])),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
