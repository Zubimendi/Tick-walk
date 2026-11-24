import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/dates.dart';
import '../../domain/models.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/status_chip.dart';

class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.inspectionId,
    required this.attachmentId,
  });

  final String inspectionId;
  final String attachmentId;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final TextEditingController _captionController;
  var _isEditingCaption = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final inspectionAsync = ref.watch(singleInspectionProvider(widget.inspectionId));
    final attachmentAsync = ref.watch(singleAttachmentProvider(widget.attachmentId));

    return inspectionAsync.when(
      data: (inspection) {
        final isReadOnly = inspection?.isCompleted ?? false;

        return attachmentAsync.when(
          data: (attachment) {
            if (attachment == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Photo Viewer')),
                body: const Center(child: Text('Photo not found or has been deleted.')),
              );
            }

            if (!_isEditingCaption && _captionController.text != (attachment.caption ?? '')) {
              _captionController.text = attachment.caption ?? '';
            }

            final filePath = attachment.localPath ?? attachment.thumbPath;
            final fileExists = filePath != null && File(filePath).existsSync();

            return Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black.withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                title: Text(
                  'Evidence Photo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  if (!isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Delete photo',
                      onPressed: () => _confirmDelete(context, ref, attachment),
                    ),
                ],
              ),
              body: Column(
                children: [
                  // Full photo pinch-to-zoom area
                  Expanded(
                    child: Center(
                      child: fileExists
                          ? InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Image.file(
                                File(filePath),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Center(
                                  child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
                                ),
                              ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_not_supported, size: 64, color: Colors.white54),
                                  SizedBox(height: 8),
                                  Text(
                                    'Image file not available locally',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),

                  // Metadata panel & caption
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(tokens.screenPadding),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(tokens.radiusCard)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Caption field
                          TextField(
                            controller: _captionController,
                            enabled: !isReadOnly,
                            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.text),
                            decoration: InputDecoration(
                              hintText: isReadOnly ? 'No caption' : 'Add caption...',
                              hintStyle: TextStyle(color: tokens.textSecondary),
                              isDense: true,
                              prefixIcon: Icon(Icons.comment_outlined, size: 18, color: tokens.textSecondary),
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(color: tokens.border),
                              ),
                            ),
                            onTap: () => _isEditingCaption = true,
                            onSubmitted: (value) async {
                              _isEditingCaption = false;
                              await ref
                                  .read(attachmentRepositoryProvider)
                                  .updateCaption(attachment.id, value);
                            },
                          ),
                          SizedBox(height: tokens.space12),

                          // Metadata HUD Details
                          _buildMetadataRow(
                            tokens,
                            theme,
                            icon: Icons.access_time,
                            label: 'Captured',
                            value: formatMillis(attachment.capturedAt),
                          ),
                          SizedBox(height: tokens.space8),

                          _buildMetadataRow(
                            tokens,
                            theme,
                            icon: Icons.location_on_outlined,
                            label: 'GPS Location',
                            value: _formatGpsLocation(attachment),
                          ),
                          SizedBox(height: tokens.space8),

                          Row(
                            children: [
                              Expanded(
                                child: _buildMetadataRow(
                                  tokens,
                                  theme,
                                  icon: Icons.data_usage,
                                  label: 'File Size',
                                  value: '${(attachment.bytes / 1024).toStringAsFixed(1)} KB'
                                      '${attachment.width != null ? ' (${attachment.width}x${attachment.height})' : ''}',
                                ),
                              ),
                              UploadStatusChip(
                                state: attachment.isUploaded
                                    ? UploadVisualState.uploaded
                                    : UploadVisualState.waiting,
                              ),
                            ],
                          ),
                          SizedBox(height: tokens.space8),

                          _buildMetadataRow(
                            tokens,
                            theme,
                            icon: Icons.fingerprint,
                            label: 'SHA-256',
                            value: attachment.sha256.length > 16
                                ? '${attachment.sha256.substring(0, 16)}...'
                                : attachment.sha256,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text('Error loading photo: $err', style: const TextStyle(color: Colors.white))),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Error: $err', style: const TextStyle(color: Colors.white))),
      ),
    );
  }

  Widget _buildMetadataRow(
    TickTokens tokens,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: tokens.textSecondary),
        SizedBox(width: tokens.space8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.text,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatGpsLocation(Attachment att) {
    return switch (att.gpsStatus) {
      GpsFixStatus.fix =>
        '${att.gpsLat?.toStringAsFixed(6)}, ${att.gpsLng?.toStringAsFixed(6)} (±${att.gpsAccuracyM?.toStringAsFixed(1)} m)',
      GpsFixStatus.stale =>
        'Approximate (last known): ${att.gpsLat?.toStringAsFixed(6)}, ${att.gpsLng?.toStringAsFixed(6)}',
      GpsFixStatus.denied => 'No GPS (permission off)',
      GpsFixStatus.none => 'No GPS fix',
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Attachment attachment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Photo?'),
        content: const Text('This will remove the photo evidence from this item. You can undo this action.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final deleteRes = await ref.read(attachmentRepositoryProvider).deleteAttachment(attachment.id);
      if (!context.mounted) return;

      if (deleteRes.isOk) {
        final repo = ref.read(attachmentRepositoryProvider);
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Photo deleted'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await repo.restoreAttachment(attachment.id);
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(deleteRes.errorOrNull!.message)),
        );
      }
    }
  }
}
