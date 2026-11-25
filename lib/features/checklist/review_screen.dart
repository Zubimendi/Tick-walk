import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/dates.dart';
import '../../domain/models.dart';
import '../../domain/validation.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/progress_bar.dart';
import '../../ui/widgets/status_chip.dart';
import 'photo_viewer_screen.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({
    super.key,
    required this.inspectionId,
  });

  final String inspectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final inspectionAsync = ref.watch(singleInspectionProvider(inspectionId));
    final itemsAsync = ref.watch(inspectionItemsProvider(inspectionId));
    final attachmentsAsync = ref.watch(inspectionAttachmentsProvider(inspectionId));
    final blockers = ref.watch(inspectionBlockersProvider(inspectionId));

    return inspectionAsync.when(
      data: (inspection) {
        if (inspection == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Review')),
            body: const Center(child: Text('Inspection not found')),
          );
        }

        final isReadOnly = inspection.isCompleted;

        return Scaffold(
          backgroundColor: tokens.bg,
          appBar: AppBar(
            title: Text(
              isReadOnly ? 'Inspection Summary' : 'Review & Finish',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.text,
              ),
            ),
            actions: [
              IconButton(
                key: const ValueKey('export_pdf_button'),
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Export PDF Report',
                onPressed: () => _exportPdf(context, ref, inspection),
              ),
            ],
          ),
          body: itemsAsync.when(
            data: (items) {
              final attachments = attachmentsAsync.value ?? [];
              final failedItems = items
                  .where((i) => i.response == ItemResponse.fail)
                  .toList();

              return ListView(
                padding: EdgeInsets.all(tokens.screenPadding),
                children: [
                  // Inspection Info Card
                  _buildInspectionHeaderCard(
                    context,
                    tokens,
                    theme,
                    inspection,
                  ),
                  SizedBox(height: tokens.space16),

                  // Blockers Section (or Success banner)
                  if (!isReadOnly) ...[
                    _buildBlockersSection(
                      context,
                      tokens,
                      theme,
                      blockers,
                    ),
                    SizedBox(height: tokens.space16),
                  ] else ...[
                    _buildCompletedBanner(
                      context,
                      tokens,
                      theme,
                      inspection,
                    ),
                    SizedBox(height: tokens.space16),
                  ],

                  // Failed Items Summary Section
                  _buildFailedItemsSection(
                    context,
                    tokens,
                    theme,
                    inspection,
                    failedItems,
                    attachments,
                    isReadOnly,
                  ),
                  SizedBox(height: tokens.space32),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading items: $err')),
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: EdgeInsets.all(tokens.screenPadding),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: isReadOnly
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('share_report_button'),
                          onPressed: () => _exportPdf(context, ref, inspection),
                          icon: const Icon(Icons.share),
                          label: const Text('Share PDF Report'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: tokens.primary,
                          ),
                        ),
                        SizedBox(height: tokens.space8),
                        OutlinedButton.icon(
                          key: const ValueKey('reopen_inspection_button'),
                          onPressed: () => _confirmReopen(context, ref, inspection),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Reopen Inspection for Editing'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ],
                    )
                  : Semantics(
                      label: blockers.isEmpty
                          ? 'Complete Inspection'
                          : 'Cannot complete inspection: ${blockers.length} blockers remaining',
                      child: FilledButton.icon(
                        key: const ValueKey('complete_inspection_button'),
                        onPressed: blockers.isEmpty
                            ? () => _completeInspection(context, ref, inspection)
                            : null,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          blockers.isEmpty
                              ? 'Complete Inspection'
                              : '${blockers.length} Blocker${blockers.length == 1 ? '' : 's'} Remaining',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: blockers.isEmpty
                              ? tokens.pass
                              : tokens.border,
                          foregroundColor: blockers.isEmpty
                              ? Colors.white
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        body: Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildInspectionHeaderCard(
    BuildContext context,
    TickTokens tokens,
    ThemeData theme,
    Inspection inspection,
  ) {
    return Card(
      elevation: 0,
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusCard),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inspection.siteName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tokens.text,
                        ),
                      ),
                      if (inspection.siteAddress != null &&
                          inspection.siteAddress!.isNotEmpty)
                        Text(
                          inspection.siteAddress!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space8,
                    vertical: tokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: inspection.isCompleted
                        ? tokens.pass.withValues(alpha: 0.12)
                        : tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(tokens.radiusChip),
                  ),
                  child: Text(
                    inspection.isCompleted ? 'Completed' : 'In Progress',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: inspection.isCompleted ? tokens.pass : tokens.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.space8),
            Text(
              'Template: ${inspection.templateName} • Inspector: ${inspection.inspectorName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            SizedBox(height: tokens.space16),
            InspectionProgressBar(
              total: inspection.totalItems,
              answered: inspection.answeredItems,
              failed: inspection.failCount,
            ),
            SizedBox(height: tokens.space12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatPill(
                  tokens,
                  theme,
                  label: 'Pass',
                  count: inspection.passCount,
                  color: tokens.pass,
                ),
                _buildStatPill(
                  tokens,
                  theme,
                  label: 'Fail',
                  count: inspection.failCount,
                  color: tokens.fail,
                ),
                _buildStatPill(
                  tokens,
                  theme,
                  label: 'N/A',
                  count: inspection.naCount,
                  color: tokens.na,
                ),
                _buildStatPill(
                  tokens,
                  theme,
                  label: 'Total',
                  count: inspection.totalItems,
                  color: tokens.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(
    TickTokens tokens,
    ThemeData theme, {
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildBlockersSection(
    BuildContext context,
    TickTokens tokens,
    ThemeData theme,
    List<CompletionBlocker> blockers,
  ) {
    if (blockers.isEmpty) {
      return Container(
        padding: EdgeInsets.all(tokens.space16),
        decoration: BoxDecoration(
          color: tokens.pass.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(tokens.radiusCard),
          border: Border.all(color: tokens.pass.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: tokens.pass, size: 28),
            SizedBox(width: tokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Requirements Met',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.pass,
                    ),
                  ),
                  Text(
                    'All required items answered and photo evidence provided. Ready to complete.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: tokens.warning, size: 22),
            SizedBox(width: tokens.space8),
            Text(
              '${blockers.length} Blocker${blockers.length == 1 ? '' : 's'} to Resolve',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.warning,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.space4),
        Text(
          'Tap any blocker to jump directly to the item and resolve it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
        SizedBox(height: tokens.space8),
        ...blockers.map((blocker) {
          final isPhoto = blocker is MissingPhotoBlocker;
          final blockerLabel = isPhoto ? 'Photo Needed' : 'Unanswered';

          return Semantics(
            button: true,
            label: 'Jump to ${blocker.prompt}: $blockerLabel',
            child: Card(
              margin: EdgeInsets.only(bottom: tokens.space8),
              elevation: 0,
              color: tokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusCard),
                side: BorderSide(color: tokens.warning.withValues(alpha: 0.4)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: tokens.warning.withValues(alpha: 0.15),
                  child: Icon(
                    isPhoto ? Icons.camera_alt_outlined : Icons.edit_note,
                    color: tokens.warning,
                    size: 20,
                  ),
                ),
                title: Text(
                  blocker.prompt,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
                subtitle: Text(
                  '${blocker.sectionTitle} • $blockerLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.warning,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  // Return the target item ID so ChecklistScreen scrolls to it
                  Navigator.of(context).pop(blocker.itemId);
                },
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCompletedBanner(
    BuildContext context,
    TickTokens tokens,
    ThemeData theme,
    Inspection inspection,
  ) {
    final completedDate = inspection.completedAt != null
        ? formatMillis(inspection.completedAt!)
        : 'Completed';

    return Container(
      padding: EdgeInsets.all(tokens.space16),
      decoration: BoxDecoration(
        color: tokens.pass.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusCard),
        border: Border.all(color: tokens.pass.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: tokens.pass, size: 28),
          SizedBox(width: tokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inspection Completed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.pass,
                  ),
                ),
                Text(
                  'Locked at $completedDate. Reopening is required to make any changes.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedItemsSection(
    BuildContext context,
    TickTokens tokens,
    ThemeData theme,
    Inspection inspection,
    List<InspectionItem> failedItems,
    List<Attachment> attachments,
    bool isReadOnly,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cancel_outlined, color: tokens.fail, size: 22),
            SizedBox(width: tokens.space8),
            Text(
              'Failed Items (${failedItems.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.text,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.space8),
        if (failedItems.isEmpty)
          Card(
            elevation: 0,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusCard),
              side: BorderSide(color: tokens.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.space16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: tokens.pass, size: 20),
                  SizedBox(width: tokens.space8),
                  Text(
                    'No failed items recorded in this inspection.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...failedItems.map((item) {
            final itemPhotos = attachments
                .where((a) => a.itemId == item.id && a.isPhoto)
                .toList();

            return Card(
              margin: EdgeInsets.only(bottom: tokens.space8),
              elevation: 0,
              color: tokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusCard),
                side: BorderSide(color: tokens.fail.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.space12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const ResultChip.fail(),
                        SizedBox(width: tokens.space8),
                        if (item.severity != null)
                          SeverityBadge(severity: item.severity!),
                        const Spacer(),
                        if (!isReadOnly)
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(item.id),
                            child: const Text('Edit Item'),
                          ),
                      ],
                    ),
                    SizedBox(height: tokens.space8),
                    Text(
                      item.prompt,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      item.sectionTitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (item.note != null && item.note!.trim().isNotEmpty) ...[
                      SizedBox(height: tokens.space8),
                      Container(
                        padding: EdgeInsets.all(tokens.space8),
                        decoration: BoxDecoration(
                          color: tokens.bg,
                          borderRadius: BorderRadius.circular(tokens.radiusCard),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.notes, size: 16, color: tokens.textSecondary),
                            SizedBox(width: tokens.space8),
                            Expanded(
                              child: Text(
                                item.note!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (itemPhotos.isNotEmpty) ...[
                      SizedBox(height: tokens.space8),
                      SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: itemPhotos.length,
                          separatorBuilder: (context, index) => SizedBox(width: tokens.space8),
                          itemBuilder: (context, pIdx) {
                            final photo = itemPhotos[pIdx];
                            final path = photo.thumbPath ?? photo.localPath;
                            final exists = path != null && File(path).existsSync();

                            return Semantics(
                              button: true,
                              label: 'View evidence photo ${pIdx + 1}',
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PhotoViewerScreen(
                                        inspectionId: inspection.id,
                                        attachmentId: photo.id,
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(tokens.radiusChip),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(tokens.radiusChip),
                                    border: Border.all(color: tokens.border),
                                    color: tokens.surface,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: exists
                                      ? Image.file(
                                          File(path),
                                          fit: BoxFit.cover,
                                          cacheWidth: 104,
                                        )
                                      : Center(
                                          child: Icon(Icons.photo,
                                              size: 20, color: tokens.textSecondary),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _completeInspection(
    BuildContext context,
    WidgetRef ref,
    Inspection inspection,
  ) async {
    final res = await ref
        .read(inspectionRepositoryProvider)
        .completeInspection(inspection.id);

    if (!context.mounted) return;

    if (res.isOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inspection marked completed and locked.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.errorOrNull!.message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmReopen(
    BuildContext context,
    WidgetRef ref,
    Inspection inspection,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reopen Inspection?'),
        content: const Text(
          'Reopening this inspection will allow editing checklist items and photos. '
          'The reopened count will be incremented.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final res = await ref
          .read(inspectionRepositoryProvider)
          .reopenInspection(inspection.id);

      if (!context.mounted) return;

      if (res.isOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inspection reopened for editing.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorOrNull!.message)),
        );
      }
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    WidgetRef ref,
    Inspection inspection,
  ) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF report...')),
      );

      final items = await ref.read(inspectionItemsProvider(inspection.id).future);
      final attachments = await ref.read(inspectionAttachmentsProvider(inspection.id).future);

      final exportService = ref.read(pdfExportServiceProvider);
      await exportService.shareReport(
        inspection: inspection,
        items: items,
        attachments: attachments,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate PDF: $e')),
        );
      }
    }
  }
}

class SeverityBadge extends StatelessWidget {
  const SeverityBadge({super.key, required this.severity});

  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final color = switch (severity) {
      Severity.low => tokens.pass,
      Severity.medium => tokens.warning,
      Severity.high => tokens.fail,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space8,
        vertical: tokens.space4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${severity.name[0].toUpperCase()}${severity.name.substring(1)} Severity',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
