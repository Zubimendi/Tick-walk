import 'package:flutter/material.dart';
import '../tokens.dart';

class SeverityChips extends StatelessWidget {
  const SeverityChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selected; // 'low', 'medium', 'high'
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      children: [
        _SeverityChip(
          label: 'Low',
          isSelected: selected == 'low',
          color: tokens.accent,
          enabled: enabled,
          onTap: () => onChanged(selected == 'low' ? null : 'low'),
        ),
        SizedBox(width: tokens.space8),
        _SeverityChip(
          label: 'Medium',
          isSelected: selected == 'medium',
          color: tokens.warning,
          enabled: enabled,
          onTap: () => onChanged(selected == 'medium' ? null : 'medium'),
        ),
        SizedBox(width: tokens.space8),
        _SeverityChip(
          label: 'High',
          isSelected: selected == 'high',
          color: tokens.fail,
          enabled: enabled,
          onTap: () => onChanged(selected == 'high' ? null : 'high'),
        ),
      ],
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Severity $label',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: tokens.minTouchTarget,
          minWidth: tokens.minTouchTarget,
        ),
        child: FilterChip(
          selected: isSelected,
          label: Text(label),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : tokens.text,
          ),
          selectedColor: color,
          backgroundColor: tokens.surface,
          checkmarkColor: Colors.white,
          side: BorderSide(
            color: isSelected ? color : tokens.border,
            width: isSelected ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusChip),
          ),
          onSelected: enabled ? (_) => onTap() : null,
        ),
      ),
    );
  }
}
