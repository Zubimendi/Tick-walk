import 'package:flutter/material.dart';
import '../tokens.dart';

class ResultChip extends StatelessWidget {
  const ResultChip.pass({super.key})
      : label = 'Pass',
        icon = Icons.check_circle,
        isPass = true,
        isFail = false,
        isNa = false;

  const ResultChip.fail({super.key})
      : label = 'Fail',
        icon = Icons.cancel,
        isPass = false,
        isFail = true,
        isNa = false;

  const ResultChip.na({super.key})
      : label = 'N/A',
        icon = Icons.remove_circle_outline,
        isPass = false,
        isFail = false,
        isNa = true;

  final String label;
  final IconData icon;
  final bool isPass;
  final bool isFail;
  final bool isNa;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final color = isPass
        ? tokens.pass
        : isFail
            ? tokens.fail
            : tokens.na;

    return Semantics(
      label: 'Result: $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space8,
          vertical: tokens.space4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radiusChip),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            SizedBox(width: tokens.space4),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum UploadVisualState {
  waiting,
  waitingWifi,
  uploading,
  uploaded,
  retrying,
  failed,
}

class UploadStatusChip extends StatelessWidget {
  const UploadStatusChip({
    super.key,
    required this.state,
    this.failureReason,
  });

  final UploadVisualState state;
  final String? failureReason;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final (Widget iconWidget, String label, Color color) = switch (state) {
      UploadVisualState.waiting => (
          Icon(Icons.schedule, size: 14, color: tokens.warning),
          'Waiting',
          tokens.warning,
        ),
      UploadVisualState.waitingWifi => (
          Icon(Icons.wifi_off, size: 14, color: tokens.warning),
          'Waiting for Wi-Fi',
          tokens.warning,
        ),
      UploadVisualState.uploading => (
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.primary),
            ),
          ),
          'Uploading',
          tokens.primary,
        ),
      UploadVisualState.uploaded => (
          Icon(Icons.check, size: 14, color: tokens.pass),
          'Uploaded',
          tokens.pass,
        ),
      UploadVisualState.retrying => (
          Icon(Icons.sync_problem, size: 14, color: tokens.warning),
          'Retrying soon',
          tokens.warning,
        ),
      UploadVisualState.failed => (
          Icon(Icons.error_outline, size: 14, color: tokens.fail),
          failureReason ?? 'Upload failed',
          tokens.fail,
        ),
    };

    return Semantics(
      label: 'Upload status: $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space8,
          vertical: tokens.space4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radiusChip),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            SizedBox(width: tokens.space4),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
