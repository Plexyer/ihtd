import 'dart:convert';
import 'dart:io';

/// Only allowlisted values enter the log. Raw exceptions/commands never do.
class DocumentDiagnostics {
  static const codes = {
    'checking',
    'connected',
    'renamed',
    'unavailable',
    'external_changed',
    'save_failed',
    'local_failed',
    'reconnect_required',
    'publish_started',
    'publish_verified',
    'connection_confirmed',
    'session_archived',
    'write_failed',
    'verification_failed',
  };
  final String run = DateTime.now().toUtc().toIso8601String();
  final Map<String, String> _references = {};
  String _reference = 'none';
  void useDocument(String privateKey) {
    _reference = _references.putIfAbsent(
      privateKey,
      () => 'copy-${_references.length + 1}',
    );
  }

  final List<Map<String, Object?>> events = [];
  Map<String, dynamic> environment = {};
  File? file;
  Future<void> _writes = Future.value();

  Future<void> initialize(Directory directory) async {
    file = File('${directory.path}/diagnostics.json');
    try {
      if (await file!.exists()) {
        final stored = jsonDecode(await file!.readAsString()) as List;
        for (final event in stored.whereType<Map>()) {
          if (codes.contains(event['code'])) {
            events.add({
              'time': DateTime.tryParse('${event['time']}')
                  ?.toUtc()
                  .toIso8601String(),
              'code': event['code'],
              'pending': event['pending'] == true,
              'run': DateTime.tryParse('${event['run']}')
                  ?.toUtc()
                  .toIso8601String(),
              'document':
                  RegExp(r'^(none|copy-[0-9]+)$')
                      .hasMatch('${event['document']}')
                  ? event['document']
                  : 'none',
            });
          }
        }
        if (events.length > 120) events.removeRange(0, events.length - 120);
      }
    } catch (_) {}
  }

  void record(String code, bool pending) {
    if (!codes.contains(code)) return;
    if (events.isNotEmpty &&
        events.last['code'] == code &&
        events.last['pending'] == pending &&
        events.last['document'] == _reference) {
      return;
    }
    events.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'code': code,
      'pending': pending,
      'run': run,
      'document': _reference,
    });
    if (events.length > 120) events.removeAt(0);
    final bytes = jsonEncode(events);
    _writes = _writes.then((_) async {
      try {
        if (file != null) {
          final temp = File('${file!.path}.tmp');
          await temp.writeAsString(bytes, flush: true);
          await temp.rename(file!.path);
        }
      } catch (_) {}
    });
  }

  Future<void> flush() => _writes;

  String export({
    required String state,
    required bool pending,
    Map<String, dynamic>? recovery,
    Map<String, dynamic>? extended,
  }) {
    final safeEnvironment = <String, dynamic>{};
    for (final key in ['appVersion', 'build', 'androidApi', 'androidVersion']) {
      final value = environment[key];
      if (value != null &&
          RegExp(r'^[0-9.A-Za-z+_-]{1,40}$').hasMatch('$value')) {
        safeEnvironment[key] = value;
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'formatVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'environment': safeEnvironment,
      'state': state,
      'pending': pending,
      'recovery': ?recovery,
      'events': events,
      'additionalInformation': ?extended,
    });
  }
}
