import 'dart:convert';
import 'dart:io';
import 'dart:math';

Map<String, dynamic> cloneMap(Map source) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(source)));

enum DraftExitChoice { save, discard, keepEditing }

enum DraftExitReason { navigate, back, outside, operation }

/// No live document mutations. A session owns its baseline and editable values;
/// unrelated model refreshes never replace text controllers or this draft.
class ItemDraft {
  ItemDraft({
    required this.ownerPath,
    required this.documentId,
    required this.viewId,
    required this.view,
    required this.base,
    required this.values,
    this.itemId,
    this.parentId,
    String? sessionId,
  }) : sessionId =
           sessionId ??
           '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}',
       initial = cloneMap(values);
  final String sessionId, ownerPath, documentId;
  final int viewId;
  final Map<String, dynamic> view;
  Map<String, dynamic> base, values, initial;
  final int? itemId;
  int? parentId;
  Map<String, dynamic>? intent;
  String? error;
  int formRevision = 0;
  int checkpointSerial = 0;
  bool accepted = false;
  bool get isNew => itemId == null;
  bool get dirty => jsonEncode(values) != jsonEncode(initial);
  Map<String, dynamic> command() => {
    'id': itemId,
    'expected_item': base,
    'expected_view': view,
    'view_id': viewId,
    'parent_id': parentId,
    ...values,
  };
  Map<String, dynamic> toJson() => {
    'version': 1,
    'checkpoint': checkpointSerial,
    'session': sessionId,
    'ownerPath': ownerPath,
    'documentId': documentId,
    'viewId': viewId,
    'view': view,
    'base': base,
    'values': values,
    'initial': initial,
    'itemId': itemId,
    'parentId': parentId,
    'intent': intent,
  };
  factory ItemDraft.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        !RegExp(r'^[0-9]+-[a-f0-9]+$').hasMatch('${json['session']}')) {
      throw const FormatException('Unsupported draft');
    }
    for (final key in ['values', 'initial']) {
      final fields = json[key];
      if (fields is! Map ||
          fields['title'] is! String ||
          fields['notes'] is! String ||
          !['task', 'folder'].contains(fields['kind']) ||
          fields['priority'] is! int ||
          (fields['priority'] as int) < 0 ||
          (fields['priority'] as int) > 3 ||
          fields['auto_complete'] is! bool ||
          fields['completed'] is! bool ||
          (fields['due_date'] != null && fields['due_date'] is! String) ||
          fields['tag_ids'] is! List ||
          (fields['tag_ids'] as List).any((id) => id is! int || id <= 0)) {
        throw const FormatException('Invalid draft fields');
      }
    }
    final checkpoint = json['checkpoint'];
    if (checkpoint != null && (checkpoint is! int || checkpoint < 0)) {
      throw const FormatException('Invalid draft checkpoint');
    }
    return ItemDraft(
        ownerPath: json['ownerPath'] as String,
        documentId: json['documentId'] as String,
        viewId: json['viewId'] as int,
        view: cloneMap(json['view'] as Map),
        base: cloneMap(json['base'] as Map),
        values: cloneMap(json['values'] as Map),
        itemId: json['itemId'] as int?,
        parentId: json['parentId'] as int?,
        sessionId: json['session'] as String,
      )
      ..checkpointSerial = json['checkpoint'] as int? ?? 0
      ..initial = cloneMap(json['initial'] as Map)
      ..intent = json['intent'] is Map ? cloneMap(json['intent']) : null;
  }
  void rebase(Map<String, dynamic> item) {
    formRevision++;
    base = cloneMap(item);
    values = editable(item);
    initial = cloneMap(values);
    intent = null;
    accepted = false;
    error = null;
  }

  static Map<String, dynamic> editable(Map item) => {
    'title': item['title'] ?? '',
    'notes': item['notes'] ?? '',
    'kind': item['kind'] ?? 'task',
    'due_date': item['due_date'],
    'priority': item['priority'] ?? 0,
    'tag_ids': List<int>.from(item['tag_ids'] as List? ?? []),
    'auto_complete': item['auto_complete'] == true,
    'completed': item['completed'] == true,
  };
}

/// Private content-bearing files, never included in diagnostic exports. Writes
/// and removals serialize so a late checkpoint cannot resurrect a cancelled draft.
class ItemDraftStore {
  late Directory directory;
  final Map<String, ItemDraft> recovered = {};
  int unreadableCount = 0;
  Future<void> _writes = Future.value();
  Future<void> initialize(Directory support) async {
    directory = Directory('${support.path}/item-drafts');
    await directory.create(recursive: true);
    await for (final file in directory.list()) {
      if (file is! File ||
          !(file.path.endsWith('.json') || file.path.endsWith('.json.tmp'))) {
        continue;
      }
      try {
        final draft = ItemDraft.fromJson(
          cloneMap(jsonDecode(await file.readAsString()) as Map),
        );
        final previous = recovered[draft.sessionId];
        if (previous == null ||
            draft.checkpointSerial > previous.checkpointSerial) {
          recovered[draft.sessionId] = draft;
        }
      } catch (_) {
        unreadableCount++;
        /* Unknown/unreadable drafts are retained, never rewritten. */
      }
    }
  }

  Future<void> put(ItemDraft draft) {
    draft.checkpointSerial++;
    final bytes = jsonEncode(draft.toJson());
    final task = _writes.then((_) async {
      final file = File('${directory.path}/${draft.sessionId}.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(bytes, flush: true);
      await temp.rename(file.path);
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> remove(String id) {
    final task = _writes.then((_) async {
      for (final suffix in ['.json', '.json.tmp']) {
        final file = File('${directory.path}/$id$suffix');
        if (await file.exists()) await file.delete();
      }
      recovered.remove(id);
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> flush() => _writes;
}
