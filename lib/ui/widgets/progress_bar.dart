import 'package:flutter/material.dart';
import '../tokens.dart';

class InspectionProgressBar extends StatelessWidget {
  const InspectionProgressBar({
    super.key,
    required this.total,
    required this.answered,
    this.failed = 0,
  });

  final int total;
  final int answered;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final ratio = total > 0 ? (answered / total).clamp(0.0, 1.0) : 0.0;

    return Semantics(
      label: 'Progress: $answered of $total items answered, $failed failed',
      value: '${(ratio * 100).toInt()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$answered of $total answered',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
              if (failed > 0)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space8,
                    vertical: tokens.space4,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.fail.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(tokens.radiusChip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cancel, size: 14, color: tokens.fail),
                      SizedBox(width: tokens.space4),
                      Text(
                        '$failed failed',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tokens.fail,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: tokens.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusChip),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: tokens.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                failed > 0 ? tokens.accent : tokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
