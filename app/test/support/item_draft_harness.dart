import 'dart:convert';
import 'dart:io';

import 'package:app/services/app_controller.dart';
import 'package:app/services/document_save_coordinator.dart';
import 'package:app/services/item_draft.dart';

import '../document_contract_test.dart' show FakeAdapter;

class MemoryDraftStore extends ItemDraftStore {
  @override
  Future<void> initialize(Directory support) async {
    directory = Directory('${support.path}/item-drafts');
  }

  @override
  Future<void> put(ItemDraft draft) async {}
  @override
  Future<void> remove(String id) async {
    recovered.remove(id);
  }

  @override
  Future<void> flush() async {}
}

class DraftHarness {
  DraftHarness({this.memoryDrafts = false, this.store});
  final ItemDraftStore? store;
  final bool memoryDrafts;
  late Directory directory;
  late String working;
  late FakeAdapter adapter;
  late DocumentSaveCoordinator storage;
  late AppController app;
  final List<Map<String, dynamic>> commands = [];
  bool failSave = false, failAfterAccept = false;
  Map<String, dynamic> doc = {
    'schema_version': 2,
    'document_id': 'draft-test',
    'revision': 1,
    'next_id': 5,
    'items': {
      '2': {
        'id': 2,
        'kind': 'folder',
        'title': 'Folder',
        'notes': '',
        'due_date': null,
        'priority': 0,
        'tag_ids': [],
        'auto_complete': false,
        'completed': false,
      },
      '3': {
        'id': 3,
        'kind': 'task',
        'title': 'Saved title',
        'notes': 'Saved notes',
        'due_date': null,
        'priority': 0,
        'tag_ids': [],
        'auto_complete': false,
        'completed': false,
      },
    },
    'tags': {},
    'links': [],
    'root_order': [2, 3],
    'views': {
      '1': {
        'id': 1,
        'name': 'All tasks',
        'filter': {'op': 'all'},
        'preferences': {},
      },
    },
  };
  Map<String, dynamic> snapshot() => {
    'document': doc,
    'path': working,
    'dirty': false,
    'completion': {},
    'collection_settings':
        doc['collection_settings'] ??
        {
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
        },
    'placements': {
      '2': {'root': true, 'count': 1},
      '3': {'root': true, 'count': 1},
    },
  };
  Map<String, dynamic> proposal(Map<String, dynamic> request) {
    final candidate = cloneMap(doc);
    final id = request['id'] as int? ?? candidate['next_id'] as int;
    if (request['id'] == null) {
      candidate['next_id'] = id + 1;
      (candidate['root_order'] as List).add(id);
    }
    candidate['items']['$id'] = {
      ...Map<String, dynamic>.from(candidate['items']['$id'] as Map? ?? {}),
      'id': id,
      for (final key in [
        'kind',
        'title',
        'notes',
        'due_date',
        'priority',
        'tag_ids',
        'auto_complete',
        'completed',
      ])
        key: request[key],
    };
    candidate['revision'] = (candidate['revision'] as int) + 1;
    return candidate;
  }

  Future<String> command(String input) async {
    final request = cloneMap(jsonDecode(input) as Map);
    commands.add(request);
    var data = <String, dynamic>{};
    bool ok = true;
    switch (request['op']) {
      case 'rank_tags':
        final tags = (doc['tags'] as Map).values.toList()
          ..sort(
            (a, b) => '${a['name']}'.toLowerCase().compareTo(
              '${b['name']}'.toLowerCase(),
            ),
          );
        data = {'order': tags.map((t) => t['id']).toList()};
      case 'preview_item_draft':
        if (request['id'] != null &&
            jsonEncode(request['expected_item']) !=
                jsonEncode(doc['items']['${request['id']}'])) {
          ok = false;
          break;
        }
        final candidate = proposal(request);
        data = {
          'id': request['id'] ?? doc['next_id'],
          'digest': jsonEncode(candidate),
          'revision': doc['revision'],
        };
      case 'save_item_draft':
        if (failSave || request['expected_revision'] != doc['revision']) {
          ok = false;
          break;
        }
        final candidate = proposal(request);
        if (jsonEncode(candidate) != request['expected_digest']) {
          ok = false;
          break;
        }
        doc = candidate;
        await File(working).writeAsString(jsonEncode(doc));
        data = {'id': request['id'] ?? (doc['next_id'] as int) - 1};
        if (failAfterAccept) ok = false;
      case 'item_draft_status':
        data = {'committed': request['digest'] == jsonEncode(doc)};
      case 'query':
        data = {'rows': []};
      case 'creation_defaults':
        data = {'tag_ids': [], 'requirements': []};
      case 'set_preferences':
        doc['views']['${request['view_id']}']['preferences']['${request['item_id']}'] =
            request['preferences'];
        doc['revision']++;
        await File(working).writeAsString(jsonEncode(doc));
      case 'add_tag':
        final id = doc['next_id'] as int;
        doc['next_id'] = id + 1;
        doc['tags']['$id'] = {'id': id, 'name': request['name']};
        doc['revision']++;
        await File(working).writeAsString(jsonEncode(doc));
        data = {'id': id};
    }
    return jsonEncode({
      'ok': ok,
      'data': data,
      'snapshot': snapshot(),
      'error': ok
          ? null
          : 'The item changed or could not be saved. Draft retained.',
    });
  }

  Future<void> initialize() async {
    directory = await Directory.systemTemp.createTemp('ihtd-item-draft-');
    working = '${directory.path}/working.ihtd';
    await File(working).writeAsString('baseline');
    adapter = FakeAdapter('filesystem');
    storage = DocumentSaveCoordinator(
      adapter: adapter,
      supportDirectory: () async => directory,
    );
    await storage.initialize();
    await storage.attach({
      'reference': adapter.referenceFor('selected').toJson(),
      'path': working,
      'name': adapter.name,
      'hash': adapter.contents,
      'identity': adapter.identity,
    });
    app = AppController(
      documentServices: storage,
      draftStore: store ?? (memoryDrafts ? MemoryDraftStore() : null),
      command: command,
      supportDirectory: () async => directory,
      polling: false,
    );
    await app.ready;
  }

  Future<void> dispose() async {
    app.dispose();
    await app.itemDrafts.flush();
    await storage.diagnostics.flush();
    await directory.delete(recursive: true);
  }
}
