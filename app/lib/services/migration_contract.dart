import 'document_adapter.dart';

/// Native access only. Shared migration policy chooses when/what to back up and
/// verifies every returned backup; adapters never authorize a conversion.
abstract interface class MigrationBackupAdapter {
  bool get backupFolderRequired;
  Future<DocumentReference?> pickBackupFolder();
  Future<DocumentReference> createMigrationBackup({
    required DocumentReference source,
    required String snapshotPath,
    required String name,
    DocumentReference? folder,
  });
}

class MigrationFailure implements Exception {
  const MigrationFailure(this.code);
  final String code;
  @override
  String toString() =>
      'Collection upgrade stopped ($code). Original files and any verified backups have been retained. Open the upgrade details to retry or export the diagnostic log.';
}
