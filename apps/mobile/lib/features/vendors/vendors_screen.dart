// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import '../banking/bank_screens.dart';
import '../banking/foundation.dart';
import '../revenue/foundation.dart' show DailyRevenue;
import '../revenue/revenue_screen.dart' show RevenueChart;
import '../price_intelligence/price_changes_screen.dart';
import 'foundation.dart';
import '../responsive.dart';

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
      ResponsiveContent(
        child: ListView.builder(
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
                  child: _VendorEmptyState(
                    filtered: ref
                        .watch(vendorFiltersProvider)
                        .search
                        .trim()
                        .isNotEmpty,
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
        ),
      );
}

class _VendorEmptyState extends ConsumerWidget {
  const _VendorEmptyState({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filtered)
      return const EmptyState(message: 'No vendors match your search.');
    final sync = ref.watch(bankSyncStatusProvider).valueOrNull;
    final waiting = ref.watch(bankTransactionsAwaitingReviewProvider);
    final waitingCount = waiting.valueOrNull?.length ?? 0;
    final message = sync?.inProgress == true
        ? 'Bank synchronization is still in progress. Merchant activity becomes confirmed vendor spending only after a purchase is added to Expenses and linked to a Vendor.'
        : waitingCount > 0
        ? 'Bank merchant names do not become confirmed Vendors automatically. Review purchases, add them to Expenses, and link them to Vendors to see confirmed spending here.'
        : 'No confirmed vendor activity was found for this period. Vendor spending appears after purchases are added to Expenses and linked to Vendors.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyState(message: message),
        if (waitingCount > 0) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('review-bank-transactions-vendors'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BankTransactionsScreen()),
            ),
            icon: const Icon(Icons.account_balance),
            label: const Text('Review Bank Transactions'),
          ),
        ],
      ],
    );
  }
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
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const Key('vendor-price-changes'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PriceChangesScreen()),
            ),
            icon: const Icon(Icons.trending_up),
            label: const Text('Price Changes'),
          ),
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
        _BankMerchantSummary(
          transactions:
              ref.watch(allBankTransactionsProvider).valueOrNull ?? const [],
        ),
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

class _BankMerchantSummary extends StatelessWidget {
  const _BankMerchantSummary({required this.transactions});
  final List<BankTransactionData> transactions;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<BankTransactionData>>{};
    for (final item in transactions.where((item) => item.amount > 0)) {
      groups.putIfAbsent(item.merchant, () => []).add(item);
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    final merchants = groups.entries.toList()
      ..sort(
        (a, b) => b.value
            .fold<double>(0, (sum, item) => sum + item.amount)
            .compareTo(
              a.value.fold<double>(0, (sum, item) => sum + item.amount),
            ),
      );
    return Card(
      key: const Key('bank-merchants-section'),
      elevation: 0,
      child: ExpansionTile(
        title: const Text('Bank Merchants'),
        subtitle: const Text(
          'Imported names are not confirmed Vendors until you review and link them.',
        ),
        children: [
          for (final entry in merchants.take(5))
            ListTile(
              title: Text(entry.key),
              subtitle: Text(
                '${entry.value.length} transactions · ${entry.value.any((item) => item.vendorId != null) ? 'Vendor associated' : 'Needs review'}',
              ),
              trailing: Text(
                formatCurrency(
                  entry.value.fold<double>(0, (sum, item) => sum + item.amount),
                ),
              ),
            ),
          ListTile(
            title: const Text('Review Bank Transactions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BankTransactionsScreen()),
            ),
          ),
        ],
      ),
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
