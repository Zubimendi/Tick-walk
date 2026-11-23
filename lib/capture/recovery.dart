import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../core/clock.dart';
import '../../core/logger.dart';
import '../../data/repositories/settings_repository.dart';
import 'capture_pipeline.dart';

/// Maximum age of a pending-capture record to still attempt recovery (30 minutes).
const Duration pendingCaptureMaxAge = Duration(minutes: 30);

/// Encapsulates the decision of whether and how to recover a lost capture.
/// Pure domain logic: no Flutter or platform imports.
sealed class RecoveryDecision {
  const RecoveryDecision();
}

/// No pending capture in settings — nothing to recover.
class RecoveryNotRequired extends RecoveryDecision {
  const RecoveryNotRequired();
}

/// Pending capture is too old to safely recover (> 30 min).
class RecoveryExpired extends RecoveryDecision {
  const RecoveryExpired({required this.startedAt});

  final int startedAt;
}

/// Pending capture is recent and a file was returned — proceed with pipeline.
class RecoveryRequired extends RecoveryDecision {
  const RecoveryRequired({
    required this.inspectionId,
    required this.itemId,
    required this.lostFilePath,
    required this.startedAt,
  });

  final String inspectionId;
  final String? itemId;
  final String lostFilePath;
  final int startedAt;
}

/// Pure function: determines what recovery action to take given the pending-capture
/// settings value and the now-timestamp.
/// Never calls any platform API; testable without mocks.
RecoveryDecision evaluateRecovery({
  required String? pendingCaptureJson,
  required String? lostFilePath,
  required int nowMillis,
}) {
  if (pendingCaptureJson == null || pendingCaptureJson.isEmpty) {
    return const RecoveryNotRequired();
  }

  try {
    final map = jsonDecode(pendingCaptureJson) as Map<String, dynamic>;
    final inspectionId = map['inspectionId'] as String?;
    final itemId = map['itemId'] as String?;
    final startedAt = map['startedAt'] as int?;

    if (inspectionId == null || startedAt == null) {
      return const RecoveryNotRequired();
    }

    final ageMsecs = nowMillis - startedAt;
    if (ageMsecs > pendingCaptureMaxAge.inMilliseconds) {
      return RecoveryExpired(startedAt: startedAt);
    }

    if (lostFilePath == null || lostFilePath.isEmpty) {
      // Pending capture exists but OS returned no file — just clear the flag
      return const RecoveryNotRequired();
    }

    return RecoveryRequired(
      inspectionId: inspectionId,
      itemId: itemId,
      lostFilePath: lostFilePath,
      startedAt: startedAt,
    );
  } catch (_) {
    return const RecoveryNotRequired();
  }
}

/// Checks for lost camera data on app resume or boot and runs the capture
/// pipeline if a valid pending capture exists (Rule 4 / CURSOR_CONTEXT T15).
///
/// Must be called:
///   1. On first app frame after launch (from AppLifecycleListener / didChangeAppLifecycleState).
///   2. On resume from background (AppLifecycleState.resumed).
///
/// Note: retrieveLostData() is Android-only. On iOS the camera returns
/// immediately so there is no lost-data scenario; this method is a no-op on iOS.
class CaptureRecoveryService {
  CaptureRecoveryService({
    required SettingsRepository settingsRepository,
    required CapturePipeline capturePipeline,
    required Clock clock,
    ImagePicker? imagePicker,
    Logger? logger,
  })  : _settings = settingsRepository,
        _pipeline = capturePipeline,
        _clock = clock,
        _picker = imagePicker ?? ImagePicker(),
        _logger = logger ?? const NoOpLogger();

  final SettingsRepository _settings;
  final CapturePipeline _pipeline;
  final Clock _clock;
  final ImagePicker _picker;
  final Logger _logger;

  /// Attempts to recover lost-data from the previous camera session.
  /// Safe to call on every resume; it is idempotent.
  Future<void> tryRecoverLostCapture() async {
    // 1. Read pending-capture flag first
    final pendingJson = await _settings.pendingCapture();

    // 2. Ask image_picker if the OS has a file for us (Android-only)
    String? lostPath;
    try {
      final lostData = await _picker.retrieveLostData();
      if (!lostData.isEmpty && lostData.file != null) {
        lostPath = lostData.file!.path;
      }
    } on UnsupportedError {
      // iOS or other platforms that don't support retrieveLostData
      lostPath = null;
    } catch (e) {
      _logger.error('retrieveLostData failed', error: e);
      lostPath = null;
    }

    final nowMillis = _clock.nowMillis();
    final decision = evaluateRecovery(
      pendingCaptureJson: pendingJson,
      lostFilePath: lostPath,
      nowMillis: nowMillis,
    );

    switch (decision) {
      case RecoveryNotRequired():
        // Also clear any stale pending-capture flag if no lost data returned
        if (pendingJson != null && lostPath == null) {
          await _settings.clearPendingCapture();
          _logger.info('recover: stale cleared');
        }

      case RecoveryExpired():
        // Clear the expired flag and discard the file
        await _settings.clearPendingCapture();
        if (lostPath != null) {
          try {
            await File(lostPath).delete();
          } catch (_) {}
        }
        _logger.info('recover: expired');

      case RecoveryRequired(:final inspectionId, :final itemId, :final lostFilePath):
        _logger.info('recover: starting');

        final result = await _pipeline.executeCapture(
          inspectionId: inspectionId,
          itemId: itemId,
          rawSourcePath: lostFilePath,
        );

        if (result.isErr) {
          _logger.error('recover: failed', error: result.errorOrNull?.klass.name);
        } else {
          _logger.info('recover: ok');
        }
    }
  }
}
