import 'dart:typed_data';

enum DocumentFailureKind {
  unavailable,
  renamed,
  replaced,
  externalChanged,
  writeFailed,
  verificationFailed,
  localFailed,
}

class DocumentFailure implements Exception {
  const DocumentFailure(this.kind);
  final DocumentFailureKind kind;
  String get code => switch (kind) {
    DocumentFailureKind.externalChanged => 'external_changed',
    DocumentFailureKind.writeFailed => 'write_failed',
    DocumentFailureKind.verificationFailed => 'verification_failed',
    DocumentFailureKind.localFailed => 'local_failed',
    _ => kind.name,
  };
  factory DocumentFailure.fromCode(String code) =>
      DocumentFailure(switch (code) {
        'renamed' => DocumentFailureKind.renamed,
        'replaced' => DocumentFailureKind.replaced,
        'external_changed' => DocumentFailureKind.externalChanged,
        'write_failed' => DocumentFailureKind.writeFailed,
        'verification_failed' => DocumentFailureKind.verificationFailed,
        'local_failed' => DocumentFailureKind.localFailed,
        _ => DocumentFailureKind.unavailable,
      });
  @override
  String toString() => 'Document operation failed: $code';
}

class DocumentReference {
  const DocumentReference(this.kind, this.locator, {this.nameHint});
  final String kind;
  final String locator;
  final String? nameHint;
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'locator': locator,
    'nameHint': nameHint,
  };
  factory DocumentReference.fromJson(Map<String, dynamic> json) =>
      DocumentReference(
        json['kind'] as String,
        json['locator'] as String,
        nameHint: json['nameHint'] as String?,
      );
  bool sameLocation(DocumentReference other) =>
      kind == other.kind && locator == other.locator;
}

class DocumentCapabilities {
  const DocumentCapabilities({this.writable, this.stableIdentity = false});
  final bool? writable;
  final bool stableIdentity;
}

class DocumentObservation {
  const DocumentObservation({
    required this.hash,
    this.name,
    this.identity,
    this.size,
    this.modified,
    this.flags,
    this.capabilities = const DocumentCapabilities(),
  });
  final String hash;
  final String? name, identity;
  final int? size, modified, flags;
  final DocumentCapabilities capabilities;
  factory DocumentObservation.fromJson(Map<String, dynamic> json) =>
      DocumentObservation(
        hash: json['hash'] as String,
        name: json['name'] as String?,
        identity: json['identity'] as String?,
        size: (json['size'] as num?)?.toInt(),
        modified: (json['modified'] as num?)?.toInt(),
        flags: (json['flags'] as num?)?.toInt(),
        capabilities: DocumentCapabilities(
          writable: json['writable'] as bool?,
          stableIdentity: json['identity'] != null,
        ),
      );
  Map<String, dynamic> toJson() => {
    'name': name,
    'hash': hash,
    'identity': identity,
    'size': size,
    'modified': modified,
    'flags': flags,
    'writable': capabilities.writable,
  };
}

class DocumentRead {
  const DocumentRead(this.bytes, this.hash);
  final Uint8List bytes;
  final String hash;
}

/// OS access only. Severity, messages, confirmation and recovery policy live
/// in DocumentSaveCoordinator and are never implemented by an adapter.
abstract interface class DocumentAdapter {
  String get kind;
  List<String> get legacyRegistryNames;
  DocumentReference referenceFor(String locator);
  Future<Map<String, dynamic>> environment();
  Future<DocumentReference?> pick({String? suggested});
  Future<DocumentRead> read(
    DocumentReference reference, {
    bool allowMissing = false,
  });
  Future<DocumentObservation> inspect(
    DocumentReference reference, {
    bool allowMissing = false,
  });
  Future<String> localHash(String path);
  Future<DocumentObservation> publish(
    DocumentReference reference,
    String workingPath, {
    required String expectedHash,
    String? expectedName,
    String? expectedIdentity,
    bool create = false,
  });
}
