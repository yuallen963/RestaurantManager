import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import 'foundation.dart';

String _priceCurrency(double value) =>
    '\$${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
String _shortDate(DateTime value) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} ${value.day}';

class SavingsOpportunitiesScreen extends ConsumerWidget {
  const SavingsOpportunitiesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Savings Opportunities')),
      body: location == null
          ? const EmptyState(message: 'No restaurant locations available')
          : ref
                .watch(savingsOpportunitiesProvider)
                .when(
                  loading: () => const LoadingState(
                    label: 'Loading savings opportunities...',
                  ),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load savings opportunities',
                    onRetry: () => ref.invalidate(savingsOpportunitiesProvider),
                  ),
                  data: (data) =>
                      _SavingsContent(location: location, data: data),
                ),
    );
  }
}

class _SavingsContent extends ConsumerWidget {
  const _SavingsContent({required this.location, required this.data});
  final RestaurantLocation location;
  final SavingsData data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(availableLocationsProvider);
    return ListView(
      key: const Key('savings-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        LocationSelector(
          active: location,
          locations: locations.isEmpty ? [location] : locations,
          onSelected: (selected) => ref
              .read(activeLocationControllerProvider.notifier)
              .select(selected),
        ),
        const SizedBox(height: 16),
        Text(
          'Potential Savings',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Text('Estimates based on your own reviewed invoice history.'),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _Summary(
                    label: 'Estimated monthly',
                    value: formatCurrency(data.estimatedMonthlySavings),
                  ),
                ),
                Expanded(
                  child: _Summary(
                    label: 'Estimated annual',
                    value: formatCurrency(data.estimatedAnnualSavings),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (data.items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: EmptyState(
              message:
                  'No meaningful savings opportunities found from recent confirmed products.',
            ),
          ),
        for (final item in data.items) _OpportunityCard(item: item),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.item});
  final SavingsOpportunity item;
  @override
  Widget build(BuildContext context) => Card(
    key: Key('savings-${item.productGroupId}'),
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SavingsOpportunityDetailScreen(item: item),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'You recently paid: ${item.currentVendor.name} — ${_priceCurrency(item.currentVendor.unitPrice)}/${item.unit.toLowerCase()}',
            ),
            Text(
              'Lower recent price: ${item.lowerCostVendor.name} — ${_priceCurrency(item.lowerCostVendor.unitPrice)}/${item.unit.toLowerCase()}',
            ),
            Text(
              'Difference: ${_priceCurrency(item.absoluteDifference)}/${item.unit.toLowerCase()}',
            ),
            const SizedBox(height: 8),
            Text(
              'Potential: ~${formatCurrency(item.estimatedMonthlySavings)}/month',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class SavingsOpportunityDetailScreen extends StatelessWidget {
  const SavingsOpportunityDetailScreen({required this.item, super.key});
  final SavingsOpportunity item;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Savings Detail')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          item.productName,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        _detail(
          'Recent purchase',
          '${item.currentVendor.name} • ${_priceCurrency(item.currentVendor.unitPrice)}',
        ),
        _detail('Observed', _shortDate(item.latestHigherPriceDate)),
        _detail(
          'Lower recent price',
          '${item.lowerCostVendor.name} • ${_priceCurrency(item.lowerCostVendor.unitPrice)}',
        ),
        _detail('Observed', _shortDate(item.latestLowerPriceDate)),
        _detail('Purchasing basis', '${item.unit} • ${item.packSize}'),
        _detail(
          'Price difference',
          '${_priceCurrency(item.absoluteDifference)} • ${item.percentageDifference.toStringAsFixed(1)}%',
        ),
        _detail(
          'Typical monthly usage',
          '${item.typicalMonthlyQuantity.toStringAsFixed(1)} ${item.unit.toLowerCase()}s',
        ),
        _detail(
          'Estimated monthly savings',
          _priceCurrency(item.estimatedMonthlySavings),
        ),
        _detail(
          'Estimated annual savings',
          _priceCurrency(item.estimatedAnnualSavings),
        ),
        const SizedBox(height: 16),
        Text(
          'Recent invoice evidence',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        for (final evidence in item.evidence)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${evidence.vendorName} • ${_priceCurrency(evidence.unitPrice)}',
            ),
            subtitle: Text(
              '${_shortDate(evidence.date)} • Invoice ${evidence.invoiceId.substring(0, 8)}',
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Actual pricing may vary based on availability, contract terms, delivery fees, volume, brand, and negotiated pricing.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    ),
  );
}

Widget _detail(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label)),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  ),
);
