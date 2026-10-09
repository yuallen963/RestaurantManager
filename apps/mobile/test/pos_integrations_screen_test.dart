import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/pos/foundation.dart';
import 'package:restaurant_profit_mobile/features/pos/pos_integrations_screen.dart';

const downtown = RestaurantLocation(
  id: 'downtown',
  name: 'Downtown Grill',
  organizationId: 'org-a',
);
const lakeside = RestaurantLocation(
  id: 'lakeside',
  name: 'Lakeside Grill',
  organizationId: 'org-a',
);
final connected = PosConnectionData(
  id: 'connection',
  status: 'CONNECTED',
  merchantName: 'Square Sandbox Cafe',
  lastSyncAt: DateTime(2026, 10, 9),
  mappings: const [
    PosMapping(
      id: 'mapping',
      providerLocationId: 'square-downtown',
      providerLocationName: 'Downtown Store',
      providerTimezone: 'America/Detroit',
      restaurantLocationId: 'downtown',
      active: true,
    ),
  ],
  conflicts: [
    PosConflict(
      id: 'conflict',
      businessDate: DateTime.utc(2026, 10, 8),
      netSales: 500,
      restaurantLocationId: 'downtown',
    ),
  ],
);

class FakePosRepository extends PosRepository {
  FakePosRepository() : super(Dio());
  int connectCalls = 0, syncCalls = 0, disconnectCalls = 0, mapCalls = 0;
  bool syncFails = false;
  String? resolution;
  @override
  Future<void> connect(String organizationId) async {
    connectCalls++;
  }

  @override
  Future<List<SquareLocationData>> squareLocations(String connectionId) async =>
      const [
        SquareLocationData(
          id: 'square-lakeside',
          name: 'Lakeside Store',
          timezone: 'America/Detroit',
        ),
      ];
  @override
  Future<void> map(
    String connectionId,
    SquareLocationData square,
    String restaurantLocationId,
  ) async {
    mapCalls++;
  }

  @override
  Future<void> sync(String connectionId) async {
    syncCalls++;
    if (syncFails) throw Exception('outage');
  }

  @override
  Future<void> disconnect(String connectionId) async {
    disconnectCalls++;
  }

  @override
  Future<void> resolve(String conflictId, String value) async {
    resolution = value;
  }
}

Widget app(FakePosRepository repository, List<PosConnectionData> connections) =>
    ProviderScope(
      overrides: [
        activeLocationProvider.overrideWithValue(downtown),
        availableLocationsProvider.overrideWithValue(const [
          downtown,
          lakeside,
        ]),
        posRepositoryProvider.overrideWithValue(repository),
        posConnectionsProvider('org-a').overrideWith((_) async => connections),
      ],
      child: const MaterialApp(home: PosIntegrationsScreen()),
    );

void main() {
  testWidgets('shows disconnected Square state and starts connect flow', (
    tester,
  ) async {
    final repository = FakePosRepository();
    await tester.pumpWidget(app(repository, const []));
    await tester.pumpAndSettle();
    expect(find.text('POS Integrations'), findsOneWidget);
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(repository.connectCalls, 1);
    expect(find.textContaining('Complete authorization'), findsOneWidget);
  });

  testWidgets(
    'shows connected merchant, mapping, sync state, and conflict warning',
    (tester) async {
      final repository = FakePosRepository();
      await tester.pumpWidget(app(repository, [connected]));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Square Sandbox Cafe'), findsOneWidget);
      expect(find.text('Downtown Store'), findsOneWidget);
      expect(find.text('→ Downtown Grill'), findsOneWidget);
      expect(find.byKey(const Key('revenue-conflict-warning')), findsOneWidget);
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(repository.syncCalls, 1);
      expect(find.text('Square sales synced.'), findsOneWidget);
      await tester.tap(find.text('Use Square'));
      await tester.pumpAndSettle();
      expect(repository.resolution, 'SQUARE');
    },
  );

  testWidgets('maps Square and restaurant locations explicitly', (
    tester,
  ) async {
    final repository = FakePosRepository();
    await tester.pumpWidget(app(repository, [connected]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Map location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lakeside Store').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurant location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lakeside Grill').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Map'));
    await tester.pumpAndSettle();
    expect(repository.mapCalls, 1);
  });

  testWidgets('surfaces sync failure without exposing raw provider error', (
    tester,
  ) async {
    final repository = FakePosRepository()..syncFails = true;
    await tester.pumpWidget(app(repository, [connected]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to complete the Square action. Try again.'),
      findsOneWidget,
    );
    expect(find.text('outage'), findsNothing);
  });

  testWidgets('requires confirmation before disconnecting', (tester) async {
    final repository = FakePosRepository();
    await tester.pumpWidget(app(repository, [connected]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect Square?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(repository.disconnectCalls, 1);
  });
}
