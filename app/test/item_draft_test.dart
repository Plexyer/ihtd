import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/services/item_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/item_draft_harness.dart';

class BlockingDiscardStore extends ItemDraftStore {
  Completer<void>? gate;
  @override
  Future<void> remove(String id) async {
    if (gate != null) await gate!.future;
    await super.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DraftHarness h;
  setUp(() async {
    h = DraftHarness();
    await h.initialize();
  });
  tearDown(() async {
    await h.dispose();
  });
  test('all editable fields stay private, Cancel discards them, immediate tag creation survives', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('title', 'Private title');
    h.app.changeItemDraft('notes', 'Private notes');
    h.app.changeItemDraft('auto_complete', true);
    h.app.changeItemDraft('priority', 3);
    final tag = await h.app.dispatch({'op': 'add_tag', 'name': 'New tag'});
    h.app.changeItemDraft('tag_ids', [tag!['id']]);
    await h.app.itemDrafts.flush();
    expect(h.doc['items']['3']['title'], 'Saved title');
    expect(h.doc['items']['3']['auto_complete'], false);
    final writes = h.adapter.writes;
    expect(await h.app.discardItemDraft(), true);
    expect(h.app.itemDraft, null);
    expect(h.adapter.writes, writes);
    expect(h.doc['tags']['${tag['id']}']['name'], 'New tag');
    expect(h.doc['items']['3']['tag_ids'], isEmpty);
  });
  test('Save commits fields and auto-completion once and closes; failures retain draft', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('title', 'Edited');
    h.app.changeItemDraft('auto_complete', true);
    h.failSave = true;
    expect(await h.app.saveItemDraft(), false);
    expect(h.app.itemDraft?.dirty, true);
    expect(h.doc['items']['3']['title'], 'Saved title');
    h.failSave = false;
    expect(await h.app.saveItemDraft(), true);
    expect(h.app.itemDraft, null);
    expect(h.doc['items']['3']['title'], 'Edited');
    expect(h.doc['items']['3']['auto_complete'], true);
    expect(h.adapter.writes, 1);
  });
  test('navigation prompts, Keep editing cancels switching, Discard affects no live fields', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'Unfinished');
    h.app.chooseDraftExit = (_, _) async => DraftExitChoice.keepEditing;
    await h.app.selectItem(2);
    expect(h.app.selectedItemId, 3);
    h.app.chooseDraftExit = (_, _) async => DraftExitChoice.discard;
    await h.app.selectItem(2);
    expect(h.app.selectedItemId, 2);
    expect(h.doc['items']['3']['notes'], 'Saved notes');
    expect(h.adapter.writes, 0);
  });
  test('outside existing editor saves only valid drafts; new outside always offers a choice', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('title', '');
    expect(
      await h.app.resolveItemDraft(
        reason: DraftExitReason.outside,
        close: true,
      ),
      false,
    );
    expect(h.app.itemDraft?.error, contains('title'));
    h.app.changeItemDraft('title', 'Outside save');
    expect(
      await h.app.resolveItemDraft(
        reason: DraftExitReason.outside,
        close: true,
      ),
      true,
    );
    expect(h.doc['items']['3']['title'], 'Outside save');
    await h.app.beginCreateDraft({});
    var asked = false;
    h.app.chooseDraftExit = (_, _) async {
      asked = true;
      return DraftExitChoice.keepEditing;
    };
    expect(
      await h.app.resolveItemDraft(
        reason: DraftExitReason.outside,
        close: true,
      ),
      false,
    );
    expect(asked, true);
  });
  test('draft journal reload restores privately and stale values cannot overwrite a changed item', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'Recover me');
    await h.app.itemDrafts.flush();
    final store = ItemDraftStore();
    await store.initialize(h.directory);
    final recovered = store.recovered.values.single;
    expect(recovered.values['notes'], 'Recover me');
    h.doc['items']['3']['notes'] = 'Newer saved notes';
    await h.app.discardItemDraft();
    expect(await h.app.restoreItemDraft(recovered), true);
    expect(await h.app.saveItemDraft(), false);
    expect(h.app.itemDraft?.values['notes'], 'Recover me');
    expect(h.doc['items']['3']['notes'], 'Newer saved notes');
  });
  test('returning to original values removes an older checkpoint; late writes cannot resurrect Cancel', () async {
    await h.app.selectItem(3);
    final id = h.app.itemDraft!.sessionId;
    h.app.changeItemDraft('notes', 'Transient');
    h.app.changeItemDraft('notes', 'Saved notes');
    await h.app.itemDrafts.flush();
    expect(
      await File('${h.app.itemDrafts.directory.path}/$id.json').exists(),
      false,
    );
    h.app.changeItemDraft('notes', 'Another transient');
    await h.app.discardItemDraft();
    await h.app.itemDrafts.flush();
    expect(
      await File('${h.app.itemDrafts.directory.path}/$id.json').exists(),
      false,
    );
  });
  test('interrupted accepted creation is recognized by receipt instead of creating a duplicate', () async {
    await h.app.beginCreateDraft({});
    h.app.changeItemDraft('title', 'One task');
    final draft = h.app.itemDraft!;
    final request = {...draft.command(), 'title': 'One task'};
    final plan = await h.app.dispatch({'op': 'preview_item_draft', ...request});
    draft.intent = {
      'digest': plan!['digest'],
      'id': plan['id'],
      'revision': plan['revision'],
    };
    await h.app.checkpointItemDraft();
    await h.app.dispatch({
      'op': 'save_item_draft',
      ...request,
      'expected_revision': plan['revision'],
      'expected_digest': plan['digest'],
    });
    final journal = jsonDecode(
      await File('${h.app.itemDrafts.directory.path}/${draft.sessionId}.json')
          .readAsString(),
    );
    h.app.itemDraft = null;
    final recovered = ItemDraft.fromJson(Map<String, dynamic>.from(journal));
    expect(await h.app.restoreItemDraft(recovered), true);
    expect(h.app.itemDraft, null);
    expect((h.doc['items'] as Map).length, 3);
    expect(h.app.error, contains('already saved'));
  });
  test('malformed known-version checkpoint stays on disk without opening an editor', () async {
    await h.app.selectItem(3);
    final data = h.app.itemDraft!.toJson();
    (data['values'] as Map)['tag_ids'] = 'invalid';
    final file = File('${h.app.itemDrafts.directory.path}/damaged.json');
    await file.writeAsString(jsonEncode(data));
    final reopened = ItemDraftStore();
    await reopened.initialize(h.directory);
    expect(reopened.recovered, isEmpty);
    expect(reopened.unreadableCount, 1);
    expect(await file.exists(), true);
  });
  test('complete newer temporary checkpoints recover; discard clears both files; unknown versions are retained', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'First checkpoint');
    await h.app.itemDrafts.flush();
    final draft = h.app.itemDraft!;
    draft.values['notes'] = 'Most recent checkpoint';
    draft.checkpointSerial++;
    final temp = File(
      '${h.app.itemDrafts.directory.path}/${draft.sessionId}.json.tmp',
    );
    await temp.writeAsString(jsonEncode(draft.toJson()), flush: true);
    final reopened = ItemDraftStore();
    await reopened.initialize(h.directory);
    expect(
      reopened.recovered.values.single.values['notes'],
      'Most recent checkpoint',
    );
    await reopened.remove(draft.sessionId);
    expect(await temp.exists(), false);
    final unknown = File('${h.app.itemDrafts.directory.path}/future.json');
    await unknown.writeAsString('{"version":99,"private":"keep"}');
    final unsupported = ItemDraftStore();
    await unsupported.initialize(h.directory);
    expect(unsupported.unreadableCount, 1);
    expect(await unknown.readAsString(), contains('keep'));
  });
  test(
    'an accepted Save whose response failed closes without a second creation',
    () async {
      await h.app.beginCreateDraft({});
      h.app.changeItemDraft('title', 'Accepted once');
      h.failAfterAccept = true;
      expect(await h.app.saveItemDraft(), true);
      expect(h.app.itemDraft, null);
      expect(
        (h.doc['items'] as Map).values.where(
          (item) => item['title'] == 'Accepted once',
        ),
        hasLength(1),
      );
      expect(
        h.commands.where((c) => c['op'] == 'save_item_draft'),
        hasLength(1),
      );
    },
  );
  test('typing or a lifecycle checkpoint during Cancel cannot resurrect the discarded draft', () async {
    await h.dispose();
    final store = BlockingDiscardStore();
    h = DraftHarness(store: store);
    await h.initialize();
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'Discard me');
    await h.app.itemDrafts.flush();
    final id = h.app.itemDraft!.sessionId;
    store.gate = Completer<void>();
    final cancellation = h.app.discardItemDraft();
    expect(h.app.discardingItemDraft, true);
    h.app.changeItemDraft('notes', 'Late input');
    await h.app.checkpointItemDraft();
    store.gate!.complete();
    expect(await cancellation, true);
    await store.flush();
    expect(await File('${store.directory.path}/$id.json').exists(), false);
    expect(h.app.itemDraft, null);
  });
  test('resolving Save for a separate operation rebases the draft and allows a later real Save', () async {
    await h.app.selectItem(3);
    h.app.changeItemDraft('notes', 'First saved note');
    expect(await h.app.saveItemDraft(close: false), true);
    expect(h.app.itemDraft?.accepted, false);
    h.app.changeItemDraft('notes', 'Second saved note');
    expect(await h.app.saveItemDraft(), true);
    expect(h.doc['items']['3']['notes'], 'Second saved note');
  });
  test(
    'late callbacks from an old editor cannot modify the next item draft',
    () async {
      await h.app.selectItem(3);
      final old = h.app.itemDraft!.sessionId;
      await h.app.selectItem(2);
      h.app.changeItemDraft('notes', 'Late old editor input', sessionId: old);
      expect(h.app.itemDraft?.values['notes'], '');
      expect(h.app.itemDraft?.dirty, false);
    },
  );
}
