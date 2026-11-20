import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens.dart';

class AnswerButtons extends StatelessWidget {
  const AnswerButtons({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selected; // 'pass', 'fail', 'na'
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Row(
      children: [
        Expanded(
          child: _AnswerButton(
            label: 'Pass',
            icon: Icons.check,
            isSelected: selected == 'pass',
            activeColor: tokens.pass,
            enabled: enabled,
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged('pass');
            },
          ),
        ),
        SizedBox(width: tokens.space8),
        Expanded(
          child: _AnswerButton(
            label: 'Fail',
            icon: Icons.close,
            isSelected: selected == 'fail',
            activeColor: tokens.fail,
            enabled: enabled,
            onPressed: () {
              HapticFeedback.lightImpact();
              onChanged('fail');
            },
          ),
        ),
        SizedBox(width: tokens.space8),
        Expanded(
          child: _AnswerButton(
            label: 'N/A',
            icon: Icons.remove,
            isSelected: selected == 'na',
            activeColor: tokens.na,
            enabled: enabled,
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged('na');
            },
          ),
        ),
      ],
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onPressed,
    required this.enabled,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    final bg = isSelected ? activeColor : tokens.surface;
    final fg = isSelected ? Colors.white : tokens.text;
    final border = isSelected ? activeColor : tokens.border;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label answer',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: tokens.answerButtonHeight,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusCard),
            side: BorderSide(color: border, width: isSelected ? 2 : 1),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(tokens.radiusCard),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: fg),
                SizedBox(width: tokens.space4),
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
