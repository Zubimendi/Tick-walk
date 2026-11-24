import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import '../../core/dates.dart';
import '../../data/sync/upload_scheduler.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/status_chip.dart';

class UploadsScreen extends ConsumerStatefulWidget {
  const UploadsScreen({super.key});

  @override
  ConsumerState<UploadsScreen> createState() => _UploadsScreenState();
}

class _UploadsScreenState extends ConsumerState<UploadsScreen> {
  bool _isSyncing = false;

  Future<void> _triggerManualSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await ref.read(syncCoordinatorProvider).triggerSync();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _uploadNowOverride() async {
    final mediaLane = ref.read(mediaLaneProvider);
    mediaLane.setOneBatchOverride(true);
    await ref.read(syncCoordinatorProvider).triggerSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting upload on mobile data...')),
      );
    }
  }

  Future<void> _retryItem(int outboxSeq) async {
    await ref.read(outboxRepositoryProvider).retryEntry(outboxSeq);
    await ref.read(syncCoordinatorProvider).triggerSync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retrying photo upload...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final queueAsync = ref.watch(uploadQueueProvider);
    final connAsync = ref.watch(connectivityStateProvider);
    final settingsAsync = ref.watch(settingsMapProvider);
    final authService = ref.watch(authServiceProvider);

    final connection = connAsync.value ?? NetworkConnectionType.wifi;
    final settings = settingsAsync.value ?? {};
    final wifiOnly = settings['wifi_only'] != 'false';
    final isSignedIn = authService.isSignedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(tokens.primary),
                    ),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: _isSyncing ? null : _triggerManualSync,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _triggerManualSync,
        child: queueAsync.when(
          data: (queue) {
            final hasPendingUploads = queue.isNotEmpty;
            final isCellularBlocked = wifiOnly && connection == NetworkConnectionType.cellular;

            return CustomScrollView(
              slivers: [
                // Top Global Status Banners
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(tokens.screenPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Account Status Banner (if not signed in)
                        if (!isSignedIn) ...[
                          _BannerCard(
                            icon: Icons.cloud_off_outlined,
                            iconColor: tokens.primary,
                            title: 'Sign in to sync',
                            description: 'Sign in to an account to backup inspections and photo evidence to the cloud.',
                            actionLabel: 'Sign In',
                            onAction: () => context.push('/settings/account'),
                          ),
                          SizedBox(height: tokens.space12),
                        ],

                        // Wi-Fi Only Gating Banner (if on cellular and uploads pending)
                        if (isCellularBlocked && hasPendingUploads) ...[
                          _BannerCard(
                            icon: Icons.wifi_off,
                            iconColor: tokens.warning,
                            title: 'Paused on mobile data',
                            description: 'Wi-Fi Only mode is enabled. Connect to Wi-Fi to resume uploads, or upload this batch now.',
                            actionLabel: 'Upload Now',
                            onAction: _uploadNowOverride,
                          ),
                          SizedBox(height: tokens.space12),
                        ],

                        // Offline Banner
                        if (connection == NetworkConnectionType.none) ...[
                          _BannerCard(
                            icon: Icons.signal_wifi_connected_no_internet_4,
                            iconColor: tokens.fail,
                            title: 'Device is offline',
                            description: 'No network connection. Uploads will resume automatically once connected.',
                          ),
                          SizedBox(height: tokens.space12),
                        ],

                        // Queue Summary Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'QUEUED EVIDENCE (${queue.length})',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            Text(
                              connection == NetworkConnectionType.wifi
                                  ? 'Wi-Fi'
                                  : connection == NetworkConnectionType.cellular
                                      ? 'Mobile Data'
                                      : 'Offline',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Queue Items List or Empty State
                if (queue.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: EmptyState(
                        icon: Icons.cloud_done_outlined,
                        title: 'Upload queue is empty',
                        message: 'All captured photos and records are stored safely on device and synced.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: tokens.screenPadding),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = queue[index];
                          return Padding(
                            padding: EdgeInsets.only(bottom: tokens.space12),
                            child: _QueueItemCard(
                              item: item,
                              onRetry: () => _retryItem(item.outboxEntry.seq),
                            ),
                          );
                        },
                        childCount: queue.length,
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error loading queue: $err')),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(tokens.space12),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusCard),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          SizedBox(width: tokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
                SizedBox(height: tokens.space4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  SizedBox(height: tokens.space8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.symmetric(horizontal: tokens.space12),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({
    required this.item,
    required this.onRetry,
  });

  final UploadQueueItem item;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final att = item.attachment;
    final path = att?.thumbPath ?? att?.localPath;
    final fileExists = path != null && File(path).existsSync();

    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(tokens.radiusCard),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(tokens.space12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusCard),
              child: SizedBox(
                width: 56,
                height: 56,
                child: fileExists
                    ? Image.file(
                        File(path),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: tokens.surface,
                          child: Icon(Icons.broken_image, color: tokens.textSecondary),
                        ),
                      )
                    : Container(
                        color: tokens.surface,
                        child: Icon(Icons.image_not_supported, color: tokens.textSecondary),
                      ),
              ),
            ),
            SizedBox(width: tokens.space12),

            // Item Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.siteName ?? 'Inspection Evidence',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: tokens.space4),
                  if (att != null)
                    Text(
                      '${formatBytes(att.bytes)} • ${formatMillis(att.capturedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  SizedBox(height: tokens.space4),
                  UploadStatusChip(
                    state: item.visualState,
                    failureReason: item.failureReason,
                  ),
                ],
              ),
            ),

            // Retry action if failed or retrying
            if (item.visualState == UploadVisualState.failed ||
                item.visualState == UploadVisualState.retrying) ...[
              SizedBox(width: tokens.space8),
              IconButton(
                icon: Icon(Icons.refresh, color: tokens.primary),
                tooltip: 'Retry upload',
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
