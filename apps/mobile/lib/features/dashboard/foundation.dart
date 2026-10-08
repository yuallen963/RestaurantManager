// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../main.dart' show api;

enum DatePreset { thisMonth, lastMonth, last30Days, custom }

class DateRangeState {
  const DateRangeState(this.preset, this.startDate, this.endDate);
  final DatePreset preset;
  final DateTime startDate, endDate;
  static DateRangeState resolve(
    DatePreset preset, {
    DateTime? now,
    DateTime? start,
    DateTime? end,
  }) {
    final d = now ?? DateTime.now();
    final today = DateTime(d.year, d.month, d.day);
    if (preset == DatePreset.thisMonth)
      return DateRangeState(preset, DateTime(d.year, d.month), today);
    if (preset == DatePreset.lastMonth)
      return DateRangeState(
        preset,
        DateTime(d.year, d.month - 1),
        DateTime(d.year, d.month).subtract(const Duration(days: 1)),
      );
    if (preset == DatePreset.last30Days)
      return DateRangeState(
        preset,
        today.subtract(const Duration(days: 29)),
        today,
      );
    return DateRangeState(preset, start!, end!);
  }

  DateRangeState previous() => DateRangeState(
    DatePreset.custom,
    startDate.subtract(
      Duration(days: endDate.difference(startDate).inDays + 1),
    ),
    startDate.subtract(const Duration(days: 1)),
  );
}

class RestaurantLocation {
  const RestaurantLocation({
    required this.id,
    required this.name,
    required this.organizationId,
  });
  final String id, name, organizationId;
  factory RestaurantLocation.fromJson(Map<String, dynamic> j) =>
      RestaurantLocation(
        id: j['id'] as String,
        name: j['name'] as String,
        organizationId: j['organizationId'] as String,
      );
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw FormatException('Missing numeric $key');
}

class DashboardSummary {
  const DashboardSummary(
    this.revenue,
    this.expenses,
    this.estimatedProfit,
    this.profitMargin,
    this.foodCost,
    this.foodCostPercentage,
    this.laborCost,
    this.laborCostPercentage,
  );
  final double revenue,
      expenses,
      estimatedProfit,
      profitMargin,
      foodCost,
      foodCostPercentage,
      laborCost,
      laborCostPercentage;
  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
    _number(j, 'revenue'),
    _number(j, 'expenses'),
    _number(j, 'estimatedProfit'),
    _number(j, 'profitMargin'),
    _number(j, 'foodCost'),
    _number(j, 'foodCostPercentage'),
    _number(j, 'laborCost'),
    _number(j, 'laborCostPercentage'),
  );
}

class ExpenseBreakdown {
  const ExpenseBreakdown(
    this.categoryId,
    this.categoryName,
    this.amount,
    this.percentageOfExpenses,
  );
  final String categoryId, categoryName;
  final double amount, percentageOfExpenses;
  factory ExpenseBreakdown.fromJson(Map<String, dynamic> j) => ExpenseBreakdown(
    j['categoryId'] as String,
    j['categoryName'] as String,
    _number(j, 'amount'),
    _number(j, 'percentageOfExpenses'),
  );
}

class DashboardData {
  const DashboardData(this.summary, this.breakdown);
  final DashboardSummary summary;
  final List<ExpenseBreakdown> breakdown;
  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
    DashboardSummary.fromJson(Map<String, dynamic>.from(j['summary'])),
    (j['expenseBreakdown'] as List)
        .map((e) => ExpenseBreakdown.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class LocationsRepository {
  LocationsRepository(this.dio);
  final Dio dio;
  Future<List<RestaurantLocation>> list(String organizationId) async =>
      (await dio.get('/organizations/$organizationId/locations')).data
          .map<RestaurantLocation>(
            (e) => RestaurantLocation.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
}

class DashboardRepository {
  DashboardRepository(this.dio);
  final Dio dio;
  Future<DashboardData> get(String locationId, DateRangeState range) async {
    const path = '/dashboard';
    final query = <String, dynamic>{
      'restaurantLocationId': locationId,
      'startDate': range.startDate.toIso8601String(),
      'endDate': range.endDate.toIso8601String(),
    };
    final baseUri = Uri.parse(dio.options.baseUrl);
    final requestUri = baseUri.replace(
      path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query.map((key, value) => MapEntry(key, '$value')),
    );

    if (kDebugMode) {
      debugPrint('[DEV] Loading dashboard');
      debugPrint('[DEV] Dashboard URL: $requestUri');
      debugPrint('[DEV] Dashboard restaurantLocationId: $locationId');
      debugPrint('[DEV] Dashboard startDate: ${query['startDate']}');
      debugPrint('[DEV] Dashboard endDate: ${query['endDate']}');
    }

    try {
      final r = await dio.get(path, queryParameters: query);
      if (kDebugMode) {
        debugPrint('[DEV] Dashboard HTTP status: ${r.statusCode}');
        final body = r.data;
        debugPrint(
          '[DEV] Dashboard response shape: ${body is Map ? 'object keys: ${body.keys.join(', ')}' : body.runtimeType}',
        );
      }
      final body = Map<String, dynamic>.from(r.data as Map);
      final dashboard = DashboardData.fromJson(body);
      if (kDebugMode) debugPrint('[DEV] Dashboard loaded');
      return dashboard;
    } on DioException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[DEV] Dashboard DioException status: ${error.response?.statusCode}',
        );
        debugPrint(
          '[DEV] Dashboard DioException body: ${error.response?.data}',
        );
        debugPrint('[DEV] Dashboard DioException: ${error.message}');
      }
      rethrow;
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('[DEV] Dashboard parsing error: $error');
      rethrow;
    }
  }
}

final dateRangeProvider = StateProvider<DateRangeState>(
  (_) => DateRangeState.resolve(DatePreset.thisMonth),
);
final locationsRepositoryProvider = Provider(
  (ref) => LocationsRepository(ref.watch(api)),
);
final dashboardRepositoryProvider = Provider(
  (ref) => DashboardRepository(ref.watch(api)),
);
const _locationKey = 'activeRestaurantLocationId';
final locationStorageProvider = Provider((_) => const FlutterSecureStorage());

class ActiveLocationState {
  const ActiveLocationState(this.locations, this.active);
  final List<RestaurantLocation> locations;
  final RestaurantLocation? active;
}

class ActiveLocationController extends AsyncNotifier<ActiveLocationState> {
  @override
  Future<ActiveLocationState> build() async {
    final dio = ref.read(api);
    if (kDebugMode)
      debugPrint(
        '[DEV] Loading organizations; Authorization header present: ${dio.options.headers['Authorization'] != null}',
      );
    final organizations = await dio.get('/organizations');
    final orgs = organizations.data as List;
    if (kDebugMode) debugPrint('[DEV] Organizations loaded: ${orgs.length}');
    if (orgs.isEmpty) return const ActiveLocationState([], null);
    if (kDebugMode) debugPrint('[DEV] Loading locations');
    final locations = await ref
        .read(locationsRepositoryProvider)
        .list(orgs.first['id'] as String);
    if (kDebugMode) debugPrint('[DEV] Locations loaded: ${locations.length}');
    final saved = await ref
        .read(locationStorageProvider)
        .read(key: _locationKey);
    final active =
        locations.where((l) => l.id == saved).firstOrNull ??
        (locations.isEmpty ? null : locations.first);
    if (active != null)
      await ref
          .read(locationStorageProvider)
          .write(key: _locationKey, value: active.id);
    if (kDebugMode)
      debugPrint('[DEV] Active location: ${active?.name ?? 'none'}');
    return ActiveLocationState(locations, active);
  }

  Future<void> select(RestaurantLocation location) async {
    final current = state.valueOrNull;
    if (current == null || !current.locations.any((l) => l.id == location.id))
      throw StateError('Location is not accessible');
    await ref
        .read(locationStorageProvider)
        .write(key: _locationKey, value: location.id);
    state = AsyncData(ActiveLocationState(current.locations, location));
  }
}

final activeLocationControllerProvider =
    AsyncNotifierProvider<ActiveLocationController, ActiveLocationState>(
      ActiveLocationController.new,
    );
final activeLocationStateProvider = Provider<AsyncValue<ActiveLocationState>>(
  (ref) => ref.watch(activeLocationControllerProvider),
);
final activeLocationProvider = Provider<RestaurantLocation?>(
  (ref) => ref.watch(activeLocationStateProvider).valueOrNull?.active,
);
final availableLocationsProvider = Provider<List<RestaurantLocation>>(
  (ref) => ref.watch(activeLocationStateProvider).valueOrNull?.locations ?? [],
);
final dashboardProvider = FutureProvider<DashboardData?>((ref) async {
  final l = ref.watch(activeLocationProvider);
  if (l == null) return null;
  return ref
      .watch(dashboardRepositoryProvider)
      .get(l.id, ref.watch(dateRangeProvider));
});
final previousDashboardProvider = FutureProvider<DashboardData?>((ref) async {
  final l = ref.watch(activeLocationProvider);
  if (l == null) return null;
  final range = ref.watch(dateRangeProvider).previous();
  return ref.watch(dashboardRepositoryProvider).get(l.id, range);
});
