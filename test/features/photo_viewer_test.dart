import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/core/clock.dart';
import 'package:tickwalk/data/db/app_database.dart'
    hide Inspection, Template, InspectionItem, Attachment;
import 'package:tickwalk/data/repositories/attachment_repository.dart';
import 'package:tickwalk/data/repositories/inspection_repository.dart';
import 'package:tickwalk/data/repositories/template_repository.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/domain/template_schema.dart';
import 'package:tickwalk/features/checklist/photo_viewer_screen.dart';
import 'package:tickwalk/ui/theme.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late TemplateRepository templateRepo;
  late InspectionRepository inspectionRepo;
  late AttachmentRepository attachmentRepo;
  late Inspection testInspection;
  late InspectionItem testItem;
  late Attachment testAttachment;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.memory();
    clock = FakeClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
    templateRepo = TemplateRepository(db, clock);
    inspectionRepo = InspectionRepository(db, clock);
    attachmentRepo = AttachmentRepository(db, clock);

    tempDir = await Directory.systemTemp.createTemp('tickwalk_viewer_test_');
    final dummyPhoto = File('${tempDir.path}/photo.jpg');
    await dummyPhoto.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

    final dummyThumb = File('${tempDir.path}/photo_t.jpg');
    await dummyThumb.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

    final tpl = (await templateRepo.createTemplate(
      name: 'Safety Check',
      structure: const TemplateStructure(
        schemaVersion: 1,
        sections: [
          TemplateSectionDefinition(
            id: 'sec1',
            title: 'General',
            items: [
              TemplateItemDefinition(
                id: 'item1',
                prompt: 'Fire alarm operational',
                type: ItemType.passFail,
              ),
            ],
          ),
        ],
      ),
    )).valueOrNull!;

    testInspection = (await inspectionRepo.startInspection(
      templateId: tpl.id,
      siteName: 'Dock Warehouse',
      inspectorName: 'Inspector Alex',
    )).valueOrNull!;

    final items = await (db.select(db.inspectionItems)
          ..where((t) => t.inspectionId.equals(testInspection.id)))
        .get();
    testItem = InspectionItem(
      id: items.first.id,
      inspectionId: testInspection.id,
      sectionTitle: 'General',
      sectionOrder: 0,
      itemOrder: 0,
      prompt: 'Fire alarm operational',
      itemType: ItemType.passFail,
      required: false,
      photoRequiredOnFail: false,
      createdAt: clock.nowMillis(),
      updatedAt: clock.nowMillis(),
    );

    testAttachment = (await attachmentRepo.insertPhotoAttachment(
      id: 'att_123',
      inspectionId: testInspection.id,
      itemId: testItem.id,
      localPath: dummyPhoto.path,
      thumbPath: dummyThumb.path,
      sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      bytes: 2048,
      width: 1600,
      height: 1200,
      compressionProfile: 'standard',
      capturedAt: clock.nowMillis(),
      gpsLat: 37.774929,
      gpsLng: -122.419416,
      gpsAccuracyM: 4.8,
      gpsStatus: GpsFixStatus.fix,
      caption: 'Initial defect photo',
    )).valueOrNull!;
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildTestViewer({
    required String inspectionId,
    required String attachmentId,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: PhotoViewerScreen(
          inspectionId: inspectionId,
          attachmentId: attachmentId,
        ),
      ),
    );
  }

  group('Photo Viewer Screen (T16)', () {
    testWidgets('Renders image, metadata panel, GPS accuracy, hash, and caption',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestViewer(
          inspectionId: testInspection.id,
          attachmentId: testAttachment.id,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Evidence Photo'), findsOneWidget);
      expect(find.text('Initial defect photo'), findsOneWidget);

      // Metadata panel checks
      expect(find.text('Captured: '), findsOneWidget);
      expect(find.text('GPS Location: '), findsOneWidget);
      expect(find.textContaining('37.774929, -122.419416 (±4.8 m)'), findsOneWidget);
      expect(find.textContaining('2.0 KB (1600x1200)'), findsOneWidget);
      expect(find.textContaining('e3b0c44298fc1c14...'), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Updates caption when submitted in text field', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestViewer(
          inspectionId: testInspection.id,
          attachmentId: testAttachment.id,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final captionField = find.byType(TextField);
      expect(captionField, findsOneWidget);

      await tester.enterText(captionField, 'Updated cracked glass caption');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify DB was updated
      final updatedAtt =
          (await attachmentRepo.getAttachment(testAttachment.id)).valueOrNull!;
      expect(updatedAtt.caption, equals('Updated cracked glass caption'));

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Deletes photo with confirmation and restores on Undo toast',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(clock),
          ],
          child: MaterialApp(
            theme: buildLightTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PhotoViewerScreen(
                          inspectionId: testInspection.id,
                          attachmentId: testAttachment.id,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Viewer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open Viewer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Delete icon in app bar
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dialog appears
      expect(find.text('Delete Photo?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      // Allow dialog to dismiss and SnackBar entrance animation to complete
      await tester.pump(const Duration(milliseconds: 500));

      // Photo should be marked deleted in DB
      final deletedAtt = await attachmentRepo.getAttachment(testAttachment.id);
      expect(deletedAtt.isErr, isTrue); // Not found because deletedAt is set

      // SnackBar with Undo appears on the remaining Scaffold
      expect(find.text('Photo deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Tap Undo
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Photo is restored in DB
      final restoredAtt =
          (await attachmentRepo.getAttachment(testAttachment.id)).valueOrNull!;
      expect(restoredAtt.deletedAt, isNull);

      // Clean unmount & drain snackbar timers
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Completed inspection hides delete button and disables caption editing',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Complete inspection
      await inspectionRepo.completeInspection(testInspection.id);

      await tester.pumpWidget(
        buildTestViewer(
          inspectionId: testInspection.id,
          attachmentId: testAttachment.id,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Delete icon is not present
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      // Caption field is disabled
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
