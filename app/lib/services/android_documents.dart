import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'document_diagnostics.dart';

enum DocumentConnection {
  checking,
  connected,
  renamed,
  unavailable,
  externalChanged,
  saveFailed,
  localFailed,
  reconnectRequired,
}

/// External binding, private edits and confirmed revision are independent.
/// A persisted barrier can only be released by an explicit user action.
class AndroidDocuments {
  AndroidDocuments({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _supportDirectory;
  static const channel = MethodChannel('dev.ihtd.app/documents');
  Map<String, dynamic>? binding;
  Map<String, dynamic>? observed;
  DocumentConnection connection = DocumentConnection.checking;
  bool pending = false;
  bool publishing = false;
  bool localDurable = true;
  bool _needsPersistence = false;
  bool _untrackedSave = false;
  bool localDirty = false;
  bool _restored = false;
  String? lastFailure;
  void Function()? onStateChanged;
  late Directory directory;
  final diagnostics = DocumentDiagnostics();
  String? get name => binding?['name'] as String?;
  bool get hasIssue =>
      binding != null && connection != DocumentConnection.connected;
  bool get severe =>
      connection == DocumentConnection.saveFailed ||
      connection == DocumentConnection.localFailed ||
      !localDurable;
  String get summary {
    if (publishing) return 'Saving to file…';
    if (connection == DocumentConnection.localFailed || !localDurable) {
      return 'Local saving failed — edits may be at risk';
    }
    if (pending) {
      return severe
          ? 'Save failed — changes retained locally'
          : 'Pending changes — not saved to file';
    }
    return switch (connection) {
      DocumentConnection.connected => 'Saved to file',
      DocumentConnection.checking => 'Checking file connection…',
      DocumentConnection.renamed => 'Filename changed — confirmation needed',
      DocumentConnection.unavailable => 'Cannot access the selected file',
      DocumentConnection.externalChanged => 'File changed outside IHTD',
      DocumentConnection.saveFailed => 'File save could not be verified',
      DocumentConnection.reconnectRequired =>
        'Confirm file connection to continue',
      DocumentConnection.localFailed => 'Local saving failed',
    };
  }

  String get explanation {
    final where = localDurable
        ? (pending
              ? 'Your pending edits are retained locally and have not been confirmed in the external file.'
              : 'No pending local edits were detected.')
        : 'IHTD could not confirm local persistence. Keep the app open and save a separate copy if possible.';
    final detail = switch (connection) {
      DocumentConnection.renamed =>
        'Filename changed from “${name ?? 'the selected file'}” to “${observed?['name'] ?? 'a new name'}”. '
            '${observed?['hash'] == binding?['hash'] ? 'Contents are unchanged since the last confirmed save.' : 'Contents also changed outside IHTD.'} '
            'Confirm the unchanged document to continue, or preserve your edits and reopen the external version.',
      DocumentConnection.externalChanged => 'The selected file’s contents changed outside IHTD. Save a copy of your edits or explicitly reopen the external version. IHTD will not merge or overwrite it automatically.',
      DocumentConnection.unavailable => 'IHTD cannot access the selected file. It may have been moved, deleted, lost permission, or become unavailable through its storage provider. Retry checking or select a file to reconnect.',
      DocumentConnection.saveFailed => 'The provider refused a write or IHTD could not verify the saved contents. Automatic saving is paused. Retry explicitly, or save a separate copy. A partial write may require reopening or saving a copy.',
      DocumentConnection.localFailed => 'The private working copy or restart metadata could not be saved. Check available storage and save a separate copy before closing the app.',
      DocumentConnection.reconnectRequired => 'File access is available again, but saving remains paused. Confirm the destination before applying any pending edits.',
      DocumentConnection.checking => 'IHTD is checking the selected document before allowing external saving.',
      DocumentConnection.connected =>
        pending ? 'Changes are waiting for a verified external save.' : 'The current working copy matches the provider-confirmed file. This does not guarantee cloud synchronization.',
    };
    return '$detail\n\n$where';
  }

  Future<Map<String, dynamic>?> initialize() async {
    final support = await _supportDirectory();
    directory = Directory('${support.path}/android-documents');
    await directory.create(recursive: true);
    await diagnostics.initialize(directory);
    try {
      diagnostics.environment = Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('environment') ?? {},
      );
    } catch (_) {}
    final file = File('${directory.path}/active.json');
    if (await file.exists()) {
      binding = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()),
      );
      connection = _state(binding?['barrier']);
      pending = binding?['pending'] == true;
      _untrackedSave = binding?['untrackedSave'] == true;
      localDirty = binding?['localDirty'] == true;
      lastFailure = DocumentDiagnostics.codes.contains(binding?['failureCode'])
          ? (binding?['failureCode'] as String?)
          : null;
      _restored = true;
      diagnostics.useDocument('${binding!['path']}');
    }
    return binding;
  }

  DocumentConnection _state(dynamic barrier) => switch (barrier) {
    'renamed' => DocumentConnection.renamed,
    'unavailable' => DocumentConnection.unavailable,
    'externalChanged' => DocumentConnection.externalChanged,
    'saveFailed' => DocumentConnection.saveFailed,
    'localFailed' => DocumentConnection.localFailed,
    'reconnectRequired' => DocumentConnection.reconnectRequired,
    _ => DocumentConnection.checking,
  };
  Future<void> remember(Map<String, dynamic> next) async {
    binding = {...next, 'version': 2};
    _needsPersistence = true;
    final temp = File('${directory.path}/active.json.tmp');
    await temp.writeAsString(jsonEncode(binding), flush: true);
    await temp.rename('${directory.path}/active.json');
    _needsPersistence = false;
  }

  Future<void> _persist() async {
    if (binding == null) return;
    try {
      await remember({
        ...binding!,
        'pending': pending,
        'untrackedSave': _untrackedSave,
        'failureCode': lastFailure,
        'barrier': connection == DocumentConnection.connected
            ? null
            : connection.name,
      });
    } catch (_) {
      localDurable = false;
      connection = DocumentConnection.localFailed;
      diagnostics.record('local_failed', pending);
    }
    onStateChanged?.call();
  }

  String freshPath([String extension = 'ihtd']) =>
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.$extension';
  Future<Map<String, dynamic>?> pick({String? suggested}) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      suggested == null ? 'open' : 'create',
      {'name': suggested},
    );
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> read(String uri) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMapMethod<String, dynamic>('read', {'uri': uri}))!,
      );
  Future<Map<String, dynamic>> inspect(String uri) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMapMethod<String, dynamic>('inspect', {
          'uri': uri,
        }))!,
      );
  Future<String> localHash() async =>
      (await channel.invokeMethod<String>('localHash', binding))!;
  Future<Map<String, dynamic>> stage(Map<String, dynamic> picked) async {
    final content = await read(picked['uri'] as String);
    final metadata = await inspect(picked['uri'] as String);
    if (content['hash'] != metadata['hash']) {
      throw StateError('The selected file changed while opening. Try again.');
    }
    final path = freshPath();
    await File(path).writeAsBytes(content['bytes'] as Uint8List, flush: true);
    return {...picked, ...metadata, 'path': path, 'hash': content['hash']};
  }

  Future<void> attach(Map<String, dynamic> next) async {
    diagnostics.useDocument('${next['path']}');
    observed = null;
    pending = false;
    localDurable = true;
    _untrackedSave = false;
    lastFailure = null;
    connection = DocumentConnection.checking;
    localDirty = false;
    _restored = false;
    try {
      await remember(next);
    } catch (_) {
      localDurable = false;
      connection = DocumentConnection.localFailed;
    }
    await check();
  }

  Future<void> check() async {
    if (binding == null) return;
    final previous = connection;
    try {
      final digest = await localHash();
      pending = localDirty || digest != binding!['hash'];
      observed = await inspect(binding!['uri'] as String);
      final remote = observed!['hash'];
      if (observed!['name'] == null) {
        connection = DocumentConnection.unavailable;
      } else if (observed!['name'] != name) {
        connection = DocumentConnection.renamed;
      } else if (remote != binding!['hash']) {
        connection = previous == DocumentConnection.saveFailed
            ? previous
            : DocumentConnection.externalChanged;
      } else if (!localDurable || _needsPersistence) {
        connection = DocumentConnection.localFailed;
      } else if (_restored &&
          pending &&
          previous == DocumentConnection.checking) {
        connection = DocumentConnection.reconnectRequired;
      } else if (previous == DocumentConnection.checking ||
          previous == DocumentConnection.connected) {
        connection = DocumentConnection.connected;
      } else if (previous != DocumentConnection.saveFailed) {
        connection = DocumentConnection.reconnectRequired;
      }
    } on PlatformException catch (e) {
      connection = e.code == 'local_failed'
          ? DocumentConnection.localFailed
          : DocumentConnection.unavailable;
      if (connection == DocumentConnection.localFailed) localDurable = false;
    } catch (_) {
      connection = DocumentConnection.unavailable;
    }
    diagnostics.record(_eventCode(), pending);
    await _persist();
  }

  String _eventCode() => switch (connection) {
    DocumentConnection.externalChanged => 'external_changed',
    DocumentConnection.saveFailed => 'save_failed',
    DocumentConnection.localFailed => 'local_failed',
    DocumentConnection.reconnectRequired => 'reconnect_required',
    _ => connection.name,
  };
  Future<void> publish() async {
    if (binding == null) return;
    await check();
    if (connection != DocumentConnection.connected || !pending || localDirty) {
      return;
    }
    publishing = true;
    diagnostics.record('publish_started', pending);
    // A killed write can be verified explicitly after restart, never retried
    // automatically. Persist the attempt before touching the provider.
    _untrackedSave = true;
    await _persist();
    if (!localDurable) {
      publishing = false;
      return;
    }
    try {
      final hash = await channel.invokeMethod<String>('write', binding);
      if (hash == null) throw PlatformException(code: 'verification_failed');
      await remember({...binding!, 'hash': hash, 'barrier': null});
      pending = await localHash() != hash;
      _untrackedSave = false;
      lastFailure = null;
      diagnostics.record('publish_verified', pending);
    } on PlatformException catch (e) {
      lastFailure = DocumentDiagnostics.codes.contains(e.code)
          ? e.code
          : 'unavailable';
      diagnostics.record(lastFailure!, pending);
      _untrackedSave = true;
      connection = switch (e.code) {
        'renamed' => DocumentConnection.renamed,
        'external_changed' => DocumentConnection.externalChanged,
        'write_failed' ||
        'verification_failed' => DocumentConnection.saveFailed,
        'local_failed' => DocumentConnection.localFailed,
        _ => DocumentConnection.unavailable,
      };
      if (connection == DocumentConnection.localFailed) localDurable = false;
      diagnostics.record(_eventCode(), pending);
    } catch (_) {
      _untrackedSave = true;
      localDurable = false;
      connection = DocumentConnection.localFailed;
      diagnostics.record('local_failed', pending);
    } finally {
      publishing = false;
      await _persist();
    }
  }

  /// Only after showing the destination and getting user confirmation.
  Future<bool> confirm({Map<String, dynamic>? selected}) async {
    if (binding == null || localDirty) return false;
    final destination = selected ?? binding!;
    try {
      final metadata = await inspect(destination['uri'] as String);
      if (selected != null &&
          (metadata['name'] != selected['name'] ||
              metadata['hash'] != selected['hash'])) {
        await check();
        return false; // The destination changed after the approval dialog.
      }
      final local = await localHash();
      final sameUri = destination['uri'] == binding!['uri'];
      final matchesBaseline = metadata['hash'] == binding!['hash'];
      final recoveredWrite =
          sameUri && _untrackedSave && metadata['hash'] == local;
      if (metadata['name'] == null || (!matchesBaseline && !recoveredWrite)) {
        observed = metadata;
        connection = connection == DocumentConnection.saveFailed
            ? connection
            : DocumentConnection.externalChanged;
        await _persist();
        return false;
      }
      await remember({
        ...binding!,
        ...metadata,
        'uri': destination['uri'],
        'hash': metadata['hash'],
        'barrier': null,
      });
      localDurable = true;
      connection = DocumentConnection.connected;
      _untrackedSave = false;
      _restored = false;
      pending = local != metadata['hash'];
      diagnostics.record('connection_confirmed', pending);
      await publish();
      return connection == DocumentConnection.connected;
    } on FileSystemException {
      await markLocalFailure();
      return false;
    } catch (_) {
      connection = DocumentConnection.unavailable;
      await _persist();
      return false;
    }
  }

  Future<void> archive() async {
    if (binding == null) return;
    await _persist();
    if (!localDurable) {
      throw StateError(
        'Local recovery could not be verified. Save a copy before switching.',
      );
    }
    final target = File('${binding!['path']}.binding.json');
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(binding), flush: true);
    await temp.rename(target.path);
    diagnostics.record('session_archived', pending);
  }

  Future<void> checkpoint({
    required bool dirty,
    String? recoveryPath,
    int? revision,
    bool markPending = false,
  }) async {
    if (binding == null) return;
    localDirty = dirty;
    if (markPending) pending = true;
    binding = {
      ...binding!,
      'localDirty': dirty,
      'localRevision': revision,
      'recoveryPath': dirty ? recoveryPath : null,
    };
    if (dirty) {
      pending = true;
      connection = DocumentConnection.localFailed;
    }
    await _persist();
  }

  Future<void> markLocalFailure() async {
    localDurable = false;
    connection = DocumentConnection.localFailed;
    lastFailure = 'local_failed';
    diagnostics.record('local_failed', pending);
    await _persist();
  }

  Future<List<Map<String, dynamic>>> retainedCollections() async {
    final result = <Map<String, dynamic>>[];
    await for (final file in directory.list()) {
      if (file is File && file.path.endsWith('.binding.json')) {
        try {
          final saved = Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()),
          );
          if (saved['path'] != binding?['path'] &&
              await File(saved['path'] as String).exists()) {
            result.add(saved);
          }
        } catch (_) {}
      }
    }
    return result;
  }

  Future<void> copyTo(Map<String, dynamic> picked, String path) async {
    final original = await read(picked['uri'] as String);
    if ((original['bytes'] as Uint8List).isNotEmpty) {
      throw StateError(
        'Choose a new file. IHTD will not replace an existing document.',
      );
    }
    await channel.invokeMethod<String>('write', {
      ...picked,
      'path': path,
      'hash': original['hash'],
    });
  }

  Future<void> exportDiagnostics({bool extended = false}) async {
    final picked = await pick(suggested: 'IHTD-diagnostics.json');
    if (picked == null) return;
    final output = diagnostics.export(
      state: _eventCode(),
      pending: pending,
      recovery: {
        'privateCommitPending': localDirty,
        'localPersistenceConfirmed': localDurable,
        'localRevision': binding?['localRevision'],
        'lastFailureCode': lastFailure,
      },
      extended: extended
          ? {
              'confirmedName': name,
              'currentName': observed?['name'],
              'provider': Uri.tryParse('${binding?['uri']}')?.host,
              'size': observed?['size'],
              'modified': observed?['modified'],
              'flags': observed?['flags'],
            }
          : null,
    );
    final path = freshPath('json');
    await File(path).writeAsString(output, flush: true);
    await copyTo(picked, path);
  }
}
