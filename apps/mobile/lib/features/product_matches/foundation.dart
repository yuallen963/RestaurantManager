import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

class ProductItem {
  const ProductItem({
    required this.id,
    required this.vendorName,
    required this.description,
    this.unit,
    this.packSize,
    this.sku,
  });
  final String id, vendorName, description;
  final String? unit, packSize, sku;

  factory ProductItem.fromCandidate(Map<String, dynamic> json) {
    final invoice = Map<String, dynamic>.from(json['invoice'] as Map);
    final vendor = Map<String, dynamic>.from(invoice['vendor'] as Map);
    return ProductItem(
      id: json['id'] as String,
      vendorName: vendor['name'] as String,
      description:
          (json['normalizedName'] as String?)?.trim().isNotEmpty == true
          ? json['normalizedName'] as String
          : json['rawDescription'] as String,
      unit: json['unit'] as String?,
      packSize: json['packSize'] as String?,
      sku: json['sku'] as String?,
    );
  }
}

class ProductMatchCandidate {
  const ProductMatchCandidate({
    required this.id,
    required this.itemA,
    required this.itemB,
    required this.confidence,
    required this.reason,
  });
  final String id, confidence, reason;
  final ProductItem itemA, itemB;
  factory ProductMatchCandidate.fromJson(Map<String, dynamic> json) =>
      ProductMatchCandidate(
        id: json['id'] as String,
        itemA: ProductItem.fromCandidate(
          Map<String, dynamic>.from(json['candidateLineItemA'] as Map),
        ),
        itemB: ProductItem.fromCandidate(
          Map<String, dynamic>.from(json['candidateLineItemB'] as Map),
        ),
        confidence: json['confidence'] as String,
        reason: json['reason'] as String,
      );
}

class ProductGroupMember {
  const ProductGroupMember({
    required this.id,
    required this.vendorName,
    required this.description,
  });
  final String id, vendorName, description;
  factory ProductGroupMember.fromJson(Map<String, dynamic> json) {
    final vendor = Map<String, dynamic>.from(json['vendor'] as Map);
    final item = Map<String, dynamic>.from(json['invoiceLineItem'] as Map);
    return ProductGroupMember(
      id: json['id'] as String,
      vendorName: vendor['name'] as String,
      description:
          (item['normalizedName'] as String?)?.trim().isNotEmpty == true
          ? item['normalizedName'] as String
          : item['rawDescription'] as String,
    );
  }
}

class ProductGroup {
  const ProductGroup({
    required this.id,
    required this.displayName,
    required this.members,
  });
  final String id, displayName;
  final List<ProductGroupMember> members;
  factory ProductGroup.fromJson(Map<String, dynamic> json) => ProductGroup(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    members: (json['members'] as List)
        .map(
          (member) => ProductGroupMember.fromJson(
            Map<String, dynamic>.from(member as Map),
          ),
        )
        .toList(),
  );
}

class ProductMatchesRepository {
  ProductMatchesRepository(this.dio);
  final Dio dio;
  Future<List<ProductMatchCandidate>> candidates(String locationId) async {
    final response = await dio.get(
      '/product-matches/candidates',
      queryParameters: {'restaurantLocationId': locationId},
    );
    return (response.data as List)
        .map(
          (item) => ProductMatchCandidate.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<List<ProductGroup>> groups(String locationId) async {
    final response = await dio.get(
      '/product-groups',
      queryParameters: {'restaurantLocationId': locationId},
    );
    return (response.data as List)
        .map(
          (item) =>
              ProductGroup.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<ProductGroup> confirm(String id) async => ProductGroup.fromJson(
    Map<String, dynamic>.from(
      (await dio.post('/product-matches/$id/confirm')).data as Map,
    ),
  );
  Future<void> reject(String id) async =>
      dio.post('/product-matches/$id/reject');
  Future<ProductGroup> rename(String id, String displayName) async =>
      ProductGroup.fromJson(
        Map<String, dynamic>.from(
          (await dio.patch(
                '/product-groups/$id',
                data: {'displayName': displayName},
              )).data
              as Map,
        ),
      );
}

final productMatchesRepositoryProvider = Provider(
  (ref) => ProductMatchesRepository(ref.watch(api)),
);
final productMatchCandidatesProvider =
    FutureProvider<List<ProductMatchCandidate>>((ref) async {
      final location = ref.watch(activeLocationProvider);
      if (location == null) return [];
      return ref
          .watch(productMatchesRepositoryProvider)
          .candidates(location.id);
    });
final productGroupsProvider = FutureProvider<List<ProductGroup>>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  return ref.watch(productMatchesRepositoryProvider).groups(location.id);
});
