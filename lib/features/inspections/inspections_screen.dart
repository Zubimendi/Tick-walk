import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/dates.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/progress_bar.dart';
import '../../ui/widgets/status_chip.dart';
import 'new_inspection_sheet.dart';

class InspectionsScreen extends ConsumerStatefulWidget {
  const InspectionsScreen({super.key});

  @override
  ConsumerState<InspectionsScreen> createState() => _InspectionsScreenState();
}

class _InspectionsScreenState extends ConsumerState<InspectionsScreen> {
  InspectionStatus _filter = InspectionStatus.inProgress;

  void _showNewInspectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NewInspectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final inspectionsAsync = ref.watch(inspectionsStreamProvider(_filter));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        title: const Text('Inspections'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.screenPadding,
              vertical: tokens.space4,
            ),
            child: SegmentedButton<InspectionStatus>(
              segments: const [
                ButtonSegment(
                  value: InspectionStatus.inProgress,
                  label: Text('In Progress'),
                  icon: Icon(Icons.pending_actions),
                ),
                ButtonSegment(
                  value: InspectionStatus.completed,
                  label: Text('Completed'),
                  icon: Icon(Icons.task_alt),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (newSelection) {
                setState(() => _filter = newSelection.first);
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return tokens.primary.withValues(alpha: 0.15);
                  }
                  return tokens.surface;
                }),
              ),
            ),
          ),
        ),
      ),
      body: inspectionsAsync.when(
        data: (inspections) {
          if (inspections.isEmpty) {
            return EmptyState(
              icon: Icons.assignment_outlined,
              title: _filter == InspectionStatus.inProgress
                  ? 'No active walk-rounds'
                  : 'No completed inspections',
              message: _filter == InspectionStatus.inProgress
                  ? 'Start a new inspection walk-round to record findings and photo evidence.'
                  : 'Completed inspection reports will appear here.',
              actionLabel: _filter == InspectionStatus.inProgress ? 'Start Inspection' : null,
              onAction: _filter == InspectionStatus.inProgress ? _showNewInspectionSheet : null,
            );
          }

          return ListView.separated(
            padding: EdgeInsets.all(tokens.screenPadding),
            itemCount: inspections.length,
            separatorBuilder: (context, index) => SizedBox(height: tokens.space12),
            itemBuilder: (context, index) {
              final insp = inspections[index];
              return _InspectionCard(
                inspection: insp,
                onTap: () => context.push('/inspections/${insp.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewInspectionSheet,
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('New Walk-Round'),
      ),
    );
  }
}

class _InspectionCard extends ConsumerWidget {
  const _InspectionCard({
    required this.inspection,
    required this.onTap,
  });

  final Inspection inspection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final syncState = ref.watch(inspectionSyncStateProvider(inspection.id)).value;

    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(tokens.radiusCard),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusCard),
        child: Padding(
          padding: EdgeInsets.all(tokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      inspection.siteName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: tokens.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatMillis(inspection.startedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      inspection.templateName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (syncState != null) ...[
                    SizedBox(width: tokens.space8),
                    UploadStatusChip(state: syncState),
                  ],
                ],
              ),
              SizedBox(height: tokens.space12),
              InspectionProgressBar(
                total: inspection.totalItems,
                answered: inspection.answeredItems,
                failed: inspection.failCount,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
