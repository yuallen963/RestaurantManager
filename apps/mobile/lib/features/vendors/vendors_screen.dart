// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import '../revenue/foundation.dart' show DailyRevenue;
import '../revenue/revenue_screen.dart' show RevenueChart;
import 'foundation.dart';

class VendorsScreen extends ConsumerStatefulWidget {
  const VendorsScreen({super.key});
  @override
  ConsumerState<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends ConsumerState<VendorsScreen> {
  final searchController = TextEditingController(),
      scrollController = ScrollController();
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    searchController.text = ref.read(vendorFiltersProvider).search;
    scrollController.addListener(() {
      if (scrollController.position.extentAfter < 400)
        ref.read(vendorListProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void search(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted)
        ref.read(vendorFiltersProvider.notifier).state = ref
            .read(vendorFiltersProvider)
            .copyWith(search: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(activeLocationProvider);
    if (location == null)
      return ref
          .watch(activeLocationStateProvider)
          .when(
            loading: () => const LoadingState(label: 'Loading restaurant...'),
            error: (_, _) => ErrorState(
              message: 'Unable to load restaurant data',
              onRetry: () => ref.invalidate(activeLocationControllerProvider),
            ),
            data: (_) =>
                const EmptyState(message: 'No restaurant locations available'),
          );
    return ref
        .watch(vendorListProvider)
        .when(
          loading: () => const LoadingState(label: 'Loading vendors...'),
          error: (_, _) => ErrorState(
            message: 'Unable to load vendors',
            onRetry: () => ref.invalidate(vendorListProvider),
          ),
          data: (data) => content(location, data),
        );
  }

  Widget content(RestaurantLocation location, VendorListState data) =>
      ListView.builder(
        key: const Key('vendor-list'),
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: data.items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0)
            return VendorHeader(
              location: location,
              searchController: searchController,
              onSearch: search,
              count: data.pagination.totalItems,
            );
          if (index == data.items.length + 1) {
            if (data.items.isEmpty)
              return Padding(
                padding: const EdgeInsets.only(top: 36),
                child: EmptyState(
                  message:
                      ref.watch(vendorFiltersProvider).search.trim().isEmpty
                      ? 'No vendor activity found for this period.'
                      : 'No vendors match your search.',
                ),
              );
            if (data.isLoadingMore)
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            if (data.loadMoreFailed)
              return Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(vendorListProvider.notifier).loadMore(),
                  child: const Text('Retry loading more'),
                ),
              );
            return data.pagination.hasMore
                ? Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.read(vendorListProvider.notifier).loadMore(),
                      child: const Text('Load more'),
                    ),
                  )
                : const SizedBox(height: 12);
          }
          final vendor = data.items[index - 1];
          return VendorRow(
            vendor: vendor,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => VendorDetailSheet(id: vendor.id),
            ),
          );
        },
      );
}

class VendorHeader extends ConsumerWidget {
  const VendorHeader({
    required this.location,
    required this.searchController,
    required this.onSearch,
    required this.count,
    super.key,
  });
  final RestaurantLocation location;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final int count;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(vendorFiltersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vendors',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const DateRangeSelector(),
          ],
        ),
        const SizedBox(height: 12),
        LocationSelector(
          active: location,
          locations: ref.watch(availableLocationsProvider).isEmpty
              ? [location]
              : ref.watch(availableLocationsProvider),
          onSelected: (selected) => ref
              .read(activeLocationControllerProvider.notifier)
              .select(selected),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('vendor-search'),
          controller: searchController,
          onChanged: onSearch,
          decoration: InputDecoration(
            hintText: 'Search vendors',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      searchController.clear();
                      onSearch('');
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '$count active ${count == 1 ? 'vendor' : 'vendors'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuButton<VendorSort>(
              key: const Key('vendor-sort'),
              initialValue: filters.sort,
              onSelected: (sort) =>
                  ref.read(vendorFiltersProvider.notifier).state = filters
                      .copyWith(sort: sort),
              itemBuilder: (_) => VendorSort.values
                  .map(
                    (sort) =>
                        PopupMenuItem(value: sort, child: Text(sort.label)),
                  )
                  .toList(),
              child: Chip(
                avatar: const Icon(Icons.swap_vert, size: 18),
                label: Text(filters.sort.label),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class VendorRow extends StatelessWidget {
  const VendorRow({required this.vendor, required this.onTap, super.key});
  final VendorSummary vendor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    key: Key('vendor-${vendor.id}'),
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vendor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatCurrency(vendor.currentSpend),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 7),
            changeText(context, vendor.percentageChange),
            const SizedBox(height: 6),
            Text(
              '${vendor.transactionCount} ${vendor.transactionCount == 1 ? 'transaction' : 'transactions'}${vendor.lastPurchaseDate == null ? '' : '  •  Last purchase: ${vendorShortDate(vendor.lastPurchaseDate!)}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget changeText(BuildContext context, double? change) {
  if (change == null || !change.isFinite)
    return Text(
      '— vs previous period',
      style: Theme.of(context).textTheme.bodySmall,
    );
  final up = change > 0;
  return Text(
    '${up
        ? '↑'
        : change < 0
        ? '↓'
        : '→'} ${change.abs().toStringAsFixed(1)}% vs previous period',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: up ? Theme.of(context).colorScheme.error : Colors.green.shade700,
      fontWeight: FontWeight.w600,
    ),
  );
}

class VendorDetailSheet extends ConsumerWidget {
  const VendorDetailSheet({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(vendorDetailProvider(id))
      .when(
        loading: () => const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const SizedBox(
          height: 300,
          child: Center(child: Text('Unable to load vendor details')),
        ),
        data: (data) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Text(
                  data.vendor.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    metric(
                      context,
                      'Current Spend',
                      formatCurrency(data.vendor.currentSpend),
                    ),
                    metric(
                      context,
                      'Previous Spend',
                      formatCurrency(data.vendor.previousSpend),
                    ),
                    metric(
                      context,
                      'Transactions',
                      '${data.vendor.transactionCount}',
                    ),
                    metric(
                      context,
                      'Average Transaction',
                      formatCurrency(data.averageTransaction),
                    ),
                    metric(
                      context,
                      'Last Purchase',
                      data.vendor.lastPurchaseDate == null
                          ? '—'
                          : vendorShortDate(data.vendor.lastPurchaseDate!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                changeText(context, data.vendor.percentageChange),
                const SizedBox(height: 22),
                Text(
                  'Spend Trend',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                RevenueChart(
                  points: data.trend
                      .map((point) => DailyRevenue(point.date, point.amount))
                      .toList(),
                ),
                const SizedBox(height: 22),
                Text(
                  'Recent Expenses',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (data.recentExpenses.isEmpty)
                  const Text('No recent expenses for this period.')
                else
                  ...data.recentExpenses.map(
                    (expense) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        expense.description?.trim().isNotEmpty == true
                            ? expense.description!
                            : expense.category,
                      ),
                      subtitle: Text(
                        '${expense.category} • ${vendorShortDate(expense.date)}',
                      ),
                      trailing: Text(
                        formatCurrency(expense.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

Widget metric(BuildContext context, String label, String value) => SizedBox(
  width: (MediaQuery.sizeOf(context).width - 50) / 2,
  child: Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  ),
);
String vendorShortDate(DateTime value) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} ${value.day}';
