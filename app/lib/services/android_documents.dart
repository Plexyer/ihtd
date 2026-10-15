import 'package:flutter/services.dart';

import 'document_adapter.dart';

class AndroidDocumentAdapter implements DocumentAdapter {
  static const channel = MethodChannel('dev.ihtd.app/documents');
  @override
  String get kind => 'android';
  @override
  List<String> get legacyRegistryNames => ['android-documents'];
  @override
  DocumentReference referenceFor(String locator) =>
      DocumentReference(kind, locator);

  Future<T?> _invoke<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw DocumentFailure.fromCode(e.code);
    }
  }

  Future<Map<String, dynamic>> _map(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async =>
      Map<String, dynamic>.from((await _invoke<Map>(method, arguments))!);
  @override
  Future<Map<String, dynamic>> environment() => _map('environment');
  @override
  Future<DocumentReference?> pick({String? suggested}) async {
    final picked = await _invoke<Map>(suggested == null ? 'open' : 'create', {
      'name': suggested,
    });
    return picked == null
        ? null
        : DocumentReference(
            kind,
            picked['uri'] as String,
            nameHint: picked['name'] as String?,
          );
  }

  @override
  Future<DocumentRead> read(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async {
    final content = await _map('read', {'uri': reference.locator});
    return DocumentRead(
      content['bytes'] as Uint8List,
      content['hash'] as String,
    );
  }

  @override
  Future<DocumentObservation> inspect(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async => DocumentObservation.fromJson(
    await _map('inspect', {'uri': reference.locator}),
  );
  @override
  Future<String> localHash(String path) async =>
      (await _invoke<String>('localHash', {'path': path}))!;
  @override
  Future<DocumentObservation> publish(
    DocumentReference reference,
    String workingPath, {
    required String expectedHash,
    String? expectedName,
    String? expectedIdentity,
    bool create = false,
  }) async {
    final hash = await _invoke<String>('write', {
      'uri': reference.locator,
      'path': workingPath,
      'hash': expectedHash,
      'name': expectedName,
    });
    final observation = await inspect(reference);
    if (hash != observation.hash) {
      throw const DocumentFailure(DocumentFailureKind.verificationFailed);
    }
    return observation;
  }
}
