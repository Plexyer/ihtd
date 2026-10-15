import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'update_contract.dart';

enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  verifying,
  ready,
  error,
}

/// Product policy and UI state are identical on every platform. Native services
/// own downloads/verification/installation, never document-save decisions.
class UpdateCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  UpdateCoordinator({
    required this.source,
    required this.platform,
    required this.stateFile,
    this.automatic = true,
  }) {
    WidgetsBinding.instance.addObserver(this);
    ready = initialize();
  }
  final ReleaseSource source;
  final UpdatePlatform platform;
  final Future<File> Function() stateFile;
  bool automatic;
  late final Future<void> ready;
  UpdatePhase phase = UpdatePhase.idle;
  InstalledApp? installed;
  UpdateCandidate? candidate;
  String? message;
  double? progress;
  DateTime? _lastCheck;
  Timer? _timer;
  bool _disposed = false, _observing = false, _operation = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _writeTail = Future.value();
  Future<void> _persist() {
    final next = _writeTail.then((_) => _writeState());
    _writeTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeState() async {
    final file = await stateFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'automatic': automatic,
        'lastCheck': _lastCheck?.toUtc().toIso8601String(),
        'candidate': candidate?.toJson(),
        'download':
            phase == UpdatePhase.downloading ||
            phase == UpdatePhase.verifying ||
            phase == UpdatePhase.ready,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<void> initialize() async {
    try {
      installed = await platform.identity();
      final file = await stateFile();
      if (await file.exists() && await file.length() < 65536) {
        try {
          final data = jsonDecode(await file.readAsString()) as Map;
          automatic = data['automatic'] != false;
          _lastCheck = DateTime.tryParse('${data['lastCheck']}');
          if (data['candidate'] is Map) {
            final saved = UpdateCandidate.fromJson(
              Map<String, dynamic>.from(data['candidate'] as Map),
            );
            if (saved.newerThan(installed!)) {
              candidate = saved;
              phase = UpdatePhase.available;
              if (data['download'] == true && platform.canInstall) {
                phase = UpdatePhase.downloading;
                await poll();
                _watchDownload();
              }
            } else {
              await platform.cancel();
              await _persist();
            }
          }
        } on FormatException {
          message = 'Cached update information was invalid. Check again.';
        } on UpdateFailure {
          message = 'Cached update information was invalid. Check again.';
        }
      }
      if (phase != UpdatePhase.downloading &&
          phase != UpdatePhase.ready &&
          phase != UpdatePhase.error) {
        await check(manual: false);
      }
    } catch (_) {
      message =
          'Update services are unavailable. You can keep working offline.';
    }
    notifyListeners();
  }

  Future<void> setAutomatic(bool enabled) async {
    automatic = enabled;
    try {
      await _persist();
    } catch (_) {
      message = 'Could not retain the update preference.';
    }
    notifyListeners();
  }

  Future<void> check({bool manual = true}) async {
    if (_operation ||
        phase == UpdatePhase.downloading ||
        phase == UpdatePhase.verifying ||
        phase == UpdatePhase.ready) {
      return;
    }
    if (!manual &&
        (!automatic ||
            (_lastCheck != null &&
                DateTime.now().difference(_lastCheck!) <
                    const Duration(hours: 24)))) {
      return;
    }
    _operation = true;
    phase = UpdatePhase.checking;
    message = null;
    notifyListeners();
    try {
      installed ??= await platform.identity();
      _lastCheck = DateTime.now();
      final found = await source.latest(installed!);
      candidate = found;
      phase = found == null ? UpdatePhase.idle : UpdatePhase.available;
      message = found == null
          ? 'No newer compatible stable release is available.'
          : null;
      await _persist();
    } catch (e) {
      phase = candidate == null ? UpdatePhase.idle : UpdatePhase.available;
      message = updateError(e);
      // Retain daily backoff even on network/rate-limit failure.
      try {
        await _persist();
      } catch (_) {
        /* Report original failure. */
      }
    } finally {
      _operation = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    if (_operation ||
        candidate == null ||
        !platform.canInstall ||
        phase == UpdatePhase.downloading) {
      return;
    }
    _operation = true;
    try {
      phase = UpdatePhase.downloading;
      message = null;
      progress = null;
      await _persist(); // Persist user intent before starting native work.
      await platform.start(candidate!);
      _watchDownload();
    } catch (e) {
      phase = UpdatePhase.error;
      message = updateError(e);
    } finally {
      _operation = false;
      notifyListeners();
    }
  }

  void _watchDownload() {
    _timer?.cancel();
    if (phase == UpdatePhase.downloading) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
    }
  }

  Future<void> poll() async {
    if (_observing ||
        _disposed ||
        phase != UpdatePhase.downloading ||
        candidate == null) {
      return;
    }
    _observing = true;
    try {
      final observation = await platform.observe();
      progress = observation.total > 0
          ? (observation.bytes / observation.total).clamp(0, 1)
          : null;
      if (observation.state == 'complete') {
        phase = UpdatePhase.verifying;
        notifyListeners();
        await platform.verify(candidate!);
        phase = UpdatePhase.ready;
        await _persist();
        _timer?.cancel();
      } else if (observation.state == 'failed' ||
          observation.state == 'missing') {
        throw const UpdateFailure('download_failed');
      }
    } catch (e) {
      phase = UpdatePhase.error;
      message = updateError(e);
      _timer?.cancel();
      // Invalid package never becomes installable. Retry starts a fresh download.
      await platform.cancel();
    } finally {
      _observing = false;
      notifyListeners();
    }
  }

  Future<void> install(Future<bool> Function() prepare) async {
    if (_operation || phase != UpdatePhase.ready || candidate == null) return;
    _operation = true;
    try {
      if (!await prepare()) {
        message = 'Finish valid edits and ensure local recovery is saved before updating.';
        return;
      }
      phase = UpdatePhase.verifying;
      notifyListeners();
      await platform.verify(candidate!); // Never trust cached verification.
      final result = await platform.install(candidate!);
      phase = UpdatePhase.ready;
      message = result == 'permission'
          ? 'Allow IHTD to install updates in Android settings, then tap the green tick again.'
          : 'Complete the update in the system installer. Reopen IHTD afterward if needed.';
    } catch (e) {
      phase = UpdatePhase.error;
      message = updateError(e);
    } finally {
      _operation = false;
      notifyListeners();
    }
  }

  Future<void> openRelease() async {
    try {
      if (candidate != null) await platform.openRelease(candidate!);
    } catch (_) {
      message = 'Could not open the release page.';
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (phase == UpdatePhase.downloading) {
        poll();
      } else {
        check(manual: false);
      }
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

String updateError(Object error) => switch (error is UpdateFailure
    ? error.code
    : 'unknown') {
  'feed_unavailable' =>
    'Public releases are unavailable. The repository may still be private.',
  'rate_limited' => 'GitHub is limiting update checks. Try again later.',
  'offline' || 'network' =>
    'Could not reach GitHub. You can keep working offline and try again later.',
  'unsupported_device' =>
    'This release has no compatible package for this device.',
  'invalid_metadata' || 'incomplete_release' || 'invalid_redirect' =>
    'The release information could not be verified. No update was installed.',
  'verification' =>
    'Package verification failed. No update was installed. Download again.',
  'download_failed' =>
    'Download failed or was interrupted. Tap Retry to download again.',
  _ => 'The update could not be completed. Your collections are unchanged. Try again.',
};
