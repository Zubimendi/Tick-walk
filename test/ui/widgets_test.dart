import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/ui/theme.dart';
import 'package:tickwalk/ui/tokens.dart';
import 'package:tickwalk/ui/widgets/answer_buttons.dart';
import 'package:tickwalk/ui/widgets/empty_state.dart';
import 'package:tickwalk/ui/widgets/gps_badge.dart';
import 'package:tickwalk/ui/widgets/progress_bar.dart';
import 'package:tickwalk/ui/widgets/severity_chips.dart';
import 'package:tickwalk/ui/widgets/status_chip.dart';

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? buildLightTheme(),
      home: child,
    );

void main() {
  group('Theme Tokens & Base Widgets', () {
    // Token values are static constants — no context required to verify them.
    test('Light tokens have correct primary color', () {
      const tokens = TickTokens.light;
      expect(tokens.primary, equals(const Color(0xFF0B5CAD)));
      expect(tokens.pass, equals(const Color(0xFF15803D)));
      expect(tokens.fail, equals(const Color(0xFFB91C1C)));
      expect(tokens.answerButtonHeight, equals(56.0));
      expect(tokens.minTouchTarget, equals(48.0));
    });

    test('Dark tokens have correct primary color', () {
      const tokens = TickTokens.dark;
      expect(tokens.primary, equals(const Color(0xFF60A5FA)));
      expect(tokens.pass, equals(const Color(0xFF4ADE80)));
      expect(tokens.fail, equals(const Color(0xFFF87171)));
      expect(tokens.bg, equals(const Color(0xFF0F1419)));
    });

    test('buildLightTheme registers TickTokens extension', () {
      final theme = buildLightTheme();
      final ext = theme.extension<TickTokens>();
      expect(ext, isNotNull);
      expect(ext!.primary, equals(TickTokens.light.primary));
    });

    test('buildDarkTheme registers TickTokens extension', () {
      final theme = buildDarkTheme();
      final ext = theme.extension<TickTokens>();
      expect(ext, isNotNull);
      expect(ext!.primary, equals(TickTokens.dark.primary));
    });

    testWidgets('Light theme renders via context.tokens', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          // theme: sets the light ThemeData (default behavior)
          theme: buildLightTheme(),
          home: Builder(
            builder: (context) {
              final tokens = context.tokens;
              expect(tokens.primary, equals(TickTokens.light.primary));
              return Scaffold(
                backgroundColor: tokens.bg,
                body: Text('Light Mode', style: TextStyle(color: tokens.text)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Light Mode'), findsOneWidget);
    });

    testWidgets('Dark theme renders via context.tokens when forced via MediaQuery', (tester) async {
      // The flutter test harness always reports Brightness.light as platform
      // brightness. To force dark-theme resolution from context, we set the
      // platform brightness to dark via MediaQuery override.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            platformBrightness: Brightness.dark,
          ),
          child: MaterialApp(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: ThemeMode.system,
            home: Builder(
              builder: (context) {
                final tokens = context.tokens;
                expect(tokens.primary, equals(TickTokens.dark.primary));
                return Scaffold(
                  backgroundColor: tokens.bg,
                  body:
                      Text('Dark Mode', style: TextStyle(color: tokens.text)),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dark Mode'), findsOneWidget);
    });

    testWidgets('AnswerButtons triggers callbacks with haptics', (tester) async {
      String? answer;
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: AnswerButtons(
              selected: answer,
              onChanged: (val) => answer = val,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pass'));
      expect(answer, equals('pass'));

      await tester.tap(find.text('Fail'));
      expect(answer, equals('fail'));

      await tester.tap(find.text('N/A'));
      expect(answer, equals('na'));
    });

    testWidgets('ProgressBar renders progress correctly', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: InspectionProgressBar(
              total: 10,
              answered: 6,
              failed: 2,
            ),
          ),
        ),
      );

      expect(find.text('6 of 10 answered'), findsOneWidget);
      expect(find.text('2 failed'), findsOneWidget);
    });

    testWidgets('GpsBadge displays status and accuracy', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Column(
              children: [
                GpsBadge(status: GpsStatus.fix, accuracyMeters: 8.4),
                GpsBadge(status: GpsStatus.stale),
                GpsBadge(status: GpsStatus.denied),
              ],
            ),
          ),
        ),
      );

      expect(find.text('GPS ±8 m'), findsOneWidget);
      expect(find.text('GPS (approximate)'), findsOneWidget);
      expect(find.text('GPS denied'), findsOneWidget);
    });

    testWidgets('ResultChip and UploadStatusChip render appropriate labels',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Column(
              children: [
                ResultChip.pass(),
                ResultChip.fail(),
                ResultChip.na(),
                UploadStatusChip(state: UploadVisualState.waiting),
                UploadStatusChip(state: UploadVisualState.uploaded),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Pass'), findsOneWidget);
      expect(find.text('Fail'), findsOneWidget);
      expect(find.text('N/A'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('EmptyState displays icon, title and action', (tester) async {
      var actionTriggered = false;
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: EmptyState(
              icon: Icons.checklist,
              title: 'No Checklists',
              message: 'Get started by creating one',
              actionLabel: 'Create Now',
              onAction: () => actionTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('No Checklists'), findsOneWidget);
      expect(find.text('Get started by creating one'), findsOneWidget);
      await tester.tap(find.text('Create Now'));
      expect(actionTriggered, isTrue);
    });

    testWidgets('SeverityChips toggles selection', (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: SeverityChips(
                  selected: selected,
                  onChanged: (val) {
                    setState(() {
                      selected = val;
                    });
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      expect(selected, equals('high'));
    });
  });
}
