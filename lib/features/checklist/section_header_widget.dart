import 'package:flutter/material.dart';
import '../../ui/tokens.dart';

class SectionHeaderWidget extends StatelessWidget {
  const SectionHeaderWidget({
    super.key,
    required this.title,
    required this.answered,
    required this.total,
  });

  final String title;
  final int answered;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.screenPadding,
        vertical: tokens.space8,
      ),
      color: tokens.bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
                letterSpacing: 0.8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space8,
              vertical: tokens.space4,
            ),
            decoration: BoxDecoration(
              color: tokens.border.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(tokens.radiusChip),
            ),
            child: Text(
              '$answered / $total',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
