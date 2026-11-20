import 'package:flutter/material.dart';

/// Design tokens for Tickwalk. High-contrast, outdoor-ready tokens.
/// All screens read from here via [context.tokens] — no raw hex in features.
@immutable
class TickTokens extends ThemeExtension<TickTokens> {
  const TickTokens({
    required this.bg,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.accent,
    required this.pass,
    required this.fail,
    required this.na,
    required this.warning,
    required this.border,
    required this.radiusCard,
    required this.radiusInput,
    required this.radiusChip,
    required this.screenPadding,
    required this.space4,
    required this.space8,
    required this.space12,
    required this.space16,
    required this.space24,
    required this.space32,
    required this.minTouchTarget,
    required this.answerButtonHeight,
  });

  final Color bg;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color accent;
  final Color pass;
  final Color fail;
  final Color na;
  final Color warning;
  final Color border;

  final double radiusCard;
  final double radiusInput;
  final double radiusChip;
  final double screenPadding;

  final double space4;
  final double space8;
  final double space12;
  final double space16;
  final double space24;
  final double space32;

  final double minTouchTarget;
  final double answerButtonHeight;

  static const light = TickTokens(
    bg: Color(0xFFF4F6F8),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF111827),
    textSecondary: Color(0xFF4B5563),
    primary: Color(0xFF0B5CAD),
    primaryPressed: Color(0xFF084A8C),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFF5B301),
    pass: Color(0xFF15803D),
    fail: Color(0xFFB91C1C),
    na: Color(0xFF4B5563),
    warning: Color(0xFF92400E),
    border: Color(0xFFD1D5DB),
    radiusCard: 12,
    radiusInput: 12,
    radiusChip: 999,
    screenPadding: 16,
    space4: 4,
    space8: 8,
    space12: 12,
    space16: 16,
    space24: 24,
    space32: 32,
    minTouchTarget: 48,
    answerButtonHeight: 56,
  );

  static const dark = TickTokens(
    bg: Color(0xFF0F1419),
    surface: Color(0xFF18202A),
    text: Color(0xFFF3F4F6),
    textSecondary: Color(0xFF9CA3AF),
    primary: Color(0xFF60A5FA),
    primaryPressed: Color(0xFF3B82F6),
    onPrimary: Color(0xFF0F1419),
    accent: Color(0xFFFBBF24),
    pass: Color(0xFF4ADE80),
    fail: Color(0xFFF87171),
    na: Color(0xFF9CA3AF),
    warning: Color(0xFFFBBF24),
    border: Color(0xFF2A3441),
    radiusCard: 12,
    radiusInput: 12,
    radiusChip: 999,
    screenPadding: 16,
    space4: 4,
    space8: 8,
    space12: 12,
    space16: 16,
    space24: 24,
    space32: 32,
    minTouchTarget: 48,
    answerButtonHeight: 56,
  );

  @override
  TickTokens copyWith({
    Color? bg,
    Color? surface,
    Color? text,
    Color? textSecondary,
    Color? primary,
    Color? primaryPressed,
    Color? onPrimary,
    Color? accent,
    Color? pass,
    Color? fail,
    Color? na,
    Color? warning,
    Color? border,
    double? radiusCard,
    double? radiusInput,
    double? radiusChip,
    double? screenPadding,
    double? space4,
    double? space8,
    double? space12,
    double? space16,
    double? space24,
    double? space32,
    double? minTouchTarget,
    double? answerButtonHeight,
  }) {
    return TickTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      primary: primary ?? this.primary,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      pass: pass ?? this.pass,
      fail: fail ?? this.fail,
      na: na ?? this.na,
      warning: warning ?? this.warning,
      border: border ?? this.border,
      radiusCard: radiusCard ?? this.radiusCard,
      radiusInput: radiusInput ?? this.radiusInput,
      radiusChip: radiusChip ?? this.radiusChip,
      screenPadding: screenPadding ?? this.screenPadding,
      space4: space4 ?? this.space4,
      space8: space8 ?? this.space8,
      space12: space12 ?? this.space12,
      space16: space16 ?? this.space16,
      space24: space24 ?? this.space24,
      space32: space32 ?? this.space32,
      minTouchTarget: minTouchTarget ?? this.minTouchTarget,
      answerButtonHeight: answerButtonHeight ?? this.answerButtonHeight,
    );
  }

  @override
  TickTokens lerp(ThemeExtension<TickTokens>? other, double t) {
    if (other is! TickTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension TickTokensX on BuildContext {
  TickTokens get tokens => Theme.of(this).extension<TickTokens>()!;
}
