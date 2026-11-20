import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/app.dart';

void main() {
  testWidgets('App boots and renders navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TickwalkApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inspections'), findsWidgets);
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('Uploads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
