import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/invoice_email/foundation.dart';
import 'package:restaurant_profit_mobile/features/invoice_email/invoice_email_screen.dart';

const location = RestaurantLocation(
  id: 'loc-a',
  name: 'Downtown Grill',
  organizationId: 'org-a',
);
const secondLocation = RestaurantLocation(
  id: 'loc-b',
  name: 'Lakeside Grill',
  organizationId: 'org-a',
);
const forwardingAddress =
    'invoices+abcdef0123456789abcdef0123456789@inbound.example.com';

class FakeInvoiceEmailRepository extends InvoiceEmailRepository {
  FakeInvoiceEmailRepository({this.fail = false}) : super(Dio());
  final bool fail;
  @override
  Future<String> address(String restaurantLocationId) async {
    if (fail) throw DioException(requestOptions: RequestOptions());
    return restaurantLocationId == secondLocation.id
        ? 'invoices+fedcba9876543210fedcba9876543210@inbound.example.com'
        : forwardingAddress;
  }
}

class TestLocationController extends ActiveLocationController {
  @override
  Future<ActiveLocationState> build() async =>
      const ActiveLocationState([location, secondLocation], location);

  @override
  Future<void> select(RestaurantLocation selected) async {
    state = AsyncData(
      ActiveLocationState(state.requireValue.locations, selected),
    );
  }
}

class FakeInvoiceEmailActions extends InvoiceEmailActions {
  String? copied, shared;
  @override
  Future<void> copy(String address) async => copied = address;
  @override
  Future<void> share(String address) async => shared = address;
}

void main() {
  testWidgets('renders forwarding address and instructions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationProvider.overrideWithValue(location),
          invoiceEmailRepositoryProvider.overrideWithValue(
            FakeInvoiceEmailRepository(),
          ),
        ],
        child: const MaterialApp(home: InvoiceEmailScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(forwardingAddress), findsOneWidget);
    expect(find.textContaining('PDF, JPG and PNG'), findsOneWidget);
    expect(find.textContaining('15 MB'), findsOneWidget);
  });

  testWidgets('copy and share actions receive the forwarding address', (
    tester,
  ) async {
    final actions = FakeInvoiceEmailActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationProvider.overrideWithValue(location),
          invoiceEmailRepositoryProvider.overrideWithValue(
            FakeInvoiceEmailRepository(),
          ),
          invoiceEmailActionsProvider.overrideWithValue(actions),
        ],
        child: const MaterialApp(home: InvoiceEmailScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copy-invoice-email')));
    await tester.pump();
    expect(actions.copied, forwardingAddress);
    expect(find.text('Forwarding address copied'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-invoice-email')));
    await tester.pump();
    expect(actions.shared, forwardingAddress);
  });

  testWidgets('updates the forwarding alias when the active location changes', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        activeLocationControllerProvider.overrideWith(
          TestLocationController.new,
        ),
        invoiceEmailRepositoryProvider.overrideWithValue(
          FakeInvoiceEmailRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InvoiceEmailScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Downtown Grill'), findsOneWidget);
    expect(find.text(forwardingAddress), findsOneWidget);
    await container
        .read(activeLocationControllerProvider.notifier)
        .select(secondLocation);
    await tester.pumpAndSettle();
    expect(find.text('Lakeside Grill'), findsOneWidget);
    expect(
      find.text(
        'invoices+fedcba9876543210fedcba9876543210@inbound.example.com',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a safe unavailable state when configuration is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationProvider.overrideWithValue(location),
          invoiceEmailRepositoryProvider.overrideWithValue(
            FakeInvoiceEmailRepository(fail: true),
          ),
        ],
        child: const MaterialApp(home: InvoiceEmailScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load invoice forwarding address'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
