import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'document_adapter.dart';

import 'package:path_provider/path_provider.dart';

import 'document_diagnostics.dart';
import 'migration_safety.dart';

enum DocumentConnection {
  checking,
  connected,
  renamed,
  unavailable,
  externalChanged,
  replaced,
  saveFailed,
  localFailed,
  reconnectRequired,
}

class SaveState {
  const SaveState({
    required this.connection,
    required this.pending,
    required this.publishing,
    required this.localDurable,
    required this.localDirty,
  });
  final DocumentConnection connection;
  final bool pending, publishing, localDurable, localDirty;
  bool get severe =>
      connection == DocumentConnection.saveFailed ||
      connection == DocumentConnection.localFailed ||
      !localDurable;
}

/// External binding, private edits and confirmed revision are independent.
/// A persisted barrier can only be released by an explicit user action.
class DocumentSaveCoordinator {
  DocumentSaveCoordinator({
    required this.adapter,
    Future<Directory> Function()? supportDirectory,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _supportDirectory;
  final DocumentAdapter adapter;
  late final migrations = MigrationSafety(adapter, diagnostics);
  final List<Directory> _legacyDirectories = [];
  DocumentReference referenceOf(Map<String, dynamic> record) =>
      record['reference'] is Map
      ? DocumentReference.fromJson(
          Map<String, dynamic>.from(record['reference']),
        )
      : adapter.referenceFor(record['uri'] as String);
  String? get externalLocation =>
      binding == null ? null : referenceOf(binding!).locator;
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
  SaveState get state => SaveState(
    connection: connection,
    pending: pending,
    publishing: publishing,
    localDurable: localDurable,
    localDirty: localDirty,
  );
  void Function()? onStateChanged;
  late Directory directory;
  final diagnostics = DocumentDiagnostics();
  String? get name => binding?['name'] as String?;
  bool get hasIssue =>
      migrations.hasIssue ||
      (binding != null && connection != DocumentConnection.connected);
  bool get severe => state.severe || migrations.severe;
  String get summary {
    if (migrations.hasIssue) return migrations.summary;
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
      DocumentConnection.replaced => 'Selected file was replaced',
      DocumentConnection.saveFailed => 'File save could not be verified',
      DocumentConnection.reconnectRequired =>
        'Confirm file connection to continue',
      DocumentConnection.localFailed => 'Local saving failed',
    };
  }

  String get explanation {
    if (migrations.hasIssue) return migrations.explanation;
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
      DocumentConnection.replaced =>
        'File identity changed at the selected location. It may have been replaced or rewritten by another app. '
            '${observed?['hash'] == binding?['hash'] ? 'Contents are unchanged since the last confirmed save.' : 'Contents also changed.'} '
            'The original working copy is retained locally. Select a destination explicitly or save a separate copy; a matching name is not proof of file identity.',
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
    directory = Directory('${support.path}/documents');
    await directory.create(recursive: true);
    await diagnostics.initialize(directory);
    try {
      diagnostics.environment = Map<String, dynamic>.from(
        await adapter.environment(),
      );
    } catch (_) {}
    migrations.onChanged = () => onStateChanged?.call();
    await migrations.initialize(directory);
    final file = File('${directory.path}/active.json');
    if (!await file.exists()) {
      for (final legacyName in adapter.legacyRegistryNames) {
        final legacy = Directory('${support.path}/$legacyName');
        final active = File('${legacy.path}/active.json');
        if (await active.exists()) {
          // Copy only metadata. Existing working/recovery files remain intact.
          await migrations.protectMetadata(
            active,
            (metadata) => _rememberVerified(metadata),
          );
          break;
        }
      }
    }
    for (final legacyName in adapter.legacyRegistryNames) {
      _legacyDirectories.add(Directory('${support.path}/$legacyName'));
    }
    if (await file.exists()) {
      final loaded = await migrations.readMetadata(file);
      if (loaded['version'] != 3) {
        await migrations.protectMetadata(
          file,
          (metadata) => _rememberVerified(metadata),
        );
      } else {
        binding = loaded;
      }
      connection = _state(binding?['barrier']);
      pending = binding?['pending'] == true;
      _untrackedSave = binding?['untrackedSave'] == true;
      localDirty = binding?['localDirty'] == true;
      localDurable = binding?['localDurable'] != false;
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
    'replaced' => DocumentConnection.replaced,
    'saveFailed' => DocumentConnection.saveFailed,
    'localFailed' => DocumentConnection.localFailed,
    'reconnectRequired' => DocumentConnection.reconnectRequired,
    _ => DocumentConnection.checking,
  };
  Future<void> remember(Map<String, dynamic> next) async {
    binding = {...next, 'version': 3, 'reference': referenceOf(next).toJson()}
      ..remove('uri');
    if (referenceOf(binding!).kind != adapter.kind) {
      throw const DocumentFailure(DocumentFailureKind.unavailable);
    }
    _needsPersistence = true;
    final temp = File('${directory.path}/active.json.tmp');
    await temp.writeAsString(jsonEncode(binding), flush: true);
    if (jsonEncode(jsonDecode(await temp.readAsString())) !=
        jsonEncode(binding)) {
      throw const FormatException('Registry candidate verification failed');
    }
    await temp.rename('${directory.path}/active.json');
    _needsPersistence = false;
  }

  Future<void> _rememberVerified(Map<String, dynamic> record) async {
    await remember(record);
    final verified = jsonDecode(
      await File('${directory.path}/active.json').readAsString(),
    );
    if (jsonEncode(verified) != jsonEncode(binding)) {
      throw const FormatException('Registry verification failed');
    }
  }

  Future<void> _persist() async {
    if (binding == null) return;
    try {
      await remember({
        ...binding!,
        'pending': pending,
        'localDurable': localDurable,
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
    final reference = await adapter.pick(suggested: suggested);
    return reference == null
        ? null
        : {'reference': reference.toJson(), 'name': reference.nameHint};
  }

  Future<Map<String, dynamic>> read(
    Map<String, dynamic> selected, {
    bool allowMissing = false,
  }) async {
    final content = await adapter.read(
      referenceOf(selected),
      allowMissing: allowMissing,
    );
    return {'bytes': content.bytes, 'hash': content.hash};
  }

  Future<Map<String, dynamic>> inspect(Map<String, dynamic> selected) async =>
      (await adapter.inspect(
        referenceOf(selected),
        allowMissing: selected['creating'] == true,
      )).toJson();
  Future<String> localHash() => adapter.localHash(binding!['path'] as String);
  Future<Map<String, dynamic>> stage(Map<String, dynamic> picked) async {
    final content = await read(picked);
    final metadata = await inspect(picked);
    if (content['hash'] != metadata['hash']) {
      throw StateError('The selected file changed while opening. Try again.');
    }
    final path = freshPath();
    await File(path).writeAsBytes(content['bytes'] as Uint8List, flush: true);
    return migrations.prepare({
      ...picked,
      ...metadata,
      'path': path,
      'hash': content['hash'],
    });
  }

  Future<void> attach(
    Map<String, dynamic> next, {
    bool retained = false,
  }) async {
    diagnostics.useDocument('${next['path']}');
    observed = null;
    pending = retained && next['pending'] == true;
    localDurable = !retained || next['localDurable'] != false;
    _untrackedSave = retained && next['untrackedSave'] == true;
    lastFailure =
        retained && DocumentDiagnostics.codes.contains(next['failureCode'])
        ? next['failureCode'] as String
        : null;
    connection = retained
        ? _state(next['barrier'])
        : DocumentConnection.checking;
    if (retained && connection == DocumentConnection.checking) {
      connection = DocumentConnection.reconnectRequired;
    }
    localDirty = retained && next['localDirty'] == true;
    _restored = retained;
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
      observed = await inspect(binding!);
      final remote = observed!['hash'];
      if (observed!['name'] == null) {
        connection = DocumentConnection.unavailable;
      } else if (observed!['name'] != name) {
        connection = DocumentConnection.renamed;
      } else if (binding!['identity'] != null &&
          observed!['identity'] != binding!['identity']) {
        connection = previous == DocumentConnection.saveFailed
            ? previous
            : observed!['identity'] == null
            ? DocumentConnection.unavailable
            : DocumentConnection.replaced;
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
    } on DocumentFailure catch (e) {
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
    if (migrations.issue?['original'] is Map) {
      final original = Map<String, dynamic>.from(migrations.issue!['original']);
      if (referenceOf(original).sameLocation(referenceOf(binding!)) &&
          (binding!['migrationAttempt'] == null ||
              binding!['migrationAttempt'] == migrations.issue?['id'])) {
        return;
      }
    }
    await check();
    if (connection != DocumentConnection.connected || !pending || localDirty) {
      if (binding!['migrationAttempt'] != null) {
        await migrations.publicationFinished(
          binding!['migrationAttempt'] as String,
          false,
        );
      }
      return;
    }
    final migrationId = binding!['migrationAttempt'] as String?;
    if (migrationId != null) await migrations.publicationStarted(migrationId);
    publishing = true;
    diagnostics.record('publish_started', pending);
    // A killed write can be verified explicitly after restart, never retried
    // automatically. Persist the attempt before touching the provider.
    _untrackedSave = true;
    await _persist();
    if (!localDurable) {
      publishing = false;
      if (migrationId != null) {
        await migrations.publicationFinished(migrationId, false);
      }
      return;
    }
    try {
      final result = await adapter.publish(
        referenceOf(binding!),
        binding!['path'] as String,
        expectedHash: binding!['hash'] as String,
        expectedName: name,
        expectedIdentity: binding!['identity'] as String?,
        create: binding!['creating'] == true,
      );
      final hash = result.hash;
      observed = result.toJson();
      await remember({
        ...binding!,
        ...observed!,
        'hash': hash,
        'barrier': null,
        'creating': false,
        'migrationAttempt': null,
      });
      pending = await localHash() != hash;
      _untrackedSave = false;
      lastFailure = null;
      diagnostics.record('publish_verified', pending);
    } on DocumentFailure catch (e) {
      lastFailure = DocumentDiagnostics.codes.contains(e.code)
          ? e.code
          : 'unavailable';
      diagnostics.record(lastFailure!, pending);
      _untrackedSave = true;
      connection = switch (e.code) {
        'renamed' => DocumentConnection.renamed,
        'external_changed' => DocumentConnection.externalChanged,
        'replaced' => DocumentConnection.replaced,
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
      if (migrationId != null) {
        await migrations.publicationFinished(
          migrationId,
          connection == DocumentConnection.connected &&
              !pending &&
              localDurable,
        );
      }
    }
  }

  /// Only after showing the destination and getting user confirmation.
  Future<bool> confirm({Map<String, dynamic>? selected}) async {
    if (binding == null || localDirty) return false;
    final destination = selected ?? binding!;
    try {
      final metadata = await inspect(destination);
      if (selected != null &&
          (metadata['name'] != selected['name'] ||
              metadata['hash'] != selected['hash'] ||
              (selected['identity'] != null &&
                  metadata['identity'] != selected['identity']))) {
        await check();
        return false; // The destination changed after the approval dialog.
      }
      final local = await localHash();
      final sameUri = referenceOf(destination)
          .sameLocation(referenceOf(binding!));
      final sameIdentity =
          binding!['identity'] == null ||
          metadata['identity'] == binding!['identity'];
      final matchesBaseline =
          metadata['hash'] == binding!['hash'] &&
          (!sameUri || sameIdentity || selected?['explicitSelection'] == true);
      final recoveredWrite =
          sameUri && _untrackedSave && metadata['hash'] == local;
      if (metadata['name'] == null || (!matchesBaseline && !recoveredWrite)) {
        observed = metadata;
        connection =
            connection == DocumentConnection.saveFailed ||
                connection == DocumentConnection.replaced
            ? connection
            : DocumentConnection.externalChanged;
        await _persist();
        return false;
      }
      await remember({
        ...binding!,
        ...metadata,
        'reference': referenceOf(destination).toJson(),
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
    for (final source in [directory, ..._legacyDirectories]) {
      if (!await source.exists()) continue;
      await for (final file in source.list()) {
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
    }
    return result;
  }

  Future<void> copyTo(Map<String, dynamic> picked, String path) async {
    final original = await read(picked, allowMissing: true);
    if ((original['bytes'] as Uint8List).isNotEmpty) {
      throw StateError(
        'Choose a new file. IHTD will not replace an existing document.',
      );
    }
    await adapter.publish(
      referenceOf(picked),
      path,
      expectedHash: original['hash'] as String,
      expectedName: picked['name'] as String?,
      create: true,
    );
  }

  Future<void> exportDiagnostics({bool extended = false}) async {
    final picked = await pick(suggested: 'IHTD-diagnostics.json');
    if (picked == null) return;
    final output = migrations.hasIssue
        ? await migrations.exportLog()
        : diagnostics.export(
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
                    'adapter': adapter.kind,
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
