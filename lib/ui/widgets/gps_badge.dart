import 'package:flutter/material.dart';
import '../tokens.dart';

enum GpsStatus { fix, stale, none, denied }

class GpsBadge extends StatelessWidget {
  const GpsBadge({
    super.key,
    required this.status,
    this.accuracyMeters,
  });

  final GpsStatus status;
  final double? accuracyMeters;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final (IconData icon, String label, Color color) = switch (status) {
      GpsStatus.fix => (
          Icons.my_location,
          accuracyMeters != null
              ? 'GPS ±${accuracyMeters!.round()} m'
              : 'GPS locked',
          tokens.pass,
        ),
      GpsStatus.stale => (
          Icons.location_searching,
          'GPS (approximate)',
          tokens.warning,
        ),
      GpsStatus.none => (
          Icons.location_off_outlined,
          'No GPS fix',
          tokens.textSecondary,
        ),
      GpsStatus.denied => (
          Icons.location_disabled,
          'GPS denied',
          tokens.warning,
        ),
    };

    return Semantics(
      label: 'Location status: $label',
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
