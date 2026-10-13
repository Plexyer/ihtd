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
  AppController({this.initialDocumentPath}) {
    WidgetsBinding.instance.addObserver(this);
    ready = _initialize();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
  }
  final String? initialDocumentPath;
  late final Future<void> ready;
  Timer? _timer;
  bool busy = false;
  bool _polling = false;
  bool _disposed = false;
  final AndroidDocuments? _android = Platform.isAndroid
      ? AndroidDocuments()
      : null;
  bool _providerPending = false;
  String? _providerError;
  String? get documentName =>
      _android?.name ?? path?.replaceAll('\\', '/').split('/').last;
  String? error;
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
      final dir = await getApplicationSupportDirectory();
      await _send({'op': 'initialize', 'recovery_dir': '${dir.path}/recovery'});
      final previous = await _android?.initialize();
      if (_android == null && initialDocumentPath != null) {
        await _send({'op': 'open', 'path': initialDocumentPath});
        await refreshRows();
        notifyListeners();
      }
      if (previous != null) {
        await _send({'op': 'open', 'path': previous['path']});
        await refreshRows();
        try {
          await _publishAndroid();
        } catch (e) {
          // Rust accepted and retained the edit. Keep the editor in sync with
          // that revision while visibly reporting the provider save failure.
          error = '$e';
        }
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
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
    final views = _map(document?['views']);
    if (!views.containsKey('$selectedViewId') && views.isNotEmpty) {
      selectedViewId = int.parse(views.keys.first);
    }
    if (selectedItemId != null &&
        !_map(document?['items']).containsKey('$selectedItemId')) {
      selectedItemId = null;
    }
    status = state['dirty'] == true || _providerPending
        ? 'Pending save — local recovery retained'
        : 'Saved to file';
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> command) async {
    final response = _map(
      jsonDecode(await api.command(request: jsonEncode(command))),
    );
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
      await refreshRows();
      return null;
    } finally {
      busy = false;
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
      await _publishAndroid();
      final result = await _send({'op': 'poll'});
      if (result['reloaded'] == true) {
        await refreshRows();
        status = 'Reloaded newer file';
        notifyListeners();
      }
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
    final wasPending = _providerPending;
    _providerPending = true;
    status = 'Pending save — local recovery retained';
    try {
      await _android!.publish();
    } catch (e) {
      _providerError = '$e';
      rethrow;
    }
    _providerPending = false;
    status = 'Saved to selected file';
    if (error == _providerError) error = null;
    _providerError = null;
    if (wasPending) notifyListeners();
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
        await storage.checkBeforeSwitch();
      }
      if (action == 'open') {
        final selected = await storage.pick();
        if (selected == null) return;
        final staged = await storage.stage(selected);
        await _send({'op': 'open', 'path': staged['path']});
        await storage.remember(staged);
        _providerPending = false;
        status = 'Opened selected file';
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
          await _send({'op': 'new', 'path': local});
          await storage.remember({
            ...selected,
            'path': local,
            'hash': original['hash'],
          });
          await _publishAndroid();
        } else if (action == 'copy') {
          // Publishing a separate copy is also the escape route for conflicts.
          await storage.copyTo(selected, path!);
          final staged = await storage.stage(selected);
          await _send({'op': 'open', 'path': staged['path']});
          await storage.remember(staged);
          _providerPending = false;
          status = 'Saved to selected file';
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
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
