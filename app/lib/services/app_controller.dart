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
  }) : _documents =
           documentServices ??
           composeDocumentServices(
             command ?? ((request) => api.command(request: request)),
           ),
       _command = command ?? ((request) => api.command(request: request)),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory {
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
    if (_documents.binding != null) {
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
  Map<String, dynamic> placements = {};
  Map<String, dynamic> viewIssues = {};
  List<Map<String, dynamic>> rows = [];
  int selectedViewId = 1;
  bool completedOnly = false;
  final Set<String> expandedPaths = {'*'};
  int? selectedItemId;
  Future<bool> Function()? flushDraft;
  Future<bool> finishDraft() async => await flushDraft?.call() ?? true;

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
      await _send({'op': 'initialize', 'recovery_dir': '${dir.path}/recovery'});
      final previous = await _documents.initialize();
      if (previous != null) {
        await _send({
          'op': 'open',
          'path': previous['path'],
          'recover_local': true,
          if (previous['localDirty'] == true &&
              previous['recoveryPath'] != null)
            'recovery_path': previous['recoveryPath'],
        });
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
        await refreshRows();
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
      if (_documents.binding != null) {
        if (e is DocumentFailure && e.kind != DocumentFailureKind.localFailed) {
          await _documents.check();
        } else {
          await _documents.markLocalFailure();
        }
        status = _documents.summary;
      }
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
    _workingPath = state['path'] as String?;
    completion = _map(state['completion']);
    placements = _map(state['placements']);
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
    final response = _map(jsonDecode(await _command(jsonEncode(command))));
    _apply(response['snapshot']);
    if (response['ok'] != true) throw StateError('${response['error']}');
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
      error = 'The open collection changed. Reopen the view editor for this collection.';
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
      finishDraft().then((_) => poll());
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
    error = null;
    notifyListeners();
    final storage = _documents;
    try {
      if (action == 'open' || action == 'new') {
        await storage.check();
        if (storage.pending || storage.hasIssue) {
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

  Future<void> selectItem(int? id) async {
    if (!await finishDraft()) return;
    selectedItemId = id;
    notifyListeners();
  }

  Future<void> selectView(int id) async {
    if (!await finishDraft()) return;
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
    await _send({
      'op': 'open',
      'path': saved['path'],
      'recover_local': true,
      'preserve_pending': true,
      if (saved['localDirty'] == true && saved['recoveryPath'] != null)
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
