import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/product_matches/foundation.dart';
import 'package:restaurant_profit_mobile/features/product_matches/product_matches_screen.dart';

const location = RestaurantLocation(
  id: 'location-a',
  name: 'Downtown Grill',
  organizationId: 'org-a',
);
const candidate = ProductMatchCandidate(
  id: 'match-a',
  itemA: ProductItem(
    id: 'a',
    vendorName: 'Sysco',
    description: 'CHKN BRST BNLS SKLS 4/10 LB',
    unit: 'CASE',
    packSize: '4 x 10 lb',
  ),
  itemB: ProductItem(
    id: 'b',
    vendorName: 'US Foods',
    description: 'CHICKEN BREAST B/S 40LB',
    unit: 'CASE',
    packSize: '40 lb',
  ),
  confidence: 'HIGH',
  reason: 'Strong compatible match',
);
const group = ProductGroup(
  id: 'group-a',
  displayName: 'Boneless Skinless Chicken Breast',
  members: [
    ProductGroupMember(
      id: 'member-a',
      vendorName: 'Sysco',
      description: 'CHKN BRST BNLS SKLS 4/10 LB',
    ),
    ProductGroupMember(
      id: 'member-b',
      vendorName: 'US Foods',
      description: 'CHICKEN BREAST B/S 40LB',
    ),
  ],
);

class FakeProductMatchesRepository extends ProductMatchesRepository {
  FakeProductMatchesRepository({
    List<ProductMatchCandidate>? candidates,
    List<ProductGroup>? groups,
  }) : candidateRows = candidates ?? [candidate],
       groupRows = groups ?? [],
       super(Dio());
  List<ProductMatchCandidate> candidateRows;
  List<ProductGroup> groupRows;
  final confirmed = <String>[];
  final rejected = <String>[];
  @override
  Future<List<ProductMatchCandidate>> candidates(String locationId) async =>
      candidateRows;
  @override
  Future<List<ProductGroup>> groups(String locationId) async => groupRows;
  @override
  Future<ProductGroup> confirm(String id) async {
    confirmed.add(id);
    candidateRows = [];
    groupRows = [group];
    return group;
  }

  @override
  Future<void> reject(String id) async {
    rejected.add(id);
    candidateRows = [];
  }
}

Widget app(FakeProductMatchesRepository repository) => ProviderScope(
  overrides: [
    activeLocationProvider.overrideWithValue(location),
    productMatchesRepositoryProvider.overrideWithValue(repository),
  ],
  child: const MaterialApp(home: ProductMatchesScreen()),
);

void main() {
  testWidgets('candidate list renders and confirm creates a trusted group', (
    tester,
  ) async {
    final repository = FakeProductMatchesRepository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text('US Foods'), findsOneWidget);
    expect(find.text('Confidence: High'), findsOneWidget);
    await tester.tap(find.text('Same Product'));
    await tester.pumpAndSettle();
    expect(repository.confirmed, ['match-a']);
    expect(find.text('Boneless Skinless Chicken Breast'), findsOneWidget);
  });

  testWidgets('reject removes the candidate without creating a group', (
    tester,
  ) async {
    final repository = FakeProductMatchesRepository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not Same'));
    await tester.pumpAndSettle();
    expect(repository.rejected, ['match-a']);
    expect(find.text('No product matches need review.'), findsOneWidget);
  });

  testWidgets('trusted group renders and opens its member detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(FakeProductMatchesRepository(candidates: [], groups: [group])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boneless Skinless Chicken Breast'));
    await tester.pumpAndSettle();
    expect(find.text('Trusted Product'), findsOneWidget);
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text('US Foods'), findsOneWidget);
  });

  testWidgets('empty state explains that there is nothing to review', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(FakeProductMatchesRepository(candidates: [], groups: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('No product matches need review.'), findsOneWidget);
    expect(find.text('No trusted product groups yet.'), findsOneWidget);
  });
}
