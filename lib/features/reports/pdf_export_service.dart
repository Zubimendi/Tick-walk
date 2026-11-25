import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import 'pdf_report_builder.dart';

/// Service responsible for generating and sharing PDF inspection reports.
class PdfExportService {
  const PdfExportService({
    PdfReportBuilder reportBuilder = const PdfReportBuilder(),
  }) : _reportBuilder = reportBuilder;

  final PdfReportBuilder _reportBuilder;

  /// Generates the PDF report and shares it using the platform share sheet.
  Future<File> exportReport({
    required Inspection inspection,
    required List<InspectionItem> items,
    required List<Attachment> attachments,
  }) async {
    final bytes = await _reportBuilder.build(
      inspection: inspection,
      items: items,
      attachments: attachments,
    );

    final tempDir = await getTemporaryDirectory();
    final sanitizedSiteName = inspection.siteName
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final fileName = 'Tickwalk_${sanitizedSiteName}_${inspection.id.substring(0, 8)}.pdf';
    final file = File('${tempDir.path}/$fileName');

    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Exports the report and opens the system share sheet.
  Future<void> shareReport({
    required Inspection inspection,
    required List<InspectionItem> items,
    required List<Attachment> attachments,
  }) async {
    final file = await exportReport(
      inspection: inspection,
      items: items,
      attachments: attachments,
    );

    final xFile = XFile(
      file.path,
      mimeType: 'application/pdf',
      name: file.uri.pathSegments.last,
    );

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [xFile],
      subject: '${inspection.siteName} - Inspection Report',
      text: 'Inspection report for ${inspection.siteName} (${inspection.templateName})',
    );
  }
}
