import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// SAF documents are copied to private files before entering the Rust backend.
/// The binding and working file survive process death and failed provider writes.
class AndroidDocuments {
  AndroidDocuments({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _supportDirectory;
  static const channel = MethodChannel('dev.ihtd.app/documents');
  Map<String, dynamic>? binding;
  bool _needsPersistence = false;
  late Directory directory;
  String? get name => binding?['name'] as String?;

  Future<Map<String, dynamic>?> initialize() async {
    final support = await _supportDirectory();
    directory = Directory('${support.path}/android-documents');
    await directory.create(recursive: true);
    final file = File('${directory.path}/active.json');
    if (await file.exists()) {
      binding = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()),
      );
    }
    return binding;
  }

  Future<void> remember(Map<String, dynamic> next) async {
    // Keep the in-memory binding attached to the new working file even if a
    // full disk prevents committing its restart metadata. Never save through
    // the previous document's URI after switching the Rust session.
    binding = next;
    _needsPersistence = true;
    final temp = File('${directory.path}/active.json.tmp');
    await temp.writeAsString(jsonEncode(next), flush: true);
    await temp.rename('${directory.path}/active.json');
    _needsPersistence = false;
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

  Future<Map<String, dynamic>> stage(Map<String, dynamic> picked) async {
    final content = await read(picked['uri'] as String);
    final path = freshPath();
    await File(path).writeAsBytes(content['bytes'] as Uint8List, flush: true);
    return {...picked, 'path': path, 'hash': content['hash']};
  }

  Future<void> publish() async {
    final current = binding;
    if (current == null) return;
    final hash = await channel.invokeMethod<String>('write', current);
    if (hash != current['hash'] || _needsPersistence) {
      await remember({...current, 'hash': hash});
    }
  }

  Future<void> checkBeforeSwitch() async {
    if (binding != null &&
        await channel.invokeMethod<bool>('pending', binding) == true) {
      await publish();
    }
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
}
