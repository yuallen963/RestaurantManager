import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.parse(value as String);

enum RevenueSort { newest, oldest, highestRevenue, lowestRevenue }

enum ManualRevenueType { cash, card, online, other }

extension ManualRevenueTypeLabel on ManualRevenueType {
  String get label => switch (this) {
    ManualRevenueType.cash => 'Cash Sales',
    ManualRevenueType.card => 'Card Sales',
    ManualRevenueType.online => 'Online Sales',
    ManualRevenueType.other => 'Other Sales',
  };

  String get apiValue => name.toUpperCase();
}

extension RevenueSortLabel on RevenueSort {
  String get label => switch (this) {
    RevenueSort.newest => 'Newest',
    RevenueSort.oldest => 'Oldest',
    RevenueSort.highestRevenue => 'Highest Revenue',
    RevenueSort.lowestRevenue => 'Lowest Revenue',
  };
}

class RevenueRecord {
  const RevenueRecord({
    required this.id,
    required this.date,
    required this.amount,
    required this.source,
    required this.restaurantLocationId,
    this.manualType,
    this.additionalToPos = false,
    this.notes,
  });
  final String id;
  final DateTime date;
  final double amount;
  final String source;
  final String restaurantLocationId;
  final ManualRevenueType? manualType;
  final bool additionalToPos;
  final String? notes;
  factory RevenueRecord.fromJson(Map<String, dynamic> json) => RevenueRecord(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    amount: _number(json['amount']),
    source: json['source'] as String? ?? 'UNKNOWN',
    restaurantLocationId: json['restaurantLocationId'] as String? ?? '',
    manualType: switch (json['manualType'] as String?) {
      'CASH' => ManualRevenueType.cash,
      'CARD' => ManualRevenueType.card,
      'ONLINE' => ManualRevenueType.online,
      'OTHER' => ManualRevenueType.other,
      _ => null,
    },
    additionalToPos: json['additionalToPos'] == true,
    notes: json['notes'] as String?,
  );
}

class RevenueMutation {
  const RevenueMutation({
    required this.restaurantLocationId,
    required this.date,
    required this.amount,
    required this.manualType,
    this.notes,
    this.additionalToPos = false,
  });
  final String restaurantLocationId;
  final DateTime date;
  final double amount;
  final ManualRevenueType manualType;
  final String? notes;
  final bool additionalToPos;

  Map<String, dynamic> toCreateJson() => {
    'restaurantLocationId': restaurantLocationId,
    ...toUpdateJson(),
  };

  Map<String, dynamic> toUpdateJson() => {
    'date': DateTime.utc(date.year, date.month, date.day).toIso8601String(),
    'amount': amount,
    'manualType': manualType.apiValue,
    'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    'additionalToPos': additionalToPos,
  };

  RevenueMutation copyWith({bool? additionalToPos}) => RevenueMutation(
    restaurantLocationId: restaurantLocationId,
    date: date,
    amount: amount,
    manualType: manualType,
    notes: notes,
    additionalToPos: additionalToPos ?? this.additionalToPos,
  );
}

class RevenueConflictException implements Exception {
  const RevenueConflictException(this.message, {required this.canAddToSquare});
  final String message;
  final bool canAddToSquare;
  @override
  String toString() => message;
}

class DailyRevenue {
  const DailyRevenue(this.date, this.amount);
  final DateTime date;
  final double amount;
  factory DailyRevenue.fromJson(Map<String, dynamic> json) => DailyRevenue(
    DateTime.parse(json['date'] as String),
    _number(json['amount']),
  );
}

class RevenueSummary {
  const RevenueSummary({
    required this.total,
    required this.previousTotal,
    required this.averageDaily,
    required this.highestDay,
    required this.lowestDay,
    required this.dailyTrend,
  });
  final double total;
  final double previousTotal;
  final double averageDaily;
  final DailyRevenue? highestDay;
  final DailyRevenue? lowestDay;
  final List<DailyRevenue> dailyTrend;
  factory RevenueSummary.fromJson(Map<String, dynamic> json) => RevenueSummary(
    total: _number(json['totalRevenue']),
    previousTotal: _number(json['previousTotalRevenue']),
    averageDaily: _number(json['averageDailyRevenue']),
    highestDay: json['highestDay'] == null
        ? null
        : DailyRevenue.fromJson(
            Map<String, dynamic>.from(json['highestDay'] as Map),
          ),
    lowestDay: json['lowestDay'] == null
        ? null
        : DailyRevenue.fromJson(
            Map<String, dynamic>.from(json['lowestDay'] as Map),
          ),
    dailyTrend: (json['dailyTrend'] as List)
        .map(
          (item) =>
              DailyRevenue.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

class RevenuePagination {
  const RevenuePagination({
    required this.page,
    required this.totalItems,
    required this.hasMore,
  });
  final int page;
  final int totalItems;
  final bool hasMore;
  factory RevenuePagination.fromJson(Map<String, dynamic> json) =>
      RevenuePagination(
        page: json['page'] as int,
        totalItems: json['totalItems'] as int,
        hasMore: json['hasMore'] as bool,
      );
}

class RevenuePage {
  const RevenuePage({
    required this.items,
    required this.pagination,
    required this.summary,
  });
  final List<RevenueRecord> items;
  final RevenuePagination pagination;
  final RevenueSummary summary;
  factory RevenuePage.fromJson(Map<String, dynamic> json) => RevenuePage(
    items: (json['items'] as List)
        .map(
          (item) =>
              RevenueRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    pagination: RevenuePagination.fromJson(
      Map<String, dynamic>.from(json['pagination'] as Map),
    ),
    summary: RevenueSummary.fromJson(
      Map<String, dynamic>.from(json['summary'] as Map),
    ),
  );
}

class RevenueListState {
  const RevenueListState({
    required this.items,
    required this.pagination,
    required this.summary,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });
  final List<RevenueRecord> items;
  final RevenuePagination pagination;
  final RevenueSummary summary;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  RevenueListState copyWith({
    List<RevenueRecord>? items,
    RevenuePagination? pagination,
    RevenueSummary? summary,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => RevenueListState(
    items: items ?? this.items,
    pagination: pagination ?? this.pagination,
    summary: summary ?? this.summary,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
  factory RevenueListState.fromPage(RevenuePage page) => RevenueListState(
    items: page.items,
    pagination: page.pagination,
    summary: page.summary,
  );
}

class RevenueRepository {
  RevenueRepository(this.dio);
  final Dio dio;
  Future<RevenuePage> list({
    required String locationId,
    required DateRangeState dateRange,
    required RevenueSort sort,
    required int page,
    int limit = 25,
  }) async {
    final response = await dio.get(
      '/revenue',
      queryParameters: {
        'restaurantLocationId': locationId,
        'startDate': dateRange.startDate.toIso8601String(),
        'endDate': dateRange.endDate.toIso8601String(),
        'sort': sort.name,
        'page': page,
        'limit': limit,
      },
    );
    return RevenuePage.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<RevenueRecord> detail(String id) async => RevenueRecord.fromJson(
    Map<String, dynamic>.from((await dio.get('/revenue/$id')).data as Map),
  );

  Future<RevenueRecord> create(RevenueMutation mutation) async {
    try {
      return RevenueRecord.fromJson(
        Map<String, dynamic>.from(
          (await dio.post('/revenue', data: mutation.toCreateJson())).data
              as Map,
        ),
      );
    } on DioException catch (error) {
      throw _revenueMutationError(error);
    }
  }

  Future<RevenueRecord> update(String id, RevenueMutation mutation) async {
    try {
      return RevenueRecord.fromJson(
        Map<String, dynamic>.from(
          (await dio.patch('/revenue/$id', data: mutation.toUpdateJson())).data
              as Map,
        ),
      );
    } on DioException catch (error) {
      throw _revenueMutationError(error);
    }
  }

  Future<void> delete(String id) async {
    await dio.delete('/revenue/$id');
  }
}

Object _revenueMutationError(DioException error) {
  if (error.response?.statusCode != 409) return error;
  final data = error.response?.data;
  final message = data is Map && data['message'] is String
      ? data['message'] as String
      : 'Potential duplicate revenue detected.';
  return RevenueConflictException(
    message,
    canAddToSquare: message.toLowerCase().contains('additional sales'),
  );
}

final revenueRepositoryProvider = Provider(
  (ref) => RevenueRepository(ref.watch(api)),
);
final revenueSortProvider = StateProvider((_) => RevenueSort.newest);
final revenueDetailProvider = FutureProvider.family<RevenueRecord, String>(
  (ref, id) => ref.watch(revenueRepositoryProvider).detail(id),
);

class RevenueListController extends AsyncNotifier<RevenueListState> {
  late RestaurantLocation _location;
  late DateRangeState _range;
  late RevenueSort _sort;
  @override
  Future<RevenueListState> build() async {
    final location = ref.watch(activeLocationProvider);
    if (location == null) throw StateError('No active restaurant location');
    _location = location;
    _range = ref.watch(dateRangeProvider);
    _sort = ref.watch(revenueSortProvider);
    return RevenueListState.fromPage(
      await ref
          .watch(revenueRepositoryProvider)
          .list(
            locationId: _location.id,
            dateRange: _range,
            sort: _sort,
            page: 1,
          ),
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.isLoadingMore ||
        !current.pagination.hasMore) {
      return;
    }
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final next = await ref
          .read(revenueRepositoryProvider)
          .list(
            locationId: _location.id,
            dateRange: _range,
            sort: _sort,
            page: current.pagination.page + 1,
          );
      final ids = current.items.map((item) => item.id).toSet();
      state = AsyncData(
        RevenueListState(
          items: [
            ...current.items,
            ...next.items.where((item) => ids.add(item.id)),
          ],
          pagination: next.pagination,
          summary: next.summary,
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

final revenueListProvider =
    AsyncNotifierProvider<RevenueListController, RevenueListState>(
      RevenueListController.new,
    );
