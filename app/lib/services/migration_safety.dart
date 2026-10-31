import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'document_adapter.dart';
import 'document_diagnostics.dart';
import 'migration_contract.dart';

/// One policy for every platform. Journals contain private recovery locations;
/// exported failure logs are a separate, strictly allowlisted representation.
class MigrationSafety {
  MigrationSafety(this.adapter, this.diagnostics);
  final DocumentAdapter adapter;
  final DocumentDiagnostics diagnostics;
  Future<String> Function(String)? command;
  String? recoveryDirectory;
  late Directory directory;
  Map<String, dynamic>? issue;
  bool logFailed = false;
  void Function()? onChanged;
  DocumentReference? _folder;
  bool _initialized = false;
  bool get hasIssue => issue != null;
  bool get severe {
    if (!hasIssue) return false;
    if (logFailed) return true;
    if (issue?['failure'] == 'interrupted') {
      return issue?['stage'] == 'publication';
    }
    return !{
      'backup_required',
      'source_changed',
      'snapshot_required',
      'unavailable',
    }.contains(issue?['failure']);
  }

  String get summary => 'Collection upgrade needs attention';
  String get explanation {
    final code = issue?['failure'] ?? 'none';
    final stage = issue?['stage'] ?? 'none';
    final detail = switch (code) {
      'backup_required' => 'Choose an authorized backup folder before upgrading. Cancelling keeps the original unchanged.',
      'backup_failed' => 'The backup could not be written. Check folder access, free storage and provider availability, then retry.',
      'backup_verification_failed' => 'The backup could not be verified. IHTD has not converted the source. Choose a reliable backup location and retry.',
      'source_changed' => 'The selected file changed or was replaced during preparation. Reopen the external version after preserving unpublished work.',
      'unavailable' => 'The selected file is unavailable. Restore its permission or storage connection before retrying.',
      'snapshot_required' => 'This file may have an active SQLite journal or WAL. Close its writer and use a complete, closed collection snapshot before retrying.',
      'unsupported_version' => 'This collection uses an unsupported format. Use a compatible app version; IHTD will not downgrade it.',
      'validation_failed' => 'The converted copy did not pass data-preservation checks. Keep the original and export the diagnostic log for investigation.',
      'publication_failed' => 'The upgraded file could not be published and verified. Keep the backup and recovered edits; check the external file before reconnecting.',
      'interrupted' => 'A previous upgrade was interrupted. No write will be replayed automatically. Review its backup and recovery copies before retrying.',
      _ => 'The upgrade could not complete safely. Check local storage and export the diagnostic log for investigation.',
    };
    return '$detail\n\nThe upgrade stopped at $stage ($code). Automatic migration writes are paused. '
        'Original private files, candidates and completed backups are retained. '
        'A provider write interrupted at publication may be incomplete; do not overwrite it blindly. '
        'Review the backup locations below. Retry opening the original collection after resolving the problem; '
        'use Retained working copies for unpublished edits, or export originals/candidates through Upgrade recovery files. '
        'Reopening a backup creates a separate working copy. '
        '${logFailed ? 'The diagnostic log could not be saved. Check free storage.' : 'A redacted diagnostic log is stored privately and can be exported.'}';
  }

  List<String> get backupLocations => [
    for (final backup in (issue?['backups'] as List? ?? []))
      if (backup is Map && backup['verified'] == true)
        DocumentReference.fromJson(
          Map<String, dynamic>.from(backup['reference'] as Map),
        ).locator,
  ];

  String _id() =>
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
  Future<void> _json(File target, Object data) async {
    final temp = File('${target.path}.${_id()}.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename(target.path);
  }

  Future<void> _save(Map<String, dynamic> job) async =>
      _json(File('${directory.path}/${job['id']}.attempt.json'), job);

  Future<void> initialize(Directory documents) async {
    if (_initialized) return;
    directory = Directory('${documents.path}/migrations');
    try {
      await directory.create(recursive: true);
    } catch (_) {
      final job = _newJob('preflight', 0, 0);
      await fail(job, 'local_failed');
      throw const MigrationFailure('local_failed');
    }
    _initialized = true;
    final folder = File('${directory.path}/backup-folder.json');
    if (await folder.exists()) {
      try {
        _folder = DocumentReference.fromJson(
          Map<String, dynamic>.from(jsonDecode(await folder.readAsString())),
        );
        if (_folder!.kind != adapter.kind) _folder = null;
      } catch (_) {
        _folder = null;
      }
    }
    // Completed/failed attempts stay available. An unfinished attempt is NEVER
    // automatically replayed, especially after a potentially partial SAF write.
    final attempts = <Map<String, dynamic>>[];
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.attempt.json')) continue;
      try {
        final job = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()),
        );
        if (job['status'] == 'running') {
          await fail(job, 'interrupted');
        }
        if (job['status'] == 'failed') attempts.add(job);
      } catch (_) {
        final job = _newJob('journal', 0, 0);
        await fail(job, 'journal_unreadable');
        attempts.add(job);
      }
    }
    attempts.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    if (attempts.isNotEmpty) {
      issue = attempts.last;
      logFailed = !await File('${directory.path}/${issue!['id']}.failure.json')
          .exists();
    }
  }

  Map<String, dynamic> _newJob(String stage, int from, int target) => {
    'id': _id(),
    'status': 'running',
    'stage': stage,
    'from': from,
    'target': target,
    'started': DateTime.now().toUtc().toIso8601String(),
    'backups': <dynamic>[],
    'events': <dynamic>[],
  };
  Future<void> _stage(Map<String, dynamic> job, String stage) async {
    job['stage'] = stage;
    (job['events'] as List).add({
      'stage': stage,
      'time': DateTime.now().toUtc().toIso8601String(),
    });
    await _save(job); // Failure to persist intent prevents the next mutation.
  }

  static const stages = {
    'preflight',
    'backup',
    'backupVerified',
    'candidate',
    'candidateValidated',
    'publication',
    'metadataBackup',
    'metadataConversion',
    'completed',
    'journal',
  };
  static const failureCodes = {
    'backup_required',
    'backup_failed',
    'backup_verification_failed',
    'local_failed',
    'source_changed',
    'invalid_format',
    'snapshot_required',
    'unsupported_version',
    'candidate_failed',
    'unavailable',
    'validation_failed',
    'publication_failed',
    'interrupted',
    'journal_unreadable',
    'engine_unavailable',
    'metadata_failed',
  };
  Future<void> fail(Map<String, dynamic> job, String code) async {
    job['failure'] = failureCodes.contains(code) ? code : 'local_failed';
    job['status'] = 'failed';
    job['failedAt'] = DateTime.now().toUtc().toIso8601String();
    issue = job;
    logFailed = false;
    try {
      await _save(job);
    } catch (_) {
      logFailed = true;
    }
    try {
      // No exception text, names, hashes, paths, URIs or document IDs. Anonymous
      // backup/candidate references correlate stages without exposing content.
      final environment = jsonDecode(
        diagnostics.export(state: 'migration_failed', pending: true),
      )['environment'];
      final safe = {
        'formatVersion': 1,
        'attempt': RegExp(r'^[0-9]+-[0-9a-f]+$').hasMatch('${job['id']}')
            ? job['id']
            : 'unknown',
        'environment': environment,
        'sourceFormat': job['from'] is int ? job['from'] : null,
        'targetFormat': job['target'] is int ? job['target'] : null,
        'plans': [
          for (final plan in job['plans'] as List? ?? [])
            if ({
              'schema-1-to-2',
              'protected-all-tasks',
              'schema-1-to-2-and-protected-all-tasks',
            }.contains(plan))
              plan,
        ],
        'started': DateTime.tryParse('${job['started']}')
            ?.toUtc()
            .toIso8601String(),
        'failedAt': job['failedAt'],
        'stage': stages.contains(job['stage']) ? job['stage'] : 'unknown',
        'code': job['failure'],
        'backups': [
          for (var i = 0; i < (job['backups'] as List).length; i++)
            {
              'reference': 'backup-${i + 1}',
              'verified': job['backups'][i]['verified'] == true,
            },
        ],
        'candidateValidated': job['candidateValidated'] == true,
        'stages': [
          for (final event in (job['events'] as List? ?? []))
            if (event is Map && stages.contains(event['stage']))
              {
                'stage': event['stage'],
                'time': DateTime.tryParse('${event['time']}')
                    ?.toUtc()
                    .toIso8601String(),
              },
        ],
        'validation': {
          for (final key in ['items', 'tags', 'views', 'links'])
            if ((job['validation'] as Map?)?[key] is int)
              key: job['validation'][key],
        },
      };
      await _json(File('${directory.path}/${job['id']}.failure.json'), safe);
    } catch (_) {
      logFailed = true;
    }
    onChanged?.call();
  }

  Future<Map<String, dynamic>> _engine(
    String action,
    String path, {
    Map<String, dynamic> extra = const {},
  }) async {
    if (command == null) throw const MigrationFailure('engine_unavailable');
    final result = Map<String, dynamic>.from(
      jsonDecode(
        await command!(
          jsonEncode({
            'op': 'migration',
            'action': action,
            'source': path,
            ...extra,
          }),
        ),
      ),
    );
    if (result['ok'] != true) throw MigrationFailure('${result['error_code']}');
    return Map<String, dynamic>.from(result['data'] as Map);
  }

  Future<Map<String, dynamic>?> _probe(String path) async {
    // Non-SQLite data is rejected by the normal model loader. This avoids doing
    // migrations on exports/JSON and keeps document adapters format agnostic.
    final file = await File(path).open();
    late List<int> header;
    try {
      header = await file.read(16);
    } finally {
      await file.close();
    }
    if (utf8.decode(header, allowMalformed: true) != 'SQLite format 3\u0000') {
      return null;
    }
    return _engine('probe', path, extra: {'recovery_dir': recoveryDirectory});
  }

  Future<void> chooseBackupFolder() async {
    final service = adapter;
    if (service is! MigrationBackupAdapter) {
      throw const MigrationFailure('backup_required');
    }
    final access = service as MigrationBackupAdapter;
    final picked = await access.pickBackupFolder();
    if (picked == null) throw const MigrationFailure('backup_required');
    await _json(File('${directory.path}/backup-folder.json'), picked.toJson());
    _folder = picked;
  }

  Future<void> _backup(
    Map<String, dynamic> job,
    DocumentReference source,
    String snapshot,
    String role,
  ) async {
    final service = adapter;
    if (service is! MigrationBackupAdapter) {
      throw const MigrationFailure('backup_required');
    }
    final access = service as MigrationBackupAdapter;
    if (access.backupFolderRequired && _folder == null) {
      await chooseBackupFolder();
    }
    final expected = await adapter.localHash(snapshot);
    DocumentReference reference;
    try {
      reference = await access.createMigrationBackup(
        source: source,
        snapshotPath: snapshot,
        name: 'IHTD-before-upgrade-${job['id']}-$role.ihtd',
        folder: _folder,
      );
    } catch (_) {
      throw const MigrationFailure('backup_failed');
    }
    if (reference.sameLocation(source)) {
      throw const MigrationFailure('backup_verification_failed');
    }
    final record = {
      'reference': reference.toJson(),
      'verified': false,
      'role': role,
    };
    (job['backups'] as List).add(record);
    await _save(job);
    late DocumentRead verified;
    try {
      verified = await adapter.read(reference);
    } catch (_) {
      throw const MigrationFailure('backup_verification_failed');
    }
    // Hash and actual read-back bytes must match the closed source snapshot.
    final bytes = await File(snapshot).readAsBytes();
    if (verified.hash != expected || !_equal(bytes, verified.bytes)) {
      throw const MigrationFailure('backup_verification_failed');
    }
    record['verified'] = true;
    await _save(job);
  }

  bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  DocumentReference _reference(Map<String, dynamic> record) =>
      record['reference'] is Map
      ? DocumentReference.fromJson(
          Map<String, dynamic>.from(record['reference']),
        )
      : adapter.referenceFor(record['uri'] as String);

  /// Input is a closed private snapshot. Output is a different validated file.
  /// Originals/old recovery paths are never overwritten, even on successful upgrade.
  Future<Map<String, dynamic>> prepare(
    Map<String, dynamic> record, {
    bool retained = false,
    bool automatic = false,
  }) async {
    Map<String, dynamic>? job;
    bool paused = false;
    try {
      final path = record['path'] as String;
      final probe = await _probe(path);
      final recovery =
          (record['recoveryPath'] ?? probe?['recovery_path']) as String?;
      final recoveryProbe = recovery != null && await File(recovery).exists()
          ? await _probe(recovery)
          : null;
      if (probe?['needed'] != true && recoveryProbe?['needed'] != true) {
        if (!retained && !automatic && probe != null) {
          await reconcileExternal(record, probe['hash'] as String);
        }
        final attempt = record['migrationAttempt'] as String?;
        if (attempt != null) {
          final old = await _job(attempt);
          if ({'completed', 'resolved'}.contains(old['status'])) {
            return {...record, 'migrationAttempt': null};
          }
        }
        return record;
      }
      if (automatic) {
        for (final failed in await recoveryAttempts()) {
          if (failed['status'] == 'failed' &&
              failed['original'] is Map &&
              _reference(Map<String, dynamic>.from(failed['original']))
                  .sameLocation(_reference(record))) {
            issue = failed;
            logFailed = !await File(
              '${directory.path}/${failed['id']}.failure.json',
            ).exists();
            paused = true;
            throw MigrationFailure('${failed['failure']}');
          }
        }
      }
      job = _newJob(
        'preflight',
        (probe?['from'] as int?) ?? 0,
        (probe?['target'] as int?) ?? 0,
      );
      job['original'] = record;
      job['plans'] = [
        probe?['plan'],
        recoveryProbe?['plan'],
      ].whereType<String>().toSet().toList();
      await _save(job);
      final source = _reference(record);
      // Protect the bound external baseline independently of unpublished local
      // edits/recovery. Do not use a matching UUID as evidence of file identity.
      final external = await adapter.read(source);
      final observation = await adapter.inspect(source);
      if (external.hash != record['hash'] ||
          observation.hash != external.hash ||
          (record['name'] != null && observation.name != record['name']) ||
          (record['identity'] != null &&
              observation.identity != record['identity'])) {
        throw const MigrationFailure('source_changed');
      }
      final snapshot = '${directory.path}/${job['id']}.external.ihtd';
      job['externalSnapshot'] = snapshot;
      await _save(job);
      await File(snapshot).writeAsBytes(external.bytes, flush: true);
      await _stage(job, 'backup');
      await _backup(job, source, snapshot, 'external');
      if (retained) await _backup(job, source, path, 'working');
      if (recoveryProbe != null) {
        await _backup(job, source, recovery!, 'recovery');
      }
      await _stage(job, 'backupVerified');
      final next = {
        ...record,
        if (recoveryProbe != null) 'recoveryPath': recovery,
      };
      for (final entry in [
        (path, probe, 'path'),
        if (recoveryProbe != null) (recovery!, recoveryProbe, 'recoveryPath'),
      ]) {
        if (entry.$2?['needed'] != true) continue;
        final candidate =
            '${directory.path}/${job['id']}.${entry.$3}.candidate.ihtd';
        job['candidate'] = candidate;
        (job['candidates'] ??= <dynamic>[]).add({
          'role': entry.$3,
          'path': candidate,
          'sourcePath': entry.$1,
          'sourceHash': entry.$2!['hash'],
        });
        await _stage(job, 'candidate');
        final result = await _engine(
          'prepare',
          entry.$1,
          extra: {'candidate': candidate, 'expected_hash': entry.$2!['hash']},
        );
        if (result['validated'] != true) {
          throw const MigrationFailure('validation_failed');
        }
        final evidence = (job['candidates'] as List).last as Map;
        evidence['sourceDigest'] = result['source_digest'];
        evidence['sourceNextId'] = result['source_next_id'];
        next[entry.$3] = candidate;
        (job['candidateHashes'] ??= <String, dynamic>{})[candidate] =
            result['hash'];
        job['validation'] = {
          for (final key in ['items', 'tags', 'views', 'links'])
            if (result[key] is int) key: result[key],
        };
      }
      job['candidateValidated'] = true;
      job['prepared'] = next;
      await _stage(job, 'candidateValidated');
      return {...next, 'migrationAttempt': job['id']};
    } catch (e) {
      if (paused) rethrow;
      job ??= _newJob('preflight', 0, 0)..['original'] = record;
      await fail(
        job,
        e is MigrationFailure
            ? e.code
            : e is DocumentFailure
            ? e.code
            : 'local_failed',
      );
      throw MigrationFailure('${job['failure']}');
    }
  }

  Future<Map<String, dynamic>> _job(String id) async =>
      Map<String, dynamic>.from(
        jsonDecode(
          await File('${directory.path}/$id.attempt.json').readAsString(),
        ),
      );
  Future<void> publicationStarted(String id) async {
    final job = await _job(id);
    if (job['status'] != 'running' || job['stage'] != 'candidateValidated') {
      throw const MigrationFailure('publication_failed');
    }
    try {
      await _stage(job, 'publication');
    } catch (_) {
      await fail(job, 'local_failed');
      throw const MigrationFailure('local_failed');
    }
  }

  Future<void> publicationFinished(String id, bool success) async {
    final job = await _job(id);
    if (!success) {
      await fail(job, 'publication_failed');
      return;
    }
    job['status'] = 'completed';
    job['stage'] = 'completed';
    try {
      await _save(job);
    } catch (_) {
      await fail(job, 'local_failed');
      return;
    }
    // Keep every backup, original and candidate; no cleanup on update.
    await resolveFor(Map<String, dynamic>.from(job['original']));
    onChanged?.call();
  }

  /// Explicit reopening is safe reconciliation only when the external bytes
  /// exactly match a previously validated candidate. Never repair partial bytes
  /// or transfer unpublished edits on the strength of a filename/UUID.
  Future<void> reconcileExternal(
    Map<String, dynamic> record,
    String hash,
  ) async {
    for (final previous in await recoveryAttempts()) {
      if (previous['status'] != 'failed' ||
          previous['original'] is! Map ||
          previous['candidateValidated'] != true ||
          previous['candidateHashes'] is! Map) {
        continue;
      }
      if (_reference(Map<String, dynamic>.from(previous['original']))
              .sameLocation(_reference(record)) &&
          (previous['candidateHashes'] as Map).values.contains(hash)) {
        await resolveFor(record);
        onChanged?.call();
        return;
      }
    }
  }

  Future<void> resolveFor(Map<String, dynamic> original) async {
    for (final previous in await recoveryAttempts()) {
      if (previous['status'] != 'failed' || previous['original'] is! Map) {
        continue;
      }
      if (_reference(Map<String, dynamic>.from(previous['original']))
          .sameLocation(_reference(original))) {
        previous['status'] = 'resolved';
        await _save(previous);
      }
    }
    if (issue?['original'] is Map &&
        _reference(Map<String, dynamic>.from(issue!['original']))
            .sameLocation(_reference(original))) {
      issue = null;
    }
  }

  Future<String?> expectedHashForOpen(String path) async {
    for (final job in await recoveryAttempts()) {
      if (job['status'] == 'running' && job['candidateHashes'] is Map) {
        final expected = job['candidateHashes'][path] as String?;
        if (expected != null) return expected;
      }
    }
    return null;
  }

  /// An explicit draft Restore may follow this exact, backed-up conversion.
  /// UUID equality alone never authorizes rebinding a draft to another file.
  /// This is read-only: the original draft and source remain untouched.
  Future<bool> preservesDraftOwner(String original, String current) async =>
      await draftOwnerEvidence(original, current) != null;

  Future<Map<String, dynamic>?> draftOwnerEvidence(
    String original,
    String current,
  ) async {
    for (final job in await recoveryAttempts()) {
      final plans = job['plans'];
      if (plans is! List ||
          plans.isEmpty ||
          !plans.every(
            (plan) => {
              'none',
              'schema-1-to-2',
              'protected-all-tasks',
              'schema-1-to-2-and-protected-all-tasks',
            }.contains(plan),
          )) {
        continue;
      }
      if (job['candidateValidated'] != true ||
          (job['prepared'] as Map?)?['path'] != current) {
        continue;
      }
      for (final candidate in job['candidates'] as List? ?? []) {
        if (candidate is! Map ||
            candidate['role'] != 'path' ||
            candidate['path'] != current ||
            candidate['sourcePath'] != original ||
            candidate['sourceHash'] is! String) {
          continue;
        }
        try {
          if (await adapter.localHash(original) == candidate['sourceHash']) {
            return Map<String, dynamic>.from(candidate);
          }
        } catch (_) {
          // Missing/changed evidence cannot authorize another owner.
        }
      }
    }
    return null;
  }

  Future<void> candidateOpenFailed(String path) async {
    for (final job in await recoveryAttempts()) {
      if (job['status'] == 'running' &&
          (job['prepared'] as Map?)?['path'] == path) {
        await fail(job, 'validation_failed');
      }
    }
  }

  Future<Map<String, dynamic>> readMetadata(File file) async {
    try {
      return Map<String, dynamic>.from(jsonDecode(await file.readAsString()));
    } catch (_) {
      // Preserve even an unreadable registry before another collection can
      // replace active.json; the raw backup may still be useful for recovery.
      await protectMetadata(file, (_) async {
        throw const MigrationFailure('metadata_failed');
      });
      throw const MigrationFailure('metadata_failed');
    }
  }

  /// Registry conversion is private metadata, not an external collection.
  /// Back it up unchanged beside its original and verify before replacing it.
  Future<void> protectMetadata(
    File source,
    Future<void> Function(Map<String, dynamic>) convert,
  ) async {
    final job = _newJob('metadataBackup', 0, 3);
    job['metadataSource'] = source.path;
    try {
      await _save(job);
      final bytes = await source.readAsBytes();
      final backup = File('${source.path}.before-upgrade-${job['id']}.json');
      await backup.create(exclusive: true);
      await backup.writeAsBytes(bytes, flush: true);
      if (!_equal(bytes, await backup.readAsBytes())) {
        throw const MigrationFailure('backup_verification_failed');
      }
      (job['backups'] as List).add({
        'reference': DocumentReference('private', backup.path).toJson(),
        'verified': true,
      });
      final metadata = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes)),
      );
      job['from'] = metadata['version'] is int ? metadata['version'] : 0;
      if ((job['from'] as int) > 3) {
        throw const MigrationFailure('unsupported_version');
      }
      if (!_equal(bytes, await source.readAsBytes())) {
        throw const MigrationFailure('source_changed');
      }
      await _stage(job, 'metadataConversion');
      await convert(metadata);
      job['status'] = 'completed';
      job['stage'] = 'metadataConverted';
      await _save(job);
      for (final previous in await recoveryAttempts()) {
        if (previous['status'] == 'failed' &&
            previous['metadataSource'] == source.path) {
          previous['status'] = 'resolved';
          await _save(previous);
        }
      }
      if (issue?['metadataSource'] == source.path) issue = null;
    } catch (e) {
      await fail(job, e is MigrationFailure ? e.code : 'metadata_failed');
      throw const MigrationFailure('metadata_failed');
    }
  }

  Future<List<Map<String, dynamic>>> recoveryAttempts() async {
    final results = <Map<String, dynamic>>[];
    await for (final file in directory.list()) {
      if (file is File && file.path.endsWith('.attempt.json')) {
        try {
          results.add(
            Map<String, dynamic>.from(jsonDecode(await file.readAsString())),
          );
        } catch (_) {}
      }
    }
    return results;
  }

  Future<String> exportLog() async {
    final id = issue?['id'];
    if (logFailed || id == null) throw const MigrationFailure('local_failed');
    return File('${directory.path}/$id.failure.json').readAsString();
  }
}
