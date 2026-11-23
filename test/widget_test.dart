import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app.dart';
import 'package:tickwalk/app_providers.dart';
import 'package:tickwalk/data/db/app_database.dart';

void main() {
  testWidgets('App boots and renders navigation tabs when onboarding is done', (WidgetTester tester) async {
    final db = AppDatabase.memory();
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: 'onboarding_done', value: 'true'),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const TickwalkApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inspections'), findsWidgets);
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('Uploads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await db.close();
  });
}
