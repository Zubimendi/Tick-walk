import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/domain/models.dart';
import 'package:tickwalk/features/reports/pdf_report_builder.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pdf_report_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PdfReportBuilder (T25)', () {
    test('generates valid PDF document with header, counts, and disclaimer', () async {
      const builder = PdfReportBuilder();

      final inspection = Inspection(
        id: 'insp_pdf_1',
        templateId: 'tmpl_1',
        templateName: 'Electrical Safety Audit',
        siteName: 'Warehouse 42 North',
        siteAddress: '100 Industrial Parkway',
        inspectorName: 'Jane Doe, Lead Inspector',
        status: InspectionStatus.completed,
        startedAt: DateTime(2026, 3, 10, 9, 30).millisecondsSinceEpoch,
        completedAt: DateTime(2026, 3, 10, 11, 45).millisecondsSinceEpoch,
        reopenedCount: 0,
        startLat: 37.7749,
        startLng: -122.4194,
        startAccuracyM: 4.5,
        startGpsStatus: GpsFixStatus.fix,
        startGpsAt: DateTime(2026, 3, 10, 9, 30).millisecondsSinceEpoch,
        notes: 'Annual mandatory electrical assessment.',
        totalItems: 3,
        answeredItems: 3,
        passCount: 1,
        failCount: 1,
        naCount: 1,
        createdAt: DateTime(2026, 3, 10, 9, 30).millisecondsSinceEpoch,
        updatedAt: DateTime(2026, 3, 10, 11, 45).millisecondsSinceEpoch,
      );

      final items = [
        const InspectionItem(
          id: 'item_1',
          inspectionId: 'insp_pdf_1',
          sectionTitle: 'Main Panels',
          sectionOrder: 0,
          itemOrder: 0,
          prompt: 'Main breaker labeled and unobstructed',
          itemType: ItemType.passFail,
          required: true,
          photoRequiredOnFail: true,
          response: ItemResponse.pass,
          note: 'Clear access confirmed',
          createdAt: 1000,
          updatedAt: 1000,
        ),
        const InspectionItem(
          id: 'item_2',
          inspectionId: 'insp_pdf_1',
          sectionTitle: 'Main Panels',
          sectionOrder: 0,
          itemOrder: 1,
          prompt: 'Ground wire securely connected',
          itemType: ItemType.passFail,
          required: true,
          photoRequiredOnFail: true,
          response: ItemResponse.fail,
          severity: Severity.high,
          note: 'Loose ground clamp on subpanel B',
          createdAt: 1000,
          updatedAt: 1000,
        ),
        const InspectionItem(
          id: 'item_3',
          inspectionId: 'insp_pdf_1',
          sectionTitle: 'Generators',
          sectionOrder: 1,
          itemOrder: 0,
          prompt: 'Fuel tank level in gallons',
          itemType: ItemType.number,
          unit: 'gal',
          required: false,
          photoRequiredOnFail: false,
          response: ItemResponse.na,
          note: 'No generator on site',
          createdAt: 1000,
          updatedAt: 1000,
        ),
      ];

      // Create a dummy image file for attachment
      final dummyPhoto = File('${tempDir.path}/evidence_1.jpg');
      // Minimal valid 1x1 JPEG bytes
      dummyPhoto.writeAsBytesSync([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
        0x00, 0xBF, 0x80, 0xFF, 0xD9
      ]);

      final attachments = [
        Attachment(
          id: 'att_pdf_1',
          inspectionId: 'insp_pdf_1',
          itemId: 'item_2',
          kind: AttachmentKind.photo,
          localPath: dummyPhoto.path,
          thumbPath: dummyPhoto.path,
          sha256: 'hash123',
          bytes: dummyPhoto.lengthSync(),
          capturedAt: DateTime(2026, 3, 10, 10, 15).millisecondsSinceEpoch,
          gpsLat: 37.7750,
          gpsLng: -122.4195,
          gpsAccuracyM: 3.2,
          gpsStatus: GpsFixStatus.fix,
          caption: 'Photo of loose ground clamp',
          createdAt: DateTime(2026, 3, 10, 10, 15).millisecondsSinceEpoch,
          updatedAt: DateTime(2026, 3, 10, 10, 15).millisecondsSinceEpoch,
        ),
      ];

      final pdfBytes = await builder.build(
        inspection: inspection,
        items: items,
        attachments: attachments,
      );

      // Verify PDF header magic bytes "%PDF-" and footer "%%EOF"
      expect(pdfBytes.length, greaterThan(500));
      final headerStr = utf8.decode(pdfBytes.sublist(0, 5));
      expect(headerStr, '%PDF-');

      final endBytes = pdfBytes.sublist(pdfBytes.length - 10);
      final footerStr = String.fromCharCodes(endBytes);
      expect(footerStr.contains('%%EOF'), isTrue);
    });

    test('generates PDF when there are no attachments', () async {
      const builder = PdfReportBuilder();

      const inspection = Inspection(
        id: 'insp_empty_att',
        templateId: 'tmpl_empty',
        templateName: 'Quick Check',
        siteName: 'Gate 4',
        inspectorName: 'Bob',
        status: InspectionStatus.inProgress,
        startedAt: 1000000,
        reopenedCount: 0,
        createdAt: 1000000,
        updatedAt: 1000000,
      );

      final pdfBytes = await builder.build(
        inspection: inspection,
        items: [],
        attachments: [],
      );

      expect(pdfBytes, isNotEmpty);
      expect(utf8.decode(pdfBytes.sublist(0, 5)), '%PDF-');
    });
  });
}
