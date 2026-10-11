import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/more/location_management_screen.dart';

const bangkok = RestaurantLocation(
  id: 'bangkok',
  name: 'Bangkok Cuisine',
  organizationId: 'org-a',
  addressLine1: '727 N Main Street',
  city: 'Rochester',
  state: 'MI',
  postalCode: '48307',
);
const second = RestaurantLocation(
  id: 'test-location',
  name: 'FundWell Test Restaurant',
  organizationId: 'org-a',
  addressLine1: '123 Test Street',
  city: 'Rochester',
  state: 'MI',
  postalCode: '48307',
);

class TestLocationController extends ActiveLocationController {
  @override
  Future<ActiveLocationState> build() async =>
      const ActiveLocationState([bangkok], bangkok);

  @override
  Future<void> reload({String? preferredLocationId}) async {
    state = const AsyncData(ActiveLocationState([bangkok, second], second));
  }
}

void main() {
  late Dio dio;
  late List<RequestOptions> requests;

  setUp(() {
    requests = [];
    dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': options.path.endsWith('/bangkok')
                      ? 'bangkok'
                      : 'test-location',
                  'organizationId': 'org-a',
                  ...(options.data as Map<String, dynamic>),
                },
              ),
            );
          },
        ),
      );
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool canManage = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        activeLocationControllerProvider.overrideWith(
          TestLocationController.new,
        ),
        locationsRepositoryProvider.overrideWithValue(LocationsRepository(dio)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LocationManagementScreen(canManage: canManage),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('owner creates a validated location and it becomes active', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('add-location')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('location-name')),
      'FundWell Test Restaurant',
    );
    await tester.enterText(
      find.byKey(const Key('location-address')),
      '123 Test Street',
    );
    await tester.enterText(find.byKey(const Key('location-city')), 'Rochester');
    await tester.enterText(
      find.byKey(const Key('location-postal-code')),
      '48307',
    );
    await tester.tap(find.byKey(const Key('save-location')));
    await tester.pumpAndSettle();

    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/organizations/org-a/locations');
    expect(container.read(activeLocationProvider)?.id, 'test-location');
    expect(find.text('FundWell Test Restaurant'), findsOneWidget);
  });

  testWidgets('form blocks invalid required fields', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('add-location')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-location')));
    await tester.pump();
    expect(find.text('This field is required'), findsNWidgets(4));
    expect(requests, isEmpty);
  });

  testWidgets('owner edits a location through the scoped PATCH endpoint', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        locationsRepositoryProvider.overrideWithValue(LocationsRepository(dio)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LocationFormScreen(location: bangkok)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('location-name')),
      'Bangkok Cuisine Rochester',
    );
    await tester.tap(find.byKey(const Key('save-location')));
    await tester.pumpAndSettle();

    expect(requests.single.method, 'PATCH');
    expect(requests.single.path, '/organizations/org-a/locations/bangkok');
    expect((requests.single.data as Map)['name'], 'Bangkok Cuisine Rochester');
  });

  testWidgets('viewer can switch but cannot add or edit locations', (
    tester,
  ) async {
    await pump(tester, canManage: false);
    expect(find.byKey(const Key('add-location')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Bangkok Cuisine'), findsOneWidget);
  });
}
