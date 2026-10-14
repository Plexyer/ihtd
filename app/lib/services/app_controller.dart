import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/legacy.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/simple.dart' as api;
import 'android_documents.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => AppController(),
);

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    this.initialDocumentPath,
    AndroidDocuments? androidDocuments,
    Future<String> Function(String)? command,
    Future<Directory> Function()? supportDirectory,
    bool polling = true,
  }) : _android =
           androidDocuments ?? (Platform.isAndroid ? AndroidDocuments() : null),
       _command = command ?? ((request) => api.command(request: request)),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory {
    WidgetsBinding.instance.addObserver(this);
    _android?.onStateChanged = _syncAndroidStatus;
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
  final AndroidDocuments? _android;
  final Future<String> Function(String) _command;
  final Future<Directory> Function() _supportDirectory;
  bool _localDirty = false;
  bool _localPersistenceFailed = false;
  String? _recoveryPath;
  void _syncAndroidStatus() {
    if (_android?.binding != null) {
      status =
          _mutating &&
              !_android!.hasIssue &&
              !_android.pending &&
              !_android.publishing
          ? 'Saving changes locally…'
          : _android!.summary;
      notifyListeners();
    }
  }

  AndroidDocuments? get androidDocuments => _android;
  bool get documentIssue =>
      _android?.hasIssue == true || _android?.pending == true;
  Future<bool> Function(String title, String message)? confirmDocumentAction;
  String? get documentName =>
      _android?.name ?? path?.replaceAll('\\', '/').split('/').last;
  String? error;
  String? documentActionNotice;
  String status = 'Open a collection to begin';
  String? path;
  Map<String, dynamic>? document;
  Map<String, dynamic> completion = {};
  List<Map<String, dynamic>> rows = [];
  int selectedViewId = 1;
  bool completedOnly = false;
  final Set<String> expandedPaths = {'*'};
  int? selectedItemId;
  Future<bool> Function()? flushDraft;
  Future<bool> finishDraft() async => await flushDraft?.call() ?? true;
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
      final previous = await _android?.initialize();
      if (_android == null && initialDocumentPath != null) {
        await _send({'op': 'open', 'path': initialDocumentPath});
        await refreshRows();
        notifyListeners();
      }
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
          await _android!.checkpoint(
            dirty: _localDirty,
            recoveryPath: _recoveryPath,
            revision: document?['revision'] as int?,
          );
          await _android.check();
          status = _android.summary;
        } catch (e) {
          // Rust accepted and retained the edit. Keep the editor in sync with
          // that revision while visibly reporting the provider save failure.
          error = '$e';
        }
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
      if (_android?.binding != null) {
        await _android!.markLocalFailure();
        status = _android.summary;
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
    path = state['path'] as String?;
    completion = _map(state['completion']);
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
    status = _android?.binding != null
        ? _android!.summary
        : state['dirty'] == true
        ? 'Pending save — local recovery retained'
        : 'Saved to file';
    if (_mutating &&
        _android?.hasIssue == false &&
        _android?.pending == false) {
      status = 'Saving changes locally…';
    }
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> command) async {
    final response = _map(jsonDecode(await _command(jsonEncode(command))));
    _apply(response['snapshot']);
    if (response['ok'] != true) throw StateError('${response['error']}');
    return _map(response['data']);
  }

  Future<Map<String, dynamic>?> dispatch(Map<String, dynamic> command) async {
    await ready;
    while (_polling || busy) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    busy = true;
    _mutating =
        _android != null &&
        !const {
          'query',
          'creation_defaults',
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
        'snapshot',
        'open',
        'new',
        'export',
        'copy',
      }.contains(command['op'])) {
        try {
          await _publishAndroid();
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
      if (_android?.binding != null) {
        await _android!.checkpoint(
          dirty: _localDirty,
          recoveryPath: _recoveryPath,
          revision: document?['revision'] as int?,
        );
        if (_localDirty) status = _android.summary;
        if (_localPersistenceFailed && !_localDirty) {
          await _android.markLocalFailure();
          status = _android.summary;
        }
      }
      await refreshRows();
      return null;
    } finally {
      _mutating = false;
      busy = false;
      if (_android?.binding != null) status = _android!.summary;
      notifyListeners();
    }
  }

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
      if (_android != null) {
        await _android.check();
        status = _android.summary;
      }
      final result = await _send({'op': 'poll'});
      if (result['reloaded'] == true) {
        await refreshRows();
        status = 'Reloaded newer file';
        notifyListeners();
      }
      if (_android != null) notifyListeners();
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

  Future<void> _publishAndroid() async {
    if (_android?.binding == null) return;
    await _android!.checkpoint(
      dirty: _localDirty,
      recoveryPath: _recoveryPath,
      revision: document?['revision'] as int?,
      markPending: true,
    );
    await _android.publish();
    status = _android.summary;
    notifyListeners();
  }

  Future<void> _androidFileAction(String action, [String? format]) async {
    if (!await finishDraft()) return;
    await ready;
    while (busy || _polling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    busy = true;
    error = null;
    notifyListeners();
    final storage = _android!;
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
        final selected = await storage.pick();
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
        final selected = await storage.pick(suggested: 'Tasks.$extension');
        if (selected == null) return;
        if (action == 'new') {
          final local = storage.freshPath();
          final original = await storage.read(selected['uri'] as String);
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
          });
          await _publishAndroid();
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
    Future<void> Function(AndroidDocuments) action, {
    bool flush = true,
  }) async {
    if (_android == null) return;
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
      await action(_android);
    } catch (_) {
      documentActionNotice = 'The document action could not be completed. Your open collection has been retained.';
    } finally {
      status = _android.summary;
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
    final metadata = await storage.inspect(selected['uri'] as String);
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
    if (!await storage.confirm(selected: {...selected, ...metadata})) {
      documentActionNotice = 'Reconnection was not confirmed. The file may have changed or remain unavailable; review the document warning.';
    }
  });

  Future<void> retryDocumentSave() async {
    if (_android == null) {
      await dispatch({'op': 'retry'});
      return;
    }
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
    await storage.attach({...saved, 'barrier': 'reconnectRequired'});
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

  Future<void> openDocument() async {
    if (_android != null) return _androidFileAction('open');
    if (!await finishDraft()) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'IHTD collection', extensions: ['ihtd']),
        ],
      );
      if (file != null) await dispatch({'op': 'open', 'path': file.path});
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<String?> _savePath(String suggested, String extension) async {
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return null;
    return location.path.toLowerCase().endsWith('.$extension')
        ? location.path
        : '${location.path}.$extension';
  }

  Future<void> newDocument() async {
    if (_android != null) return _androidFileAction('new');
    if (!await finishDraft()) return;
    try {
      final selected = await _savePath('My tasks.ihtd', 'ihtd');
      if (selected != null) await dispatch({'op': 'new', 'path': selected});
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> saveAs() async {
    if (_android != null) return _androidFileAction('copy');
    if (!await finishDraft()) return;
    try {
      final selected = await _savePath('Tasks copy.ihtd', 'ihtd');
      if (selected != null) await dispatch({'op': 'save_as', 'path': selected});
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> exportDocument(String format) async {
    if (_android != null) return _androidFileAction('export', format);
    if (!await finishDraft()) return;
    try {
      final extension = format == 'markdown' ? 'md' : format;
      final selected = await _savePath('Tasks.$extension', extension);
      if (selected != null) {
        await dispatch({'op': 'export', 'format': format, 'path': selected});
      }
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _android?.onStateChanged = null;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
