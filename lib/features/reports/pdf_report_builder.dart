import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates.dart';
import '../../domain/models.dart';

/// Prominent evidence disclaimer mandated by Section 1 & Section 7.
const String evidenceHonestyDisclaimer =
    'Device timestamps and coordinates are unverified device records. '
    'Server receive time indicates cloud receipt.';

/// Builds a professional, standalone PDF report for an inspection.
class PdfReportBuilder {
  const PdfReportBuilder();

  /// Generates PDF byte array for an inspection, its items, and attachments.
  Future<Uint8List> build({
    required Inspection inspection,
    required List<InspectionItem> items,
    required List<Attachment> attachments,
  }) async {
    final pdf = pw.Document(
      title: '${inspection.siteName} - Inspection Report',
      author: inspection.inspectorName,
    );

    // Group items by section
    final sections = <String, List<InspectionItem>>{};
    for (final item in items) {
      sections.putIfAbsent(item.sectionTitle, () => []).add(item);
    }

    // Attachments lookup by itemId and standalone
    final attachmentsByItem = <String, List<Attachment>>{};
    final standaloneAttachments = <Attachment>[];
    for (final att in attachments) {
      if (att.itemId != null && att.itemId!.isNotEmpty) {
        attachmentsByItem.putIfAbsent(att.itemId!, () => []).add(att);
      } else {
        standaloneAttachments.add(att);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(inspection, context),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          // 1. Overview & Site Information
          _buildInspectionDetails(inspection),
          pw.SizedBox(height: 16),

          // 2. Summary Counts Card
          _buildSummaryCounts(inspection),
          pw.SizedBox(height: 20),

          // 3. Prominent Legal / Evidence Disclaimer (Section 7)
          _buildDisclaimerBanner(),
          pw.SizedBox(height: 20),

          // 4. Checklist Audit Table
          pw.Text(
            'Checklist Findings',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 8),

          for (final entry in sections.entries) ...[
            _buildSectionHeader(entry.key),
            _buildItemsTable(entry.value),
            pw.SizedBox(height: 12),
          ],

          pw.SizedBox(height: 16),

          // 5. Evidence Photo Gallery
          pw.Text(
            'Photo Evidence Gallery',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 8),
          if (attachments.isEmpty)
            pw.Paragraph(
              text: 'No photographic evidence was attached to this inspection.',
              style: const pw.TextStyle(color: PdfColors.grey700),
            )
          else
            _buildEvidenceGallery(attachments),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader(Inspection inspection, pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Tickwalk Inspection Report',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            inspection.siteName,
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      margin: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated via Tickwalk',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildInspectionDetails(Inspection inspection) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final startedStr = dateFormat.format(DateTime.fromMillisecondsSinceEpoch(inspection.startedAt));
    final completedStr = inspection.completedAt != null
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(inspection.completedAt!))
        : 'In Progress';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            inspection.templateName,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('Site Name:', inspection.siteName),
                    if (inspection.siteAddress != null && inspection.siteAddress!.isNotEmpty)
                      _buildDetailRow('Address:', inspection.siteAddress!),
                    _buildDetailRow('Inspector:', inspection.inspectorName),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('Status:', inspection.status.name.toUpperCase()),
                    _buildDetailRow('Started:', startedStr),
                    _buildDetailRow('Completed:', completedStr),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800),
            ),
            pw.TextSpan(
              text: value,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildSummaryCounts(Inspection inspection) {
    return pw.Row(
      children: [
        _buildCountBox('TOTAL', '${inspection.totalItems}', PdfColors.blueGrey700),
        pw.SizedBox(width: 8),
        _buildCountBox('PASS', '${inspection.passCount}', PdfColors.green700),
        pw.SizedBox(width: 8),
        _buildCountBox('FAIL', '${inspection.failCount}', PdfColors.red700),
        pw.SizedBox(width: 8),
        _buildCountBox('N/A', '${inspection.naCount}', PdfColors.grey600),
      ],
    );
  }

  pw.Widget _buildCountBox(String label, String count, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              count,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildDisclaimerBanner() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(color: PdfColors.amber600),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.only(right: 6),
            child: pw.Text(
              'NOTE:',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.amber900,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              evidenceHonestyDisclaimer,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.amber900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blueGrey900,
        ),
      ),
    );
  }

  pw.Widget _buildItemsTable(List<InspectionItem> items) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FixedColumnWidth(60),
        2: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Prompt', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Notes / Value', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            ),
          ],
        ),
        for (final item in items) ...[
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(item.prompt, style: const pw.TextStyle(fontSize: 9)),
                    if (item.required)
                      pw.Text('(Required)', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: _buildResponseBadge(item.response),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (item.severity != null)
                      pw.Text(
                        'Severity: ${item.severity!.name.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: item.severity == Severity.high
                              ? PdfColors.red
                              : PdfColors.orange,
                        ),
                      ),
                    if (item.note != null && item.note!.isNotEmpty)
                      pw.Text(item.note!, style: const pw.TextStyle(fontSize: 8)),
                    if (item.textValue != null && item.textValue!.isNotEmpty)
                      pw.Text(item.textValue!, style: const pw.TextStyle(fontSize: 8)),
                    if (item.numberValue != null)
                      pw.Text(
                        '${item.numberValue} ${item.unit ?? ''}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  pw.Widget _buildResponseBadge(ItemResponse? response) {
    PdfColor color;
    String text;

    switch (response) {
      case ItemResponse.pass:
        color = PdfColors.green700;
        text = 'PASS';
      case ItemResponse.fail:
        color = PdfColors.red700;
        text = 'FAIL';
      case ItemResponse.na:
        color = PdfColors.grey600;
        text = 'N/A';
      case null:
        color = PdfColors.orange700;
        text = 'UNANSWERED';
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Center(
        child: pw.Text(
          text,
          style: const pw.TextStyle(
            color: PdfColors.white,
            fontSize: 7.5,
          ),
        ),
      ),
    );
  }

  pw.Widget _buildEvidenceGallery(List<Attachment> attachments) {
    return pw.Wrap(
      spacing: 12,
      runSpacing: 12,
      children: attachments.map((att) {
        pw.Widget imageWidget;
        final path = att.thumbPath ?? att.localPath;

        if (path != null && File(path).existsSync()) {
          try {
            final bytes = File(path).readAsBytesSync();
            imageWidget = pw.Image(
              pw.MemoryImage(bytes),
              width: 140,
              height: 105,
              fit: pw.BoxFit.cover,
            );
          } catch (_) {
            imageWidget = _buildMissingImagePlaceholder();
          }
        } else {
          imageWidget = _buildMissingImagePlaceholder();
        }

        return pw.Container(
          width: 150,
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              imageWidget,
              pw.SizedBox(height: 4),
              pw.Text(
                'Captured: ${formatMillis(att.capturedAt)}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800),
              ),
              if (att.gpsLat != null && att.gpsLng != null)
                pw.Text(
                  'GPS: ${att.gpsLat!.toStringAsFixed(5)}, ${att.gpsLng!.toStringAsFixed(5)} (+/-${att.gpsAccuracyM?.toStringAsFixed(1) ?? '?'}m)',
                  style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
                )
              else
                pw.Text(
                  'GPS: ${att.gpsStatus.name}',
                  style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
                ),
              if (att.caption != null && att.caption!.isNotEmpty)
                pw.Text(
                  att.caption!,
                  style: const pw.TextStyle(fontSize: 7),
                  maxLines: 2,
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _buildMissingImagePlaceholder() {
    return pw.Container(
      width: 140,
      height: 105,
      color: PdfColors.grey200,
      child: pw.Center(
        child: pw.Text(
          'Photo Evidence\n(On Cloud / Local Absent)',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
    );
  }
}
