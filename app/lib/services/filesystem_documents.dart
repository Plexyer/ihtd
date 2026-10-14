import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'document_adapter.dart';

class FilesystemDocumentAdapter implements DocumentAdapter {
  FilesystemDocumentAdapter(this.command);
  final Future<String> Function(String) command;
  @override
  String get kind => 'filesystem';
  @override
  List<String> get legacyRegistryNames => [];
  @override
  DocumentReference referenceFor(String locator) => DocumentReference(
    kind,
    File(locator).absolute.path,
    nameHint: File(locator).uri.pathSegments.last,
  );

  Future<Map<String, dynamic>> _operation(Map<String, dynamic> request) async {
    final response = jsonDecode(
      await command(jsonEncode({'op': 'filesystem', ...request})),
    ) as Map;
    if (response['ok'] != true) {
      throw DocumentFailure.fromCode(
        response['error_code'] as String? ?? 'unavailable',
      );
    }
    return Map<String, dynamic>.from(response['data'] as Map);
  }

  @override
  Future<Map<String, dynamic>> environment() async {
    final info = await PackageInfo.fromPlatform();
    return {
      'appVersion': info.version,
      'build': int.tryParse(info.buildNumber),
      'os': Platform.operatingSystem,
      'osVersion': RegExp(r'\d+(\.\d+)*')
          .firstMatch(Platform.operatingSystemVersion)
          ?.group(0),
    };
  }

  @override
  Future<DocumentReference?> pick({String? suggested}) async {
    if (suggested == null) {
      final picked = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'IHTD collection', extensions: ['ihtd']),
        ],
      );
      return picked == null ? null : referenceFor(picked.path);
    }
    final extension = suggested.split('.').last;
    final picked = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (picked == null) return null;
    return referenceFor(
      picked.path.toLowerCase().endsWith('.$extension')
          ? picked.path
          : '${picked.path}.$extension',
    );
  }

  @override
  Future<DocumentRead> read(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async {
    final content = await _operation({
      'action': 'read',
      'destination': reference.locator,
      'allow_missing': allowMissing,
    });
    return DocumentRead(
      Uint8List.fromList((content['bytes'] as List).cast<int>()),
      content['hash'] as String,
    );
  }

  @override
  Future<DocumentObservation> inspect(
    DocumentReference reference, {
    bool allowMissing = false,
  }) async => DocumentObservation.fromJson(
    await _operation({
      'action': 'inspect',
      'destination': reference.locator,
      'allow_missing': allowMissing,
    }),
  );
  @override
  Future<String> localHash(String path) async =>
      (await _operation({'action': 'hash', 'working': path}))['hash'] as String;
  @override
  Future<DocumentObservation> publish(
    DocumentReference reference,
    String workingPath, {
    required String expectedHash,
    String? expectedName,
    String? expectedIdentity,
    bool create = false,
  }) async => DocumentObservation.fromJson(
    await _operation({
      'action': 'publish',
      'destination': reference.locator,
      'working': workingPath,
      'expected_hash': expectedHash,
      'expected_name': expectedName,
      'expected_identity': expectedIdentity,
      'allow_missing': create,
    }),
  );
}
