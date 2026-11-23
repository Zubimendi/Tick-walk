import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/gps_badge.dart';
import '../../ui/widgets/progress_bar.dart';
import 'checklist_item_widget.dart';
import 'section_header_widget.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({
    super.key,
    required this.inspectionId,
  });

  final String inspectionId;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  final Map<String, GlobalKey> _itemKeys = {};

  void _jumpToItem(String itemId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[itemId];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final inspectionAsync = ref.watch(singleInspectionProvider(widget.inspectionId));
    final itemsAsync = ref.watch(inspectionItemsProvider(widget.inspectionId));
    final photoCounts = ref.watch(inspectionPhotoCountsProvider(widget.inspectionId)).value ?? {};
    final blockers = ref.watch(inspectionBlockersProvider(widget.inspectionId));

    return inspectionAsync.when(
      data: (inspection) {
        if (inspection == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(child: Text('Inspection not found')),
          );
        }

        final isReadOnly = inspection.isCompleted;

        return Scaffold(
          backgroundColor: tokens.bg,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inspection.siteName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
                Text(
                  inspection.templateName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              if (inspection.startGpsStatus != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.space8),
                  child: Center(
                    child: GpsBadge(
                      status: inspection.startGpsStatus == GpsFixStatus.fix
                          ? GpsStatus.fix
                          : inspection.startGpsStatus == GpsFixStatus.stale
                              ? GpsStatus.stale
                              : inspection.startGpsStatus == GpsFixStatus.denied
                                  ? GpsStatus.denied
                                  : GpsStatus.none,
                      accuracyMeters: inspection.startAccuracyM,
                    ),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.screenPadding,
                  vertical: tokens.space8,
                ),
                child: InspectionProgressBar(
                  total: inspection.totalItems,
                  answered: inspection.answeredItems,
                  failed: inspection.failCount,
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              // Read-only Banner
              if (isReadOnly)
                Container(
                  color: tokens.accent.withValues(alpha: 0.15),
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.screenPadding,
                    vertical: tokens.space8,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: tokens.warning),
                      SizedBox(width: tokens.space8),
                      Expanded(
                        child: Text(
                          'Inspection completed (Read-only).',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: tokens.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final res = await ref
                              .read(inspectionRepositoryProvider)
                              .reopenInspection(inspection.id);
                          if (res.isErr && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res.errorOrNull!.message)),
                            );
                          }
                        },
                        child: const Text('Reopen to Edit'),
                      ),
                    ],
                  ),
                ),

              // Checklist Items by Section
              Expanded(
                child: itemsAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const Center(child: Text('No checklist items'));
                    }

                    // Group items by section
                    final sectionsMap = <String, List<InspectionItem>>{};
                    for (final it in items) {
                      sectionsMap.putIfAbsent(it.sectionTitle, () => []).add(it);
                    }

                    return ListView.builder(
                      padding: EdgeInsets.only(bottom: tokens.space32),
                      itemCount: sectionsMap.keys.length,
                      itemBuilder: (context, sIdx) {
                        final sectionTitle = sectionsMap.keys.elementAt(sIdx);
                        final sectionItems = sectionsMap[sectionTitle]!;
                        final answeredCount =
                            sectionItems.where((i) => i.isAnswered).length;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SectionHeaderWidget(
                              title: sectionTitle,
                              answered: answeredCount,
                              total: sectionItems.length,
                            ),
                            ...sectionItems.map((item) {
                              final itemKey =
                                  _itemKeys.putIfAbsent(item.id, GlobalKey.new);

                              return ChecklistItemWidget(
                                key: itemKey,
                                item: item,
                                photoCount: photoCounts[item.id] ?? 0,
                                isReadOnly: isReadOnly,
                                onAnswerChanged: ({
                                  response,
                                  severity,
                                  textValue,
                                  numberValue,
                                  note,
                                }) async {
                                  final res = await ref
                                      .read(inspectionRepositoryProvider)
                                      .updateAnswer(
                                        itemId: item.id,
                                        response: response ?? item.response,
                                        severity: severity ?? item.severity,
                                        textValue: textValue ?? item.textValue,
                                        numberValue: numberValue ?? item.numberValue,
                                        note: note ?? item.note,
                                      );
                                  if (res.isErr && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res.errorOrNull!.message),
                                      ),
                                    );
                                  }
                                },
                                onAddPhoto: () async {
                                  final res = await ref
                                      .read(capturePipelineProvider)
                                      .executeCapture(
                                        inspectionId: widget.inspectionId,
                                        itemId: item.id,
                                      );
                                  if (res.isErr && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res.errorOrNull!.message),
                                      ),
                                    );
                                  }
                                },
                              );
                            }),
                          ],
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error: $err')),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: EdgeInsets.all(tokens.screenPadding),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReadOnly
                              ? 'Inspection Completed'
                              : blockers.isEmpty
                                  ? 'All items complete'
                                  : '${blockers.length} blocker${blockers.length == 1 ? '' : 's'} remaining',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isReadOnly
                                ? tokens.textSecondary
                                : blockers.isEmpty
                                    ? tokens.pass
                                    : tokens.warning,
                          ),
                        ),
                        Text(
                          isReadOnly
                              ? 'View summary and results'
                              : blockers.isEmpty
                                  ? 'Ready to complete walk-round'
                                  : 'Resolve required items & photos',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('review_and_finish_button'),
                    onPressed: () async {
                      final targetItemId = await context.push<String>(
                        '/inspections/${inspection.id}/review',
                      );
                      if (targetItemId != null && mounted) {
                        _jumpToItem(targetItemId);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          blockers.isEmpty ? tokens.pass : tokens.primary,
                    ),
                    child: Text(
                      isReadOnly ? 'Review & Summary' : 'Review & Finish',
                    ),
                  ),
                ],
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
}
