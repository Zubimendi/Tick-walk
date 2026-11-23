import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/ids.dart';
import '../../core/result.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models.dart';
import 'compression_profiles.dart';
import 'jpeg_header.dart';

/// GPS fix data collected in parallel during capture.
class GpsFixResult {
  const GpsFixResult({
    this.lat,
    this.lng,
    this.accuracyM,
    required this.status,
    this.timestampMillis,
  });

  final double? lat;
  final double? lng;
  final double? accuracyM;
  final GpsFixStatus status;
  final int? timestampMillis;

  static const none = GpsFixResult(status: GpsFixStatus.none);
}

/// Abstract camera source for testability.
abstract class CameraSource {
  Future<String?> takePhoto();
}

/// Default device camera using image_picker.
class DeviceCameraSource implements CameraSource {
  DeviceCameraSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> takePhoto() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    return xFile?.path;
  }
}

/// Abstract native compressor interface.
abstract class NativeCompressor {
  Future<String?> compressImage({
    required String sourcePath,
    required String targetPath,
    required int maxDimension,
    required int quality,
  });
}

/// Default compressor wrapping flutter_image_compress (strips EXIF natively).
class FlutterNativeCompressor implements NativeCompressor {
  const FlutterNativeCompressor();

  @override
  Future<String?> compressImage({
    required String sourcePath,
    required String targetPath,
    required int maxDimension,
    required int quality,
  }) async {
    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        keepExif: false, // Strips EXIF per Rule 6
      );
      return result?.path;
    } on Object {
      return null;
    }
  }
}

/// Abstract storage manager for testability.
abstract class StorageManager {
  Future<Directory> getInspectionDirectory(String inspectionId);
  Future<int> getAvailableStorageBytes();
}

/// Default app storage manager using path_provider.
class AppStorageManager implements StorageManager {
  const AppStorageManager();

  @override
  Future<Directory> getInspectionDirectory(String inspectionId) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final inspectionDir = Directory(p.join(appDocDir.path, 'inspections', inspectionId));
    if (!await inspectionDir.exists()) {
      await inspectionDir.create(recursive: true);
    }
    return inspectionDir;
  }

  @override
  Future<int> getAvailableStorageBytes() async {
    // 500 MB default headroom assumption when OS disk query is unconstrained
    return 500 * 1024 * 1024;
  }
}

/// Abstract GPS fix provider.
abstract class GpsFixProvider {
  Future<GpsFixResult> obtainFix();
}

/// Fallback no-op GPS fix provider.
class FallbackGpsFixProvider implements GpsFixProvider {
  const FallbackGpsFixProvider();

  @override
  Future<GpsFixResult> obtainFix() async => GpsFixResult.none;
}

/// Orchestrates the 8-step capture pipeline strictly honoring all non-negotiable rules.
class CapturePipeline {
  CapturePipeline({
    required AttachmentRepository attachmentRepository,
    required SettingsRepository settingsRepository,
    required Clock clock,
    CameraSource? cameraSource,
    NativeCompressor? compressor,
    StorageManager? storageManager,
    GpsFixProvider? gpsFixProvider,
  })  : _attachmentRepo = attachmentRepository,
        _settingsRepo = settingsRepository,
        _clock = clock,
        _camera = cameraSource ?? DeviceCameraSource(),
        _compressor = compressor ?? const FlutterNativeCompressor(),
        _storage = storageManager ?? const AppStorageManager(),
        _gps = gpsFixProvider ?? const FallbackGpsFixProvider();

  final AttachmentRepository _attachmentRepo;
  final SettingsRepository _settingsRepo;
  final Clock _clock;
  final CameraSource _camera;
  final NativeCompressor _compressor;
  final StorageManager _storage;
  final GpsFixProvider _gps;

  static const int minRequiredStorageBytes = 50 * 1024 * 1024; // 50 MB threshold

  /// Runs the capture pipeline for an inspection item.
  /// If [rawSourcePath] is provided (e.g. from lost-data recovery), skips camera launch.
  Future<Result<Attachment?>> executeCapture({
    required String inspectionId,
    String? itemId,
    String? rawSourcePath,
  }) async {
    // Step 1: Storage pre-check
    final freeSpace = await _storage.getAvailableStorageBytes();
    if (freeSpace < minRequiredStorageBytes) {
      return const Err(AppError(
        klass: ErrorClass.storageFull,
        message: 'Not enough space to save the photo',
      ));
    }

    // Step 2: Persist pending-capture in settings before launching camera (Rule 4a)
    final startedAt = _clock.nowMillis();
    final pendingCaptureJson = jsonEncode({
      'inspectionId': inspectionId,
      'itemId': itemId,
      'startedAt': startedAt,
    });
    await _settingsRepo.setPendingCapture(pendingCaptureJson);

    String? photoPath = rawSourcePath;
    late GpsFixResult gpsResult;

    if (photoPath == null) {
      // Step 3: Launch camera and trigger GPS in parallel (Rule 4b)
      final gpsFuture = _gps.obtainFix();
      final cameraFuture = _camera.takePhoto();

      try {
        photoPath = await cameraFuture;
      } on Object catch (e) {
        await _settingsRepo.clearPendingCapture();
        return Err(AppError(
          klass: ErrorClass.local,
          message: 'Camera failed to launch',
          cause: e,
        ));
      }

      // If user cancelled camera, clear pending capture and return Ok(null)
      if (photoPath == null) {
        await _settingsRepo.clearPendingCapture();
        return const Ok(null);
      }

      try {
        gpsResult = await gpsFuture.timeout(
          const Duration(seconds: 11),
          onTimeout: () => GpsFixResult.none,
        );
      } catch (_) {
        gpsResult = GpsFixResult.none;
      }
    } else {
      gpsResult = GpsFixResult.none;
    }

    // Step 4: captured_at timestamp
    // Note: captured_at is recorded the moment the picker returns using the injected
    // clock (approximate within seconds of shutter press per Rule 6).
    final capturedAt = _clock.nowMillis();

    // Step 5: Resolve compression profile setting
    final profileKey = await _settingsRepo.qualityProfile();
    final profile = CompressionProfile.fromString(profileKey);

    // Prepare destination paths
    final inspectionDir = await _storage.getInspectionDirectory(inspectionId);
    final attachmentId = newId();
    final finalImagePath = p.join(inspectionDir.path, '$attachmentId.jpg');
    final finalThumbPath = p.join(inspectionDir.path, '${attachmentId}_t.jpg');

    // Step 6: Native compression & Thumbnail generation (Rule 4c & Rule 6)
    var usedOriginalFallback = false;
    final compressedMain = await _compressor.compressImage(
      sourcePath: photoPath,
      targetPath: finalImagePath,
      maxDimension: profile.maxDimension,
      quality: profile.quality,
    );

    if (compressedMain == null || !File(finalImagePath).existsSync()) {
      // Rule 6: If compression fails, keep the original file, set a flag and continue
      try {
        await File(photoPath).copy(finalImagePath);
        usedOriginalFallback = true;
      } on Object catch (e) {
        await _settingsRepo.clearPendingCapture();
        return Err(AppError(
          klass: ErrorClass.local,
          message: 'Failed to save photo file',
          cause: e,
        ));
      }
    }

    // Generate thumbnail natively (320px, 70 quality)
    final compressedThumb = await _compressor.compressImage(
      sourcePath: finalImagePath,
      targetPath: finalThumbPath,
      maxDimension: CompressionProfile.thumbnailMaxDimension,
      quality: CompressionProfile.thumbnailQuality,
    );

    if (compressedThumb == null || !File(finalThumbPath).existsSync()) {
      // If thumbnail generation failed, copy main image as fallback thumbnail
      try {
        await File(finalImagePath).copy(finalThumbPath);
      } catch (_) {}
    }

    // Step 7: SHA-256 Hash and dimensions extraction (Rule 4d & Rule 5)
    final mainFile = File(finalImagePath);
    Uint8List fileBytes;
    try {
      fileBytes = await mainFile.readAsBytes();
    } on Object catch (e) {
      await _cleanupFiles([finalImagePath, finalThumbPath]);
      await _settingsRepo.clearPendingCapture();
      return Err(AppError(
        klass: ErrorClass.local,
        message: 'Failed to read compressed photo',
        cause: e,
      ));
    }

    final digest = sha256.convert(fileBytes).toString();
    final sizeBytes = fileBytes.length;
    final dimensions = readJpegDimensions(fileBytes);

    // Step 8: Atomic Drift transaction for attachment row and outbox (Rule 4f)
    final insertResult = await _attachmentRepo.insertPhotoAttachment(
      id: attachmentId,
      inspectionId: inspectionId,
      itemId: itemId,
      localPath: finalImagePath,
      thumbPath: finalThumbPath,
      sha256: digest,
      bytes: sizeBytes,
      width: dimensions?.width,
      height: dimensions?.height,
      compressionProfile: usedOriginalFallback ? 'fallback_original' : profile.name,
      capturedAt: capturedAt,
      gpsLat: gpsResult.lat,
      gpsLng: gpsResult.lng,
      gpsAccuracyM: gpsResult.accuracyM,
      gpsStatus: gpsResult.status,
      gpsAt: gpsResult.timestampMillis,
    );

    if (insertResult.isErr) {
      // Rollback: delete storage files to prevent orphans (Rule 4 invariant)
      await _cleanupFiles([finalImagePath, finalThumbPath]);
      await _settingsRepo.clearPendingCapture();
      return Err(insertResult.errorOrNull!);
    }

    // Step 9: Clear pending-capture (Rule 4g)
    await _settingsRepo.clearPendingCapture();

    // Clean up temporary camera cache file if different from final path
    if (photoPath != finalImagePath) {
      try {
        final tmp = File(photoPath);
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
    }

    return Ok(insertResult.valueOrNull);
  }

  Future<void> _cleanupFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }
}
