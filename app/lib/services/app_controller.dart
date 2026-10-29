import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/simple.dart' as api;
import 'document_save_coordinator.dart';
import 'document_adapter.dart';
import 'document_composition.dart';
import 'migration_contract.dart';
import 'item_draft.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => AppController(),
);

typedef DocumentEditIdentity = ({String? workingPath, String? documentId});

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    this.initialDocumentPath,
    DocumentSaveCoordinator? documentServices,
    Future<String> Function(String)? command,
    Future<Directory> Function()? supportDirectory,
    bool polling = true,
    ItemDraftStore? draftStore,
  }) : itemDrafts = draftStore ?? ItemDraftStore(),
       _documents =
           documentServices ??
           composeDocumentServices(
             command ?? ((request) => api.command(request: request)),
           ),
       _command = command ?? ((request) => api.command(request: request)),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory {
    _documents.migrations.command = _command;
    WidgetsBinding.instance.addObserver(this);
    _documents.onStateChanged = _syncDocumentStatus;
    ready = _initialize();
    if (polling) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    }
  }
  final String? initialDocumentPath;
  late final Future<void> ready;
  Timer? _timer;
  bool busy = false;
  bool _polling = false;
  bool _disposed = false;
  bool _mutating = false;
  final DocumentSaveCoordinator _documents;
  final Future<String> Function(String) _command;
  final Future<Directory> Function() _supportDirectory;
  bool _localDirty = false;
  bool _localPersistenceFailed = false;
  String? _recoveryPath;
  void _syncDocumentStatus() {
    if (_documents.binding != null || _documents.migrations.hasIssue) {
      status =
          _mutating &&
              !_documents.hasIssue &&
              !_documents.pending &&
              !_documents.publishing
          ? 'Saving changes locally…'
          : _documents.summary;
      notifyListeners();
    }
  }

  DocumentSaveCoordinator get documentServices => _documents;
  bool get documentIssue =>
      _documents.hasIssue == true || _documents.pending == true;
  Future<bool> Function(String title, String message)? confirmDocumentAction;
  String? get documentName =>
      _documents.name ?? path?.replaceAll('\\', '/').split('/').last;
  String? error;
  String? documentActionNotice;
  String status = 'Open a collection to begin';
  String? _workingPath;
  DocumentEditIdentity get editIdentity => (
    workingPath: _workingPath,
    documentId: document?['document_id'] as String?,
  );
  String? get path => _documents.externalLocation ?? _workingPath;
  Map<String, dynamic>? document;
  Map<String, dynamic> completion = {};
  Map<String, dynamic> collectionSettings = {};
  Map<String, dynamic> placements = {};
  Map<String, dynamic> appearances = {};
  String? selectedItemPath;
  Map<String, dynamic> viewIssues = {};
  List<Map<String, dynamic>> rows = [];
  int selectedViewId = 1;
  bool completedOnly = false;
  final Set<String> expandedPaths = {'*'};
  int? selectedItemId;
  Future<bool> Function()? flushDraft;
  Future<bool> finishDraft() async {
    if (savingItemDraft || discardingItemDraft) return false;
    if (flushDraft != null && !await flushDraft!()) return false;
    return resolveItemDraft();
  }

  final ItemDraftStore itemDrafts;
  ItemDraft? itemDraft;
  String? editorOverlaySession;
  bool get editorOverlayVisible =>
      editorOverlaySession != null &&
      editorOverlaySession == itemDraft?.sessionId;
  bool recoveryOfferShown = false;
  bool savingItemDraft = false;
  bool discardingItemDraft = false;
  bool retainingItemDraft = false;
  bool switchingCollection = false;
  int _draftGeneration = 0;
  String? draftStorageError;
  Future<DraftExitChoice> Function(ItemDraft, DraftExitReason)? chooseDraftExit;
  bool _resolvingDraft = false;
  List<ItemDraft> get recoveredDrafts => itemDrafts.recovered.values
      .where((d) => d.sessionId != itemDraft?.sessionId)
      .toList();

  ItemDraft? ensureItemDraft() {
    if (itemDraft != null) return itemDraft;
    final item = _map(_map(document?['items'])['$selectedItemId']);
    if (item.isEmpty || _workingPath == null) return null;
    return itemDraft = ItemDraft(
      ownerPath: _workingPath!,
      documentId: '${document!['document_id']}',
      viewId: selectedViewId,
      view: cloneMap(_map(_map(document?['views'])['$selectedViewId'])),
      base: cloneMap(item),
      values: ItemDraft.editable(item),
      itemId: selectedItemId,
    );
  }

  Future<bool> checkpointItemDraft() async {
    final draft = itemDraft;
    if (draft == null || discardingItemDraft) return true;
    final generation = ++_draftGeneration;
    retainingItemDraft = true;
    try {
      if (!draft.dirty && !draft.isNew && draft.intent == null) {
        await itemDrafts.remove(draft.sessionId);
      } else {
        await itemDrafts.put(draft);
      }
      if (generation == _draftGeneration) draftStorageError = null;
      return true;
    } catch (_) {
      draftStorageError = 'The unfinished draft could not be retained on this device. Keep the editor open and check free storage.';
      return false;
    } finally {
      if (generation == _draftGeneration) retainingItemDraft = false;
      notifyListeners();
    }
  }

  void changeItemDraft(String key, dynamic value, {String? sessionId}) {
    final draft = itemDraft;
    if (draft == null ||
        savingItemDraft ||
        discardingItemDraft ||
        switchingCollection ||
        (sessionId != null && sessionId != draft.sessionId)) {
      return;
    }
    draft.values[key] = value;
    if (key == 'parent_id') draft.parentId = value as int?;
    draft.error = null;
    unawaited(checkpointItemDraft());
    notifyListeners();
  }

  Future<bool> discardItemDraft({bool close = true}) async {
    final draft = itemDraft;
    if (draft == null) return true;
    if (savingItemDraft || discardingItemDraft) return false;
    discardingItemDraft = true;
    notifyListeners();
    try {
      await itemDrafts.remove(draft.sessionId);
      if (close) {
        itemDraft = null;
        selectedItemId = null;
      } else if (!draft.isNew) {
        draft.rebase(_map(_map(document?['items'])['${draft.itemId}']));
      } else {
        draft.values = cloneMap(draft.initial);
        draft.error = null;
        draft.intent = null;
        draft.formRevision++;
      }
      return true;
    } catch (_) {
      draft.error =
          'Draft recovery could not be cleared. Check storage before leaving.';
      return false;
    } finally {
      discardingItemDraft = false;
      notifyListeners();
    }
  }

  Future<bool> resolveItemDraft({
    DraftExitReason reason = DraftExitReason.navigate,
    bool close = false,
  }) async {
    final draft = itemDraft;
    if (draft == null) return true;
    if (savingItemDraft || discardingItemDraft) return false;
    if (!draft.dirty && !(draft.isNew && reason == DraftExitReason.outside)) {
      if (close) return discardItemDraft();
      return true;
    }
    if (reason == DraftExitReason.outside && !draft.isNew) {
      return saveItemDraft(close: close);
    }
    if (_resolvingDraft) return false;
    _resolvingDraft = true;
    late DraftExitChoice choice;
    try {
      choice =
          await chooseDraftExit?.call(draft, reason) ??
          DraftExitChoice.keepEditing;
    } finally {
      _resolvingDraft = false;
    }
    if (!identical(itemDraft, draft)) return false;
    return switch (choice) {
      DraftExitChoice.save => saveItemDraft(close: close),
      DraftExitChoice.discard => discardItemDraft(close: close),
      DraftExitChoice.keepEditing => false,
    };
  }

  Future<bool> saveItemDraft({bool close = true}) async {
    final draft = itemDraft;
    if (draft == null || savingItemDraft || discardingItemDraft) {
      return draft == null;
    }
    if (draft.accepted) return discardItemDraft(close: close);
    if (!draft.isNew && !draft.dirty && draft.intent == null) {
      return close ? discardItemDraft() : true;
    }
    if ('${draft.values['title']}'.trim().isEmpty) {
      draft.error = 'Enter a title.';
      notifyListeners();
      return false;
    }
    if (draft.ownerPath != _workingPath ||
        draft.documentId != document?['document_id']) {
      draft.error = 'This draft belongs to another working collection. It has not overwritten this collection.';
      notifyListeners();
      return false;
    }
    savingItemDraft = true;
    notifyListeners();
    try {
      if (draft.isNew && draft.intent != null) {
        final previous = draft.intent!;
        final receipt = await dispatch({
          'op': 'item_draft_status',
          'digest': previous['digest'],
        }, expectedDocument: editIdentity);
        if (receipt?['committed'] == true) {
          return await _acceptItemDraft(draft, close: close);
        }
        if ((document?['next_id'] as int? ?? 0) >
            (previous['id'] as int? ?? 0)) {
          draft.error =
              'This creation may already have been saved as item #${previous['id']}. Review that item or export the draft before creating another.';
          return false;
        }
      }
      final command = {
        ...draft.command(),
        'title': '${draft.values['title']}'.trim(),
      };
      final identity = editIdentity;
      final plan = await dispatch({
        'op': 'preview_item_draft',
        ...command,
      }, expectedDocument: identity);
      if (plan == null || plan['digest'] is! String) {
        draft.error = error ?? 'The draft could not be prepared.';
        return false;
      }
      draft.intent = {
        'digest': plan['digest'],
        'id': plan['id'],
        'revision': plan['revision'],
      };
      if (!await checkpointItemDraft()) {
        draft.intent = null; // No model command was submitted.
        return false;
      }
      final result = await dispatch({
        'op': 'save_item_draft',
        ...command,
        'expected_revision': plan['revision'],
        'expected_digest': plan['digest'],
      }, expectedDocument: identity);
      final commitError = error;
      var accepted = result != null;
      if (!accepted) {
        final status = await dispatch({
          'op': 'item_draft_status',
          'digest': plan['digest'],
        }, expectedDocument: identity);
        accepted = status?['committed'] == true;
      }
      if (!accepted) {
        draft.error =
            commitError ??
            error ??
            'Save was not accepted. Your draft is retained.';
        return false;
      }
      return await _acceptItemDraft(draft, close: close);
    } finally {
      savingItemDraft = false;
      discardingItemDraft = false;
      notifyListeners();
    }
  }

  Future<bool> _acceptItemDraft(ItemDraft draft, {required bool close}) async {
    draft.accepted = true;
    discardingItemDraft = true;
    try {
      await itemDrafts.remove(draft.sessionId);
    } catch (_) {
      error = 'The item was saved, but its private draft cleanup failed. Recovery will check the saved result before restoring it.';
    }
    if (close || draft.isNew) {
      itemDraft = null;
      selectedItemId = null;
    } else {
      draft.rebase(_map(_map(document?['items'])['${draft.itemId}']));
    }
    return true;
  }

  Future<bool> beginCreateDraft(
    Map<String, dynamic> defaults, {
    int? parentId,
    String kind = 'task',
  }) async {
    if (!await finishDraft()) return false;
    if (itemDraft != null && !await discardItemDraft()) return false;
    if (_workingPath == null || document == null) return false;
    final values =
        ItemDraft.editable({...defaults, 'kind': defaults['kind'] ?? kind})
          ..['parent_id'] = parentId
          ..['requirements'] = List<String>.from(
            defaults['requirements'] as List? ?? [],
          );
    itemDraft = ItemDraft(
      ownerPath: _workingPath!,
      documentId: '${document!['document_id']}',
      viewId: selectedViewId,
      view: cloneMap(_map(_map(document?['views'])['$selectedViewId'])),
      base: {},
      values: values,
      parentId: parentId,
    );
    selectedItemId = null;
    notifyListeners();
    return true;
  }

  Future<void> reloadItemDraft() async {
    if (itemDraft?.isNew == false) await discardItemDraft(close: false);
  }

  Future<bool> restoreItemDraft(ItemDraft draft) async {
    await ready;
    if (!await finishDraft()) return false;
    if (draft.ownerPath != _workingPath ||
        draft.documentId != document?['document_id']) {
      final saved = [
        if (_documents.binding != null) _documents.binding!,
        ...await _documents.retainedCollections(),
      ];
      final matches = saved.where((r) => r['path'] == draft.ownerPath).toList();
      if (matches.isEmpty) {
        error = 'Open the retained working collection for this draft first. The draft has been kept separately.';
        notifyListeners();
        return false;
      }
      await restoreRetained(matches.first);
      if (draft.ownerPath != _workingPath ||
          draft.documentId != document?['document_id']) {
        return false;
      }
    }
    if (draft.intent != null) {
      final status = await dispatch({
        'op': 'item_draft_status',
        'digest': draft.intent!['digest'],
      }, expectedDocument: editIdentity);
      if (status?['committed'] == true) {
        await itemDrafts.remove(draft.sessionId);
        error = 'This draft was already saved before the interruption.';
        notifyListeners();
        return true;
      }
      if (draft.isNew &&
          ((document?['next_id'] as int? ?? 0) >
              (draft.intent!['id'] as int? ?? 0))) {
        error =
            'This creation may already have been saved as item #${draft.intent!['id']}. Review that item or export this draft; IHTD will not create it twice automatically.';
        notifyListeners();
        return false;
      }
    }
    itemDraft = draft;
    selectedItemId = draft.itemId;
    draft.formRevision++;
    notifyListeners();
    return true;
  }

  Future<void> discardRecoveredItemDraft(ItemDraft draft) async {
    try {
      await itemDrafts.remove(draft.sessionId);
    } catch (_) {
      error = 'The retained draft could not be discarded. It has been kept on this device.';
    }
    notifyListeners();
  }

  Future<void> exportItemDraft(ItemDraft draft) => _documentAction((
    storage,
  ) async {
    final picked = await storage.pick(suggested: 'IHTD-unfinished-draft.json');
    if (picked == null) return;
    final local = storage.freshPath('json');
    await File(local).writeAsString(jsonEncode(draft.toJson()), flush: true);
    await storage.copyTo(picked, local);
  }, flush: false);

  /// Installation may terminate the process: flush drafts and durably checkpoint
  /// locally without forcing a disconnected/conflicted external publication.
  Future<bool> prepareForUpdate() async {
    await ready;
    if (!await finishDraft()) return false;
    while (busy || _polling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_localPersistenceFailed) return false;
    if (document == null) return true;
    try {
      await _documents.checkpoint(
        dirty: _localDirty,
        recoveryPath: _recoveryPath,
        revision: document?['revision'] as int?,
      );
      return !_localPersistenceFailed &&
          _documents.localDurable &&
          (!_localDirty ||
              (_recoveryPath != null && await File(_recoveryPath!).exists()));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!await finishDraft()) return AppExitResponse.cancel;
    while (busy || _polling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return AppExitResponse.exit;
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _initialize() async {
    try {
      final dir = await _supportDirectory();
      try {
        await itemDrafts.initialize(dir);
      } catch (_) {
        draftStorageError = 'Draft recovery storage is unavailable. Existing drafts have been retained.';
      }
      await _send({'op': 'initialize', 'recovery_dir': '${dir.path}/recovery'});
      _documents.migrations.recoveryDirectory = '${dir.path}/recovery';
      var previous = await _documents.initialize();
      final storedPrevious = previous;
      if (previous != null) {
        previous = await _documents.migrations.prepare(
          previous,
          retained: true,
          automatic: true,
        );
      }
      if (previous != null) {
        await _send({
          'op': 'open',
          'path': previous['path'],
          'recover_local': true,
          'recovery_if_newer': previous['localDirty'] != true,
          if ((previous['localDirty'] == true ||
                  previous['migrationAttempt'] != null) &&
              previous['recoveryPath'] != null)
            'recovery_path': previous['recoveryPath'],
        });
        if (!identical(previous, storedPrevious)) {
          await _documents.attach(previous, retained: true);
        }
        await refreshRows();
        try {
          await _documents.checkpoint(
            dirty: _localDirty,
            recoveryPath: _recoveryPath,
            revision: document?['revision'] as int?,
          );
          await _documents.check();
          status = _documents.summary;
        } catch (e) {
          // Rust accepted and retained the edit. Keep the editor in sync with
          // that revision while visibly reporting the provider save failure.
          error = '$e';
        }
        notifyListeners();
      }
      if (initialDocumentPath != null) {
        final selected = {
          'reference': _documents.adapter
              .referenceFor(initialDocumentPath!)
              .toJson(),
        };
        await _documents.archive();
        final staged = await _documents.stage(selected);
        await _send({
          'op': 'open',
          'path': staged['path'],
          'preserve_pending': true,
        });
        await _documents.attach(staged);
        if (staged['migrationAttempt'] != null) await _documents.publish();
        await refreshRows();
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
      if (_documents.migrations.hasIssue) status = _documents.summary;
      if (_documents.binding != null) {
        if (e is MigrationFailure) {
          status = _documents.summary;
        } else if (e is DocumentFailure &&
            e.kind != DocumentFailureKind.localFailed) {
          await _documents.check();
        } else {
          await _documents.markLocalFailure();
        }
        status = _documents.summary;
      }
      notifyListeners();
    } finally {
      // Recovery must be offered even when there is no active collection.
      notifyListeners();
    }
  }

  void _apply(dynamic snapshot) {
    if (snapshot == null) return;
    final state = _map(snapshot);
    final next = _map(state['document']);
    if (document?['document_id'] != next['document_id']) {
      selectedItemId = null;
      selectedViewId = 1;
      expandedPaths
        ..clear()
        ..add('*');
    }
    document = next;
    final nextPath = state['path'] as String?;
    if (itemDraft != null &&
        (nextPath != itemDraft!.ownerPath ||
            (itemDraft!.itemId != null &&
                !_map(next['items']).containsKey('${itemDraft!.itemId}')))) {
      itemDraft = null;
    }
    if (itemDraft != null &&
        !savingItemDraft &&
        !itemDraft!.isNew &&
        !itemDraft!.dirty &&
        itemDraft!.intent == null) {
      final current = _map(_map(next['items'])['${itemDraft!.itemId}']);
      if (current.isNotEmpty &&
          jsonEncode(current) != jsonEncode(itemDraft!.base)) {
        itemDraft!.rebase(current);
      }
    }
    _workingPath = nextPath;
    collectionSettings = _map(state['collection_settings']);
    completion = _map(state['completion']);
    placements = _map(state['placements']);
    appearances = _map(state['appearances']);
    viewIssues = _map(state['view_issues']);
    _pruneExpandedPaths();
    _localDirty = state['dirty'] == true;
    _localPersistenceFailed = state['persistence_failed'] == true;
    _recoveryPath = state['recovery_path'] as String?;
    final views = _map(document?['views']);
    if (!views.containsKey('$selectedViewId') && views.isNotEmpty) {
      selectedViewId = int.parse(views.keys.first);
    }
    if (selectedItemId != null &&
        !_map(document?['items']).containsKey('$selectedItemId')) {
      selectedItemId = null;
    }
    status = _documents.binding != null
        ? _documents.summary
        : state['dirty'] == true
        ? 'Pending save — local recovery retained'
        : 'Saved to file';
    if (_mutating &&
        _documents.hasIssue == false &&
        _documents.pending == false) {
      status = 'Saving changes locally…';
    }
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> command) async {
    if (command['op'] == 'open') {
      final expected = await _documents.migrations.expectedHashForOpen(
        command['path'] as String,
      );
      if (expected != null) command = {...command, 'expected_hash': expected};
    }
    final response = _map(jsonDecode(await _command(jsonEncode(command))));
    _apply(response['snapshot']);
    if (response['ok'] != true) {
      if (command['op'] == 'open') {
        await _documents.migrations.candidateOpenFailed(
          command['path'] as String,
        );
      }
      throw StateError('${response['error']}');
    }
    return _map(response['data']);
  }

  Future<Map<String, dynamic>?> dispatch(
    Map<String, dynamic> command, {
    DocumentEditIdentity? expectedDocument,
    Map<String, dynamic>? expectedView,
  }) async {
    // Programmatic open/new use the same private staging and publication path
    // as native pickers. Model commands never receive an external destination.
    if (command['op'] == 'open' ||
        command['op'] == 'new' ||
        command['op'] == 'save_as') {
      final locator = command['path'] as String;
      final ref = _documents.adapter.referenceFor(locator);
      await _fileAction(
        command['op'] == 'save_as' ? 'copy' : command['op'] as String,
        null,
        {'reference': ref.toJson(), 'name': ref.nameHint},
      );
      return error == null ? {} : null;
    }
    await ready;
    while (_polling || busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Check inside the command queue, after waiting. Copies may share a UUID.
    if (expectedDocument != null && expectedDocument != editIdentity) {
      error =
          'The open collection changed. Reopen the editor for this collection.';
      notifyListeners();
      return null;
    }
    if (expectedView != null &&
        jsonEncode(_map(document?['views'])['${expectedView['id']}']) !=
            jsonEncode(expectedView)) {
      error = 'This view changed while you were editing it. Reopen the editor to review its current rules.';
      notifyListeners();
      return null;
    }
    busy = true;
    _mutating = !const {
      'query',
      'creation_defaults',
      'preview_removal',
      'preview_item_action',
      'copy_options',
      'preview_item_draft',
      'item_draft_status',
      'snapshot',
      'open',
      'new',
      'export',
      'copy',
      'poll',
    }.contains(command['op']);
    if (_mutating && !documentIssue) status = 'Saving changes locally…';
    error = null;
    notifyListeners();
    try {
      final result = await _send(command);
      if (!const {
        'query',
        'creation_defaults',
        'preview_removal',
        'preview_item_action',
        'copy_options',
        'preview_item_draft',
        'item_draft_status',
        'snapshot',
        'open',
        'new',
        'export',
        'copy',
      }.contains(command['op'])) {
        try {
          await _publishDocument();
        } catch (e) {
          // The private commit succeeded; provider failure must not leave the
          // text editor holding a stale revision of its own accepted edit.
          error = '$e';
        }
      }
      await refreshRows();
      return result;
    } catch (e) {
      error = '$e';
      if (_documents.binding != null) {
        await _documents.checkpoint(
          dirty: _localDirty,
          recoveryPath: _recoveryPath,
          revision: document?['revision'] as int?,
        );
        if (_localDirty) status = _documents.summary;
        if (_localPersistenceFailed && !_localDirty) {
          await _documents.markLocalFailure();
          status = _documents.summary;
        }
      }
      await refreshRows();
      return null;
    } finally {
      _mutating = false;
      busy = false;
      if (_documents.binding != null) status = _documents.summary;
      notifyListeners();
    }
  }

  /// A placement, not an item title or filtered appearance, is the target.
  /// Flush drafts before previewing; never reuse approval across collections.
  Future<bool> removePlacement(
    int id,
    int? parent, {
    required Future<bool> Function(Map<String, dynamic>) confirmDelete,
  }) async {
    final working = _workingPath;
    final identity = document?['document_id'];
    if (!await finishDraft()) return false;
    if (working != _workingPath || identity != document?['document_id']) {
      error = 'The open collection changed. Select the placement again.';
      notifyListeners();
      return false;
    }
    final preview = await dispatch({
      'op': 'preview_removal',
      'id': id,
      'parent': parent,
    });
    if (preview == null) return false;
    final deleting = preview['action'] == 'delete';
    if (deleting && !await confirmDelete(preview)) return false;
    if (working != _workingPath || identity != document?['document_id']) {
      error = 'The open collection changed. Select the placement again.';
      notifyListeners();
      return false;
    }
    // Rust checks the complete preview/revision atomically. A stale Unlink
    // cannot become a Delete, and an old confirmation cannot delete new work.
    return await dispatch({
          'op': 'remove_placement',
          'preview': preview,
          'confirm_delete': deleting,
        }) !=
        null;
  }

  Future<bool> performItemAction(
    List<int> path,
    String action, {
    required Future<bool> Function(Map<String, dynamic>) confirm,
  }) async {
    final owner = editIdentity;
    if (!await finishDraft() || owner != editIdentity) return false;
    final preview = await dispatch({
      'op': 'preview_item_action',
      'path': path,
      'action': action,
    }, expectedDocument: owner);
    if (preview == null) return false;
    final needsConfirmation =
        action == 'delete' || preview['blocking_parent'] != null;
    if (needsConfirmation && !await confirm(preview)) return false;
    return await dispatch({
          'op': 'apply_item_action',
          'preview': preview,
          'confirmed': needsConfirmation,
        }, expectedDocument: owner) !=
        null;
  }

  void _pruneExpandedPaths() {
    final links = (document?['links'] as List? ?? []).map(_map).toList();
    final edges = {
      for (final link in links) '${link['parent']}/${link['child']}',
    };
    expandedPaths.removeWhere((entry) {
      if (entry == '*') return false;
      final parts = (entry.startsWith('!') ? entry.substring(1) : entry).split(
        '/',
      );
      if (_map(placements[parts.first])['root'] != true) return true;
      for (var index = 1; index < parts.length; index++) {
        if (!edges.contains('${parts[index - 1]}/${parts[index]}')) return true;
      }
      return false;
    });
    final selectedPath = selectedItemPath;
    if (selectedPath != null) {
      final parts = selectedPath.split('/');
      if (parts.last != '$selectedItemId' ||
          _map(placements[parts.first])['root'] != true ||
          List.generate(
            parts.length - 1,
            (i) => '${parts[i]}/${parts[i + 1]}',
          ).any((edge) => !edges.contains(edge))) {
        selectedItemPath = null;
      }
    }
  }

  List<Map<String, dynamic>> issuesForView(int id) =>
      (viewIssues['$id'] as List? ?? []).map(_map).toList();

  Future<void> refreshRows() async {
    if (document == null) {
      rows = [];
      return;
    }
    try {
      final result = await _send({
        'op': 'query',
        'view_id': selectedViewId,
        'completed_only': completedOnly,
        'expanded': expandedPaths.toList(),
      });
      rows = (result['rows'] as List? ?? []).map(_map).toList();
    } catch (e) {
      error = '$e';
    }
  }

  Future<void> poll() async {
    await ready;
    if (_disposed || busy || _polling || document == null) return;
    _polling = true;
    try {
      await _documents.check();
      status = _documents.summary;
      final result = await _send({'op': 'poll'});
      if (result['reloaded'] == true) {
        await refreshRows();
        status = 'Reloaded newer file';
        notifyListeners();
      }
      notifyListeners();
    } catch (e) {
      final next = '$e';
      if (error != next) {
        error = next;
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) poll();
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      checkpointItemDraft().then((_) => poll());
    }
  }

  Future<void> _publishDocument() async {
    if (_documents.binding == null) return;
    await _documents.checkpoint(
      dirty: _localDirty,
      recoveryPath: _recoveryPath,
      revision: document?['revision'] as int?,
      markPending: true,
    );
    await _documents.publish();
    status = _documents.summary;
    notifyListeners();
  }

  Future<void> _fileAction(
    String action, [
    String? format,
    Map<String, dynamic>? supplied,
  ]) async {
    if (!await finishDraft()) return;
    await ready;
    while (busy || _polling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    busy = true;
    switchingCollection = {'open', 'new', 'copy'}.contains(action);
    error = null;
    notifyListeners();
    final storage = _documents;
    try {
      if (action == 'open' || action == 'new') {
        await storage.check();
        if (storage.binding != null && (storage.pending || storage.hasIssue)) {
          final confirmed =
              await confirmDocumentAction?.call(
                'Switch collection?',
                '${storage.explanation}\n\nContinue opening another collection while retaining this working copy and recovery locally?',
              ) ??
              false;
          if (!confirmed) return;
        }
        await storage.archive();
      }
      if (action == 'open') {
        final selected = supplied ?? await storage.pick();
        if (selected == null) return;
        final staged = await storage.stage(selected);
        await _send({
          'op': 'open',
          'path': staged['path'],
          'preserve_pending': true,
        });
        await storage.attach(staged);
        if (staged['migrationAttempt'] != null) await storage.publish();
        status = storage.summary;
      } else {
        final extension = format == 'markdown' ? 'md' : format ?? 'ihtd';
        final selected =
            supplied ?? await storage.pick(suggested: 'Tasks.$extension');
        if (selected == null) return;
        if (action == 'new') {
          final local = storage.freshPath();
          final original = await storage.read(selected, allowMissing: true);
          if ((original['bytes'] as List).isNotEmpty) {
            throw StateError(
              'Choose a new file; the selected document already contains data.',
            );
          }
          await _send({'op': 'new', 'path': local, 'preserve_pending': true});
          await storage.attach({
            ...selected,
            'path': local,
            'hash': original['hash'],
            'creating': true,
          });
          await _publishDocument();
        } else if (action == 'copy') {
          // Publishing a separate copy is also the escape route for conflicts.
          final latest = storage.freshPath();
          await _send({'op': 'copy', 'path': latest});
          await storage.copyTo(selected, latest);
          await storage.archive();
          final staged = await storage.stage(selected);
          await _send({
            'op': 'open',
            'path': staged['path'],
            'preserve_pending': true,
          });
          await storage.attach(staged);
          status = storage.summary;
        } else {
          final local = storage.freshPath(extension);
          await _send({'op': 'export', 'format': format, 'path': local});
          await storage.copyTo(selected, local);
        }
      }
    } catch (e) {
      error = '$e';
    } finally {
      await refreshRows();
      busy = false;
      switchingCollection = false;
      notifyListeners();
    }
  }

  void toggleExpand(String key) {
    if (expandedPaths.contains('*')) {
      if (!expandedPaths.remove('!$key')) expandedPaths.add('!$key');
    } else {
      if (!expandedPaths.remove(key)) expandedPaths.add(key);
    }
    refreshRows().then((_) {
      notifyListeners();
    });
  }

  Future<void> selectItem(int? id, {String? path}) async {
    if (itemDraft != null && itemDraft!.itemId == id && id != null) {
      if (path != null) selectedItemPath = path;
      notifyListeners();
      return;
    }
    if (!await finishDraft()) return;
    if (itemDraft != null &&
        itemDraft!.itemId != id &&
        !await discardItemDraft()) {
      return;
    }
    selectedItemId = id;
    selectedItemPath = path;
    if (id != null) ensureItemDraft();
    notifyListeners();
  }

  Future<void> selectView(int id) async {
    if (!await finishDraft()) return;
    if (itemDraft != null && !await discardItemDraft()) return;
    selectedViewId = id;
    selectedItemId = null;
    await refreshRows();
    notifyListeners();
  }

  void setCompletedOnly(bool value) {
    completedOnly = value;
    refreshRows().then((_) {
      notifyListeners();
    });
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> _documentAction(
    Future<void> Function(DocumentSaveCoordinator) action, {
    bool flush = true,
  }) async {
    if (flush && !await finishDraft()) return;
    await ready;
    while (busy || _polling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    busy = true;
    error = null;
    documentActionNotice = null;
    notifyListeners();
    try {
      await action(_documents);
    } catch (_) {
      documentActionNotice = 'The document action could not be completed. Your open collection has been retained.';
    } finally {
      status = _documents.summary;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> reconnectDocument({bool selectFile = false}) => _documentAction((
    storage,
  ) async {
    await storage.check();
    Map<String, dynamic>? selected = storage.binding;
    if (selectFile) selected = await storage.pick();
    if (selected == null) return;
    final metadata = await storage.inspect(selected);
    final confirmed =
        await confirmDocumentAction?.call(
          'Confirm saving destination',
          'Selected file: “${metadata['name'] ?? 'Unknown name'}”.\n\n'
              '${storage.pending ? 'Save your pending local edits to this file if its contents match the last confirmed version?' : 'Confirm this file to resume automatic saving?'}\n\n'
              'A changed file will not be overwritten. If its contents do not match, preserve a separate copy and reopen the external version.',
        ) ??
        false;
    if (!confirmed) return;
    if (storage.localDirty) {
      await _send({'op': 'retry'});
      await storage.checkpoint(
        dirty: _localDirty,
        recoveryPath: _recoveryPath,
        revision: document?['revision'] as int?,
      );
    }
    if (!await storage.confirm(
      selected: {...selected, ...metadata, 'explicitSelection': selectFile},
    )) {
      documentActionNotice = 'Reconnection was not confirmed. The file may have changed or remain unavailable; review the document warning.';
    }
  });

  Future<void> retryDocumentSave() async {
    await reconnectDocument();
  }

  Future<void> exportDiagnostics({bool extended = false}) => _documentAction(
    (storage) => storage.exportDiagnostics(extended: extended),
    flush: false,
  );

  Future<void> chooseMigrationBackupFolder() => _documentAction(
    (storage) => storage.migrations.chooseBackupFolder(),
    flush: false,
  );

  Future<void> exportMigrationFile(String path) =>
      _documentAction((storage) async {
        // Only locations from private migration journals are offered by the UI.
        final selected = await storage.pick(
          suggested: path.endsWith('.json')
              ? 'IHTD-recovered-metadata.json'
              : 'IHTD-recovered-collection.ihtd',
        );
        if (selected != null) await storage.copyTo(selected, path);
      }, flush: false);

  Future<void> restoreRetained(Map<String, dynamic> saved) => _documentAction((
    storage,
  ) async {
    await storage.check();
    final confirmed =
        await confirmDocumentAction?.call(
          'Restore retained working copy?',
          'Open the locally retained copy of “${saved['name'] ?? 'Collection'}”? '
              'Your current working copy will also be retained. External saving stays paused until you confirm its destination.',
        ) ??
        false;
    if (!confirmed) return;
    await storage.archive();
    saved = await storage.migrations.prepare(saved, retained: true);
    await _send({
      'op': 'open',
      'path': saved['path'],
      'recover_local': true,
      'recovery_if_newer': saved['localDirty'] != true,
      'preserve_pending': true,
      if ((saved['localDirty'] == true || saved['migrationAttempt'] != null) &&
          saved['recoveryPath'] != null)
        'recovery_path': saved['recoveryPath'],
    });
    await storage.attach(saved, retained: true);
    storage.localDirty = _localDirty;
    if (storage.connection == DocumentConnection.connected) {
      storage.connection = DocumentConnection.reconnectRequired;
    }
    await storage.checkpoint(
      dirty: _localDirty,
      recoveryPath: _recoveryPath,
      revision: document?['revision'] as int?,
    );
    await refreshRows();
  });

  Future<void> openDocument() => _fileAction('open');
  Future<void> newDocument() => _fileAction('new');
  Future<void> saveAs() => _fileAction('copy');
  Future<void> exportDocument(String format) => _fileAction('export', format);

  @override
  void dispose() {
    _disposed = true;
    _documents.onStateChanged = null;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
