import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import 'foundation.dart';

class RevenueScreen extends ConsumerStatefulWidget {
  const RevenueScreen({super.key});
  @override
  ConsumerState<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends ConsumerState<RevenueScreen> {
  final scrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    scrollController.addListener(() {
      if (scrollController.position.extentAfter < 400) {
        ref.read(revenueListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(activeLocationProvider);
    if (location == null) {
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
    }
    final revenue = ref.watch(revenueListProvider);
    return revenue.when(
      loading: () => const LoadingState(label: 'Loading revenue...'),
      error: (_, _) => ErrorState(
        message: 'Unable to load revenue',
        onRetry: () => ref.invalidate(revenueListProvider),
      ),
      data: (data) => _content(context, location, data),
    );
  }

  Widget _content(
    BuildContext context,
    RestaurantLocation location,
    RevenueListState data,
  ) => ListView.builder(
    key: const Key('revenue-list'),
    controller: scrollController,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
    itemCount: data.items.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) return RevenueHeader(location: location, state: data);
      if (index == data.items.length + 1) {
        if (data.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 32),
            child: EmptyState(message: 'No revenue found for this period.'),
          );
        }
        if (data.isLoadingMore) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (data.loadMoreFailed) {
          return Center(
            child: TextButton(
              onPressed: () =>
                  ref.read(revenueListProvider.notifier).loadMore(),
              child: const Text('Retry loading more'),
            ),
          );
        }
        return data.pagination.hasMore
            ? Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(revenueListProvider.notifier).loadMore(),
                  child: const Text('Load more'),
                ),
              )
            : const SizedBox(height: 12);
      }
      final item = data.items[index - 1];
      return Card(
        key: Key('revenue-${item.id}'),
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => RevenueDetailSheet(id: item.id),
          ),
          title: Text(
            formatDate(item.date),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            item.notes?.trim().isNotEmpty == true
                ? item.notes!
                : sourceLabel(item.source),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            formatCurrency(item.amount),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
    },
  );
}

class RevenueHeader extends ConsumerWidget {
  const RevenueHeader({required this.location, required this.state, super.key});
  final RestaurantLocation location;
  final RevenueListState state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = state.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Revenue',
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
        Card(
          key: const Key('revenue-total-card'),
          color: Theme.of(context).colorScheme.primaryContainer,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Revenue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(summary.total),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                PercentageChange(
                  current: summary.total,
                  previous: summary.previousTotal,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            RevenueMetric(
              label: 'Average Daily Revenue',
              value: formatCurrency(summary.averageDaily),
            ),
            RevenueMetric(
              label: 'Strongest Sales Day',
              value: summary.highestDay == null
                  ? '—'
                  : '${formatCurrency(summary.highestDay!.amount)}\n${shortDate(summary.highestDay!.date)}',
            ),
            RevenueMetric(
              label: 'Weakest Sales Day',
              value: summary.lowestDay == null
                  ? '—'
                  : '${formatCurrency(summary.lowestDay!.amount)}\n${shortDate(summary.lowestDay!.date)}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Daily Revenue Trend',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        RevenueChart(points: summary.dailyTrend),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                '${state.pagination.totalItems} daily entries',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuButton<RevenueSort>(
              key: const Key('revenue-sort'),
              initialValue: ref.watch(revenueSortProvider),
              onSelected: (value) =>
                  ref.read(revenueSortProvider.notifier).state = value,
              itemBuilder: (_) => RevenueSort.values
                  .map(
                    (value) =>
                        PopupMenuItem(value: value, child: Text(value.label)),
                  )
                  .toList(),
              child: Chip(
                avatar: const Icon(Icons.swap_vert, size: 18),
                label: Text(ref.watch(revenueSortProvider).label),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class RevenueMetric extends StatelessWidget {
  const RevenueMetric({required this.label, required this.value, super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 42) / 2,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
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
}

class RevenueChart extends StatelessWidget {
  const RevenueChart({required this.points, super.key});
  final List<DailyRevenue> points;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: SizedBox(
      key: const Key('revenue-chart'),
      height: 190,
      width: double.infinity,
      child: points.isEmpty
          ? const Center(child: Text('No trend data'))
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              child: CustomPaint(
                painter: RevenueChartPainter(
                  points,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
    ),
  );
}

class RevenueChartPainter extends CustomPainter {
  RevenueChartPainter(this.points, this.color);
  final List<DailyRevenue> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final minValue = points.map((e) => e.amount).reduce(math.min),
        maxValue = points.map((e) => e.amount).reduce(math.max),
        spread = math.max(maxValue - minValue, 1);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? size.width / 2
          : i * size.width / (points.length - 1);
      final y =
          size.height -
          24 -
          ((points[i].amount - minValue) / spread) * (size.height - 42);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
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
    final labelStyle = TextStyle(
      color: color.withValues(alpha: .8),
      fontSize: 10,
    );
    final indexes = <int>{0, points.length ~/ 2, points.length - 1};
    for (final i in indexes) {
      final painter = TextPainter(
        text: TextSpan(text: shortDate(points[i].date), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = points.length == 1
          ? size.width / 2
          : i * size.width / (points.length - 1);
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
  bool shouldRepaint(covariant RevenueChartPainter old) =>
      old.points != points || old.color != color;
}

class RevenueDetailSheet extends ConsumerWidget {
  const RevenueDetailSheet({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(revenueDetailProvider(id))
      .when(
        loading: () => const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const SizedBox(
          height: 220,
          child: Center(child: Text('Unable to load revenue details')),
        ),
        data: (item) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Revenue Details',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                detail('Amount', formatCurrency(item.amount)),
                detail('Date', formatDate(item.date)),
                detail('Source', sourceLabel(item.source)),
                if (item.notes?.trim().isNotEmpty == true)
                  detail('Notes', item.notes!),
              ],
            ),
          ),
        ),
      );
}

Widget detail(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value),
    ],
  ),
);
String sourceLabel(String value) => value == 'POS_IMPORT'
    ? 'Square'
    : value
          .toLowerCase()
          .split('_')
          .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
          .join(' ');
String shortDate(DateTime value) => '${month(value.month)} ${value.day}';
String formatDate(DateTime value) =>
    '${month(value.month)} ${value.day}, ${value.year}';
String month(int value) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][value - 1];
