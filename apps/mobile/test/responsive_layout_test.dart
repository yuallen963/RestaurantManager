import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/responsive.dart';

const destinations = [
  FundWellDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  FundWellDestination(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Expenses',
  ),
];

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    ValueChanged<int>? onSelected,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          selectedIndex: 0,
          onDestinationSelected: onSelected ?? (_) {},
          destinations: destinations,
          body: const Center(child: Text('Financial overview')),
          desktopHeader: const Text('Private Restaurant'),
          onNotifications: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone width preserves bottom navigation', (tester) async {
    await pumpShell(tester, size: const Size(390, 844));

    expect(find.byKey(const Key('mobile-navigation-shell')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('FundWell'), findsOneWidget);
  });

  testWidgets('tablet width uses a compact persistent navigation rail', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(900, 1024));

    expect(find.byKey(const Key('tablet-navigation-shell')), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'desktop width shows extended navigation and restaurant context',
    (tester) async {
      var selected = -1;
      await pumpShell(
        tester,
        size: const Size(1440, 900),
        onSelected: (value) => selected = value,
      );

      expect(find.byKey(const Key('desktop-navigation-shell')), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.text('Private Restaurant'), findsOneWidget);

      await tester.tap(find.text('Expenses').first);
      await tester.pump();
      expect(selected, 1);
    },
  );

  testWidgets(
    'wide content remains readable instead of stretching indefinitely',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveContent(
              maxWidth: 1200,
              child: SizedBox(
                key: Key('bounded-content'),
                width: double.infinity,
                height: 100,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('bounded-content'))).width,
        1200,
      );
    },
  );
}
