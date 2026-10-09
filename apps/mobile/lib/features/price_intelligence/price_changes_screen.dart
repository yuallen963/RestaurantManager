import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import 'foundation.dart';
import '../product_matches/product_matches_screen.dart';

class PriceChangesScreen extends ConsumerWidget {
  const PriceChangesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Price Changes'),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductMatchesScreen()),
            ),
            child: const Text('Product Matches'),
          ),
        ],
      ),
      body: location == null
          ? ref
                .watch(activeLocationStateProvider)
                .when(
                  loading: () =>
                      const LoadingState(label: 'Loading restaurant...'),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load restaurant data',
                    onRetry: () =>
                        ref.invalidate(activeLocationControllerProvider),
                  ),
                  data: (_) => const EmptyState(
                    message: 'No restaurant locations available',
                  ),
                )
          : ref
                .watch(priceChangesProvider)
                .when(
                  loading: () =>
                      const LoadingState(label: 'Loading price changes...'),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load price changes',
                    onRetry: () => ref.invalidate(priceChangesProvider),
                  ),
                  data: (data) =>
                      _PriceChangesContent(location: location, data: data),
                ),
    );
  }
}

class _PriceChangesContent extends ConsumerWidget {
  const _PriceChangesContent({required this.location, required this.data});
  final RestaurantLocation location;
  final PriceChangesData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(availableLocationsProvider);
    final sort = ref.watch(priceChangeSortProvider);
    return ListView(
      key: const Key('price-changes-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        LocationSelector(
          active: location,
          locations: locations.isEmpty ? [location] : locations,
          onSelected: (selected) => ref
              .read(activeLocationControllerProvider.notifier)
              .select(selected),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Reviewed invoices • Last ${data.lookbackDays} days'),
            ),
            PopupMenuButton<PriceChangeSort>(
              key: const Key('price-change-sort'),
              initialValue: sort,
              tooltip: 'Sort price changes',
              onSelected: (value) =>
                  ref.read(priceChangeSortProvider.notifier).state = value,
              itemBuilder: (_) => PriceChangeSort.values
                  .map(
                    (value) =>
                        PopupMenuItem(value: value, child: Text(value.label)),
                  )
                  .toList(),
              child: Chip(
                avatar: const Icon(Icons.swap_vert, size: 18),
                label: Text(sort.label),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (data.items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: EmptyState(message: 'No significant price changes found.'),
          )
        else
          for (final item in data.items) _PriceChangeCard(item: item),
      ],
    );
  }
}

class _PriceChangeCard extends StatelessWidget {
  const _PriceChangeCard({required this.item});
  final PriceChangeItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isIncrease
        ? Theme.of(context).colorScheme.error
        : Colors.green.shade700;
    return Card(
      key: Key('price-change-${item.itemKey}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PriceHistoryScreen(itemKey: item.itemKey),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.displayName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(item.vendorName),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${priceCurrency(item.previousUnitPrice)} → ${priceCurrency(item.currentUnitPrice)} / ${item.unit}',
                    ),
                  ),
                  Text(
                    '${item.isIncrease ? '↑' : '↓'} ${item.percentageChange.abs().toStringAsFixed(1)}%',
                    key: Key('price-direction-${item.itemKey}'),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _impactLabel(item),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _impactLabel(PriceChangeItem item) {
  final impact = item.estimatedMonthlyImpact;
  if (impact == null) return 'Estimated impact unavailable';
  return item.isIncrease
      ? 'Est. added cost +${priceCurrency(impact)}/month'
      : 'Est. savings -${priceCurrency(impact.abs())}/month';
}

class PriceHistoryScreen extends ConsumerWidget {
  const PriceHistoryScreen({required this.itemKey, super.key});
  final String itemKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Price History')),
    body: ref
        .watch(priceHistoryProvider(itemKey))
        .when(
          loading: () => const LoadingState(label: 'Loading price history...'),
          error: (_, _) => ErrorState(
            message: 'Unable to load price history',
            onRetry: () => ref.invalidate(priceHistoryProvider(itemKey)),
          ),
          data: (data) => _PriceHistoryContent(data: data),
        ),
  );
}

class _PriceHistoryContent extends StatelessWidget {
  const _PriceHistoryContent({required this.data});
  final PriceHistoryData data;

  @override
  Widget build(BuildContext context) {
    final item = data.item;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          item.displayName,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(item.vendorName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        _details('SKU', item.sku ?? 'Not available'),
        _details(
          'Purchasing unit',
          '${item.unit}${item.packSize == null ? '' : ' • ${item.packSize}'}',
        ),
        _details('Current price', priceCurrency(item.currentUnitPrice)),
        _details('Previous price', priceCurrency(item.previousUnitPrice)),
        _details('Absolute change', signedCurrency(item.absoluteChange)),
        _details(
          'Percentage change',
          '${item.percentageChange > 0 ? '+' : ''}${item.percentageChange.toStringAsFixed(1)}%',
        ),
        _details(
          'Typical monthly volume',
          item.typicalMonthlyQuantity == null
              ? 'Unavailable'
              : '${compactNumber(item.typicalMonthlyQuantity!)} ${item.unit.toLowerCase()}s',
        ),
        _details(
          'Estimated monthly impact',
          item.estimatedMonthlyImpact == null
              ? 'Unavailable'
              : signedCurrency(item.estimatedMonthlyImpact!),
        ),
        _details(
          'Estimated annual impact',
          item.estimatedAnnualImpact == null
              ? 'Unavailable'
              : signedCurrency(item.estimatedAnnualImpact!),
        ),
        const SizedBox(height: 18),
        Text(
          'Price history',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          key: const Key('price-history-chart'),
          height: 190,
          child: CustomPaint(
            painter: PriceHistoryChartPainter(
              data.history,
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final point in data.history)
          ListTile(
            key: Key('price-point-${point.invoiceId}'),
            contentPadding: EdgeInsets.zero,
            title: Text(priceCurrency(point.unitPrice)),
            subtitle: Text(
              '${shortPriceDate(point.date)} • Source invoice ${point.invoiceId.substring(0, math.min(8, point.invoiceId.length))}',
            ),
            trailing: point.quantity == null
                ? null
                : Text('Qty ${compactNumber(point.quantity!)}'),
          ),
      ],
    );
  }
}

Widget _details(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  ),
);

class PriceHistoryChartPainter extends CustomPainter {
  PriceHistoryChartPainter(this.points, this.color);
  final List<PriceHistoryPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final minimum = points.map((point) => point.unitPrice).reduce(math.min);
    final maximum = points.map((point) => point.unitPrice).reduce(math.max);
    final spread = math.max(maximum - minimum, 1);
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? size.width / 2
          : index * size.width / (points.length - 1);
      final y =
          size.height -
          28 -
          ((points[index].unitPrice - minimum) / spread) * (size.height - 52);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final index in <int>{0, points.length ~/ 2, points.length - 1}) {
      final painter = TextPainter(
        text: TextSpan(
          text: shortPriceDate(points[index].date),
          style: TextStyle(color: color, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = points.length == 1
          ? size.width / 2
          : index * size.width / (points.length - 1);
      painter.paint(
        canvas,
        Offset(
          (x - painter.width / 2).clamp(0, size.width - painter.width),
          size.height - painter.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PriceHistoryChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

String priceCurrency(double value) =>
    '\$${value.abs().toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
String signedCurrency(double value) =>
    '${value > 0
        ? '+'
        : value < 0
        ? '-'
        : ''}${priceCurrency(value)}';
String compactNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
String shortPriceDate(DateTime value) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} ${value.day}';
