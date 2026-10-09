import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart' show api;

class PosMapping {
  const PosMapping({
    required this.id,
    required this.providerLocationId,
    required this.providerLocationName,
    required this.providerTimezone,
    required this.restaurantLocationId,
    required this.active,
  });
  final String id,
      providerLocationId,
      providerLocationName,
      providerTimezone,
      restaurantLocationId;
  final bool active;
  factory PosMapping.fromJson(Map<String, dynamic> json) => PosMapping(
    id: json['id'] as String,
    providerLocationId: json['providerLocationId'] as String,
    providerLocationName: json['providerLocationName'] as String,
    providerTimezone: json['providerTimezone'] as String,
    restaurantLocationId: json['restaurantLocationId'] as String,
    active: json['active'] as bool? ?? true,
  );
}

class PosConflict {
  const PosConflict({
    required this.id,
    required this.businessDate,
    required this.netSales,
    required this.restaurantLocationId,
  });
  final String id, restaurantLocationId;
  final DateTime businessDate;
  final double netSales;
  factory PosConflict.fromJson(Map<String, dynamic> json) => PosConflict(
    id: json['id'] as String,
    businessDate: DateTime.parse(json['businessDate'] as String),
    netSales: double.parse(json['netSales'].toString()),
    restaurantLocationId: json['restaurantLocationId'] as String,
  );
}

class PosConnectionData {
  const PosConnectionData({
    required this.id,
    required this.status,
    required this.merchantName,
    required this.mappings,
    required this.conflicts,
    this.lastSyncAt,
    this.lastError,
  });
  final String id, status, merchantName;
  final DateTime? lastSyncAt;
  final String? lastError;
  final List<PosMapping> mappings;
  final List<PosConflict> conflicts;
  factory PosConnectionData.fromJson(Map<String, dynamic> json) =>
      PosConnectionData(
        id: json['id'] as String,
        status: json['status'] as String,
        merchantName: json['merchantName'] as String? ?? 'Square merchant',
        lastSyncAt: json['lastSyncAt'] == null
            ? null
            : DateTime.parse(json['lastSyncAt'] as String),
        lastError: json['lastError'] as String?,
        mappings: (json['mappings'] as List? ?? const [])
            .map(
              (item) =>
                  PosMapping.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
        conflicts: (json['dailySales'] as List? ?? const [])
            .map(
              (item) =>
                  PosConflict.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
      );
}

class SquareLocationData {
  const SquareLocationData({
    required this.id,
    required this.name,
    required this.timezone,
  });
  final String id, name, timezone;
  factory SquareLocationData.fromJson(Map<String, dynamic> json) =>
      SquareLocationData(
        id: json['id'] as String,
        name: json['name'] as String,
        timezone: json['timezone'] as String,
      );
}

class PosRepository {
  PosRepository(this.dio);
  final Dio dio;
  Future<List<PosConnectionData>> connections(String organizationId) async =>
      ((await dio.get(
                '/pos/connections',
                queryParameters: {'organizationId': organizationId},
              )).data
              as List)
          .map(
            (item) => PosConnectionData.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
  Future<void> connect(String organizationId) async {
    final response = await dio.post(
      '/pos/square/authorize',
      data: {'organizationId': organizationId},
    );
    final url = Uri.parse((response.data as Map)['authorizationUrl'] as String);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('Unable to open Square authorization');
    }
  }

  Future<List<SquareLocationData>> squareLocations(String connectionId) async =>
      ((await dio.get('/pos/connections/$connectionId/locations')).data as List)
          .map(
            (item) => SquareLocationData.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
  Future<void> map(
    String connectionId,
    SquareLocationData square,
    String restaurantLocationId,
  ) async {
    await dio.post(
      '/pos/connections/$connectionId/mappings',
      data: {
        'providerLocationId': square.id,
        'providerLocationName': square.name,
        'providerTimezone': square.timezone,
        'restaurantLocationId': restaurantLocationId,
      },
    );
  }

  Future<void> sync(String connectionId) async {
    await dio.post('/pos/connections/$connectionId/sync');
  }

  Future<void> disconnect(String connectionId) async {
    await dio.delete('/pos/connections/$connectionId');
  }

  Future<void> resolve(String conflictId, String resolution) async {
    await dio.patch(
      '/pos/revenue-conflicts/$conflictId',
      data: {'resolution': resolution},
    );
  }
}

final posRepositoryProvider = Provider((ref) => PosRepository(ref.watch(api)));
final posConnectionsProvider =
    FutureProvider.family<List<PosConnectionData>, String>(
      (ref, organizationId) =>
          ref.watch(posRepositoryProvider).connections(organizationId),
    );
