import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/capture/capture_pipeline.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/core/errors.dart';
import 'package:tickwalk/data/db/app_database.dart';
import 'package:tickwalk/data/repositories/attachment_repository.dart';
import 'package:tickwalk/data/repositories/inspection_repository.dart';
import 'package:tickwalk/data/repositories/settings_repository.dart';
import 'package:tickwalk/data/repositories/template_repository.dart';
import 'package:tickwalk/domain/models.dart' as domain;
import 'package:tickwalk/domain/template_schema.dart';

class FakeCameraSource implements CameraSource {
  FakeCameraSource({this.photoPathToReturn});

  String? photoPathToReturn;
  bool wasLaunched = false;

  @override
  Future<String?> takePhoto() async {
    wasLaunched = true;
    return photoPathToReturn;
  }
}

class FakeNativeCompressor implements NativeCompressor {
  FakeNativeCompressor({this.shouldFail = false});

  bool shouldFail;
  int compressCalls = 0;

  @override
  Future<String?> compressImage({
    required String sourcePath,
    required String targetPath,
    required int maxDimension,
    required int quality,
  }) async {
    compressCalls++;
    if (shouldFail) return null;

    final targetFile = File(targetPath);
    await targetFile.writeAsBytes([
      0xFF, 0xD8, // SOI
      0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x04, 0xB0, 0x06, 0x40, 0x03, 0x01, 0x11, 0x00, // SOF0
      0xFF, 0xD9, // EOI
    ]);
    return targetPath;
  }
}

class FakeStorageManager implements StorageManager {
  FakeStorageManager({
    required this.tempDir,
    this.availableBytes = 100 * 1024 * 1024,
  });

  final Directory tempDir;
  int availableBytes;

  @override
  Future<Directory> getInspectionDirectory(String inspectionId) async {
    final dir = Directory('${tempDir.path}/inspections/$inspectionId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<int> getAvailableStorageBytes() async => availableBytes;
}

class FakeGpsFixProvider implements GpsFixProvider {
  FakeGpsFixProvider({this.result = GpsFixResult.none});

  GpsFixResult result;

  @override
  Future<GpsFixResult> obtainFix() async => result;
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late SettingsRepository settingsRepo;
  late AttachmentRepository attachmentRepo;
  late InspectionRepository inspectionRepo;
  late TemplateRepository templateRepo;
  late Directory testDir;
  late domain.Inspection testInspection;

  setUp(() async {
    db = AppDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
    settingsRepo = SettingsRepository(db);
    attachmentRepo = AttachmentRepository(db, clock);
    templateRepo = TemplateRepository(db, clock);
    inspectionRepo = InspectionRepository(db, clock);

    testDir = await Directory.systemTemp.createTemp('tickwalk_capture_test_');

    final tpl = (await templateRepo.createTemplate(
      name: 'Test Template',
      structure: const TemplateStructure(
        schemaVersion: 1,
        sections: [
          TemplateSectionDefinition(
            id: 'sec1',
            title: 'General',
            items: [
              TemplateItemDefinition(
                id: 'item1',
                prompt: 'Item 1',
                type: domain.ItemType.passFail,
              ),
            ],
          ),
        ],
      ),
    )).valueOrNull!;

    testInspection = (await inspectionRepo.startInspection(
      templateId: tpl.id,
      siteName: 'Site A',
      inspectorName: 'Inspector Bob',
    )).valueOrNull!;
  });

  tearDown(() async {
    await db.close();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('Capture Pipeline (T13)', () {
    test('Storage precheck fails when disk space is below 50MB threshold', () async {
      final camera = FakeCameraSource();
      final storage = FakeStorageManager(
        tempDir: testDir,
        availableBytes: 10 * 1024 * 1024, // 10MB < 50MB
      );

      final pipeline = CapturePipeline(
        attachmentRepository: attachmentRepo,
        settingsRepository: settingsRepo,
        clock: clock,
        cameraSource: camera,
        storageManager: storage,
      );

      final result = await pipeline.executeCapture(
        inspectionId: testInspection.id,
        itemId: 'item1',
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.klass, equals(ErrorClass.storageFull));
      expect(result.errorOrNull!.message, contains('Not enough space'));
      expect(camera.wasLaunched, isFalse);
    });

    test('Camera cancel cleanly clears pending-capture and returns Ok(null)', () async {
      final camera = FakeCameraSource(photoPathToReturn: null);
      final storage = FakeStorageManager(tempDir: testDir);

      final pipeline = CapturePipeline(
        attachmentRepository: attachmentRepo,
        settingsRepository: settingsRepo,
        clock: clock,
        cameraSource: camera,
        storageManager: storage,
      );

      final result = await pipeline.executeCapture(
        inspectionId: testInspection.id,
        itemId: 'item1',
      );

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);

      // Pending capture was cleared
      final pending = await settingsRepo.pendingCapture();
      expect(pending, isNull);

      // No DB rows inserted
      final attachments = await (db.select(db.attachments)).get();
      expect(attachments, isEmpty);
    });

    test('Successful capture compresses, hashes, moves files, creates DB row, and clears pending-capture', () async {
      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(testInspection.id))).get();
      final actualItemId = items.first.id;

      // Create mock raw camera file
      final rawPhoto = File('${testDir.path}/raw_camera.jpg');
      await rawPhoto.writeAsBytes([0x01, 0x02, 0x03, 0x04]);

      final camera = FakeCameraSource(photoPathToReturn: rawPhoto.path);
      final compressor = FakeNativeCompressor();
      final storage = FakeStorageManager(tempDir: testDir);
      final gps = FakeGpsFixProvider(
        result: const GpsFixResult(
          lat: 37.7749,
          lng: -122.4194,
          accuracyM: 6.5,
          status: domain.GpsFixStatus.fix,
          timestampMillis: 1700000000000,
        ),
      );

      final pipeline = CapturePipeline(
        attachmentRepository: attachmentRepo,
        settingsRepository: settingsRepo,
        clock: clock,
        cameraSource: camera,
        compressor: compressor,
        storageManager: storage,
        gpsFixProvider: gps,
      );

      final result = await pipeline.executeCapture(
        inspectionId: testInspection.id,
        itemId: actualItemId,
      );

      if (result.isErr) {
        fail('Capture failed: ${result.errorOrNull?.message} cause=${result.errorOrNull?.cause}');
      }

      expect(result.isOk, isTrue);
      final attachment = result.valueOrNull!;

      expect(attachment.inspectionId, equals(testInspection.id));
      expect(attachment.itemId, equals(actualItemId));
      expect(attachment.kind, equals(domain.AttachmentKind.photo));
      expect(attachment.gpsLat, equals(37.7749));
      expect(attachment.gpsLng, equals(-122.4194));
      expect(attachment.gpsAccuracyM, equals(6.5));
      expect(attachment.gpsStatus, equals(domain.GpsFixStatus.fix));

      // Files exist on disk
      expect(File(attachment.localPath!).existsSync(), isTrue);
      expect(File(attachment.thumbPath!).existsSync(), isTrue);

      // Dimensions extracted without full image decode
      expect(attachment.width, equals(1600));
      expect(attachment.height, equals(1200));

      // Pending capture is cleared
      expect(await settingsRepo.pendingCapture(), isNull);
    });

    test('Compression failure falls back to keeping original file per Rule 6', () async {
      final items = await (db.select(db.inspectionItems)..where((t) => t.inspectionId.equals(testInspection.id))).get();
      final actualItemId = items.first.id;

      final rawPhoto = File('${testDir.path}/raw_camera_fallback.jpg');
      await rawPhoto.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

      final camera = FakeCameraSource(photoPathToReturn: rawPhoto.path);
      final compressor = FakeNativeCompressor(shouldFail: true); // Fails
      final storage = FakeStorageManager(tempDir: testDir);

      final pipeline = CapturePipeline(
        attachmentRepository: attachmentRepo,
        settingsRepository: settingsRepo,
        clock: clock,
        cameraSource: camera,
        compressor: compressor,
        storageManager: storage,
      );

      final result = await pipeline.executeCapture(
        inspectionId: testInspection.id,
        itemId: actualItemId,
      );

      expect(result.isOk, isTrue);
      final attachment = result.valueOrNull!;
      expect(attachment.compressionProfile, equals('fallback_original'));
      expect(File(attachment.localPath!).existsSync(), isTrue);
    });

    test('Completed inspection rejects capture and prevents disk orphans', () async {
      await inspectionRepo.completeInspection(testInspection.id);

      final rawPhoto = File('${testDir.path}/raw_completed.jpg');
      await rawPhoto.writeAsBytes([0x01, 0x02, 0x03]);

      final camera = FakeCameraSource(photoPathToReturn: rawPhoto.path);
      final compressor = FakeNativeCompressor();
      final storage = FakeStorageManager(tempDir: testDir);

      final pipeline = CapturePipeline(
        attachmentRepository: attachmentRepo,
        settingsRepository: settingsRepo,
        clock: clock,
        cameraSource: camera,
        compressor: compressor,
        storageManager: storage,
      );

      final result = await pipeline.executeCapture(
        inspectionId: testInspection.id,
        itemId: 'item1',
      );

      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.klass, equals(ErrorClass.forbidden));

      // Invariant: no orphaned files created in destination directory
      final inspectionDir = await storage.getInspectionDirectory(testInspection.id);
      expect(inspectionDir.listSync(), isEmpty);
    });
  });
}
