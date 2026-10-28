import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart' show demoModeProvider;
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import '../banking/foundation.dart';
import '../design/fundwell_theme.dart';
import '../responsive.dart';
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
  ) => ResponsiveContent(
    child: ListView.builder(
      key: const Key('revenue-list'),
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width >= FundWellBreakpoints.desktop
            ? 24
            : 16,
        20,
        MediaQuery.sizeOf(context).width >= FundWellBreakpoints.desktop
            ? 24
            : 16,
        32,
      ),
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
        return _RevenueRow(
          item: item,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => RevenueDetailSheet(id: item.id),
          ),
        );
      },
    ),
  );
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({required this.item, required this.onTap});
  final RevenueRecord item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final source = revenueSourceLabel(item);
    final note = item.notes?.trim();
    return Card(
      key: Key('revenue-${item.id}'),
      margin: const EdgeInsets.only(bottom: FundWellTokens.space2),
      child: InkWell(
        borderRadius: BorderRadius.circular(FundWellTokens.radius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 20 : 16,
            vertical: desktop ? 16 : 14,
          ),
          child: desktop
              ? Row(
                  children: [
                    Expanded(flex: 2, child: _RevenueDate(date: item.date)),
                    Expanded(
                      flex: 3,
                      child: _RevenueSource(source: source, note: note),
                    ),
                    SizedBox(
                      width: 150,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _RevenueAmount(amount: item.amount),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      color: FundWellTokens.mutedInk,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _RevenueSource(source: source, note: note),
                        ),
                        const SizedBox(width: 12),
                        _RevenueAmount(amount: item.amount),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _RevenueDate(date: item.date),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RevenueDate extends StatelessWidget {
  const _RevenueDate({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Text(
    formatDate(date),
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: FundWellTokens.mutedInk,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _RevenueSource extends StatelessWidget {
  const _RevenueSource({required this.source, this.note});
  final String source;
  final String? note;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(source, style: Theme.of(context).textTheme.titleMedium),
      if (note?.isNotEmpty == true) ...[
        const SizedBox(height: 3),
        Text(
          note!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: FundWellTokens.mutedInk),
        ),
      ],
    ],
  );
}

class _RevenueAmount extends StatelessWidget {
  const _RevenueAmount({required this.amount});
  final double amount;
  @override
  Widget build(BuildContext context) => Text(
    formatCurrency(amount),
    textAlign: TextAlign.right,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class RevenueHeader extends ConsumerWidget {
  const RevenueHeader({required this.location, required this.state, super.key});
  final RestaurantLocation location;
  final RevenueListState state;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = state.summary;
    final readOnly = ref.watch(demoModeProvider);
    final desktop =
        MediaQuery.sizeOf(context).width >= FundWellBreakpoints.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flex(
          direction: desktop ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: desktop
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (desktop)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revenue',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Track confirmed restaurant sales and review daily performance.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: FundWellTokens.mutedInk,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revenue',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track confirmed restaurant sales and review daily performance.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FundWellTokens.mutedInk,
                    ),
                  ),
                ],
              ),
            SizedBox(width: desktop ? 20 : 0, height: desktop ? 0 : 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const DateRangeSelector(),
                if (!readOnly)
                  FilledButton.icon(
                    key: const Key('add-revenue'),
                    onPressed: () => showRevenueForm(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Revenue'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        LocationSelector(
          active: location,
          locations: ref.watch(availableLocationsProvider).isEmpty
              ? [location]
              : ref.watch(availableLocationsProvider),
          onSelected: (selected) => ref
              .read(activeLocationControllerProvider.notifier)
              .select(selected),
        ),
        if (readOnly) ...[
          const SizedBox(height: 12),
          const _RevenueDemoNotice(),
        ],
        const SizedBox(height: 16),
        Consumer(
          builder: (context, ref, _) {
            final deposits =
                ref.watch(unverifiedBankDepositsProvider).valueOrNull ??
                const [];
            if (deposits.isEmpty) return const SizedBox.shrink();
            return Card(
              key: const Key('unverified-bank-deposits'),
              color: const Color(0xFFFFF8EC),
              child: ExpansionTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: FundWellTokens.warning,
                ),
                title: const Text('Bank Deposits Needing Review'),
                subtitle: Text(
                  '${deposits.length} ${deposits.length == 1 ? 'deposit is' : 'deposits are'} not counted as restaurant sales. Reviewing a deposit only classifies it; deposits may be transfers, loans, refunds, owner contributions, or sales.',
                ),
                children: [
                  for (final deposit in deposits.take(5))
                    ListTile(
                      title: Text(deposit.merchant),
                      subtitle: Text(
                        '${formatDate(deposit.postedDate)} · Needs review',
                      ),
                      trailing: Text(formatCurrency(deposit.amount.abs())),
                    ),
                ],
              ),
            );
          },
        ),
        if ((ref
                .watch(unverifiedBankDepositsProvider)
                .valueOrNull
                ?.isNotEmpty ??
            false))
          const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                RevenueMetric(
                  key: const Key('revenue-total-card'),
                  width: width,
                  emphasized: true,
                  label: 'Total Revenue',
                  value: formatCurrency(summary.total),
                  footer: PercentageChange(
                    current: summary.total,
                    previous: summary.previousTotal,
                  ),
                ),
                RevenueMetric(
                  width: width,
                  label: 'Average Daily Revenue',
                  value: formatCurrency(summary.averageDaily),
                ),
                RevenueMetric(
                  width: width,
                  label: 'Strongest Sales Day',
                  value: summary.highestDay == null
                      ? '—'
                      : formatCurrency(summary.highestDay!.amount),
                  detail: summary.highestDay == null
                      ? null
                      : shortDate(summary.highestDay!.date),
                ),
                RevenueMetric(
                  width: width,
                  label: 'Weakest Sales Day',
                  value: summary.lowestDay == null
                      ? '—'
                      : formatCurrency(summary.lowestDay!.amount),
                  detail: summary.lowestDay == null
                      ? null
                      : shortDate(summary.lowestDay!.date),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: 'Daily Revenue Trend',
          subtitle: 'Confirmed revenue for the selected reporting period',
          child: RevenueChart(points: summary.dailyTrend, embedded: true),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Revenue entries',
                style: Theme.of(context).textTheme.titleLarge,
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
        const SizedBox(height: 4),
        Text(
          '${state.pagination.totalItems} ${state.pagination.totalItems == 1 ? 'entry' : 'entries'} in this period',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: FundWellTokens.mutedInk),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class RevenueMetric extends StatelessWidget {
  const RevenueMetric({
    required this.label,
    required this.value,
    this.width,
    this.detail,
    this.footer,
    this.emphasized = false,
    super.key,
  });
  final String label, value;
  final double? width;
  final String? detail;
  final Widget? footer;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width ?? (MediaQuery.sizeOf(context).width - 42) / 2,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: FundWellTokens.mutedInk),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: emphasized ? FundWellTokens.purple : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 5),
              Text(
                detail!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: FundWellTokens.mutedInk),
              ),
            ],
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      ),
    ),
  );
}

class RevenueChart extends StatelessWidget {
  const RevenueChart({required this.points, this.embedded = false, super.key});
  final List<DailyRevenue> points;
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final chart = SizedBox(
      key: const Key('revenue-chart'),
      height: 220,
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
    );
    return embedded ? chart : Card(child: chart);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: FundWellTokens.mutedInk),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class _RevenueDemoNotice extends StatelessWidget {
  const _RevenueDemoNotice();
  @override
  Widget build(BuildContext context) => Card(
    color: FundWellTokens.surfaceSubtle,
    child: const Padding(
      padding: EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 20,
            color: FundWellTokens.purple,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Public demo is view only. Explore confirmed revenue and trends; adding, editing, and removing revenue is disabled.',
            ),
          ),
        ],
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
                detail('Source', revenueSourceLabel(item)),
                if (item.additionalToPos)
                  detail(
                    'Square overlap',
                    'Additional sales not included in Square',
                  ),
                finalLocationDetail(item, ref),
                if (item.notes?.trim().isNotEmpty == true)
                  detail('Notes', item.notes!),
                if (item.source == 'MANUAL' &&
                    !ref.watch(demoModeProvider)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('edit-revenue'),
                          onPressed: () async {
                            Navigator.pop(context);
                            await showRevenueForm(context, ref, initial: item);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('delete-revenue'),
                          onPressed: () => _deleteRevenue(context, ref, item),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

Widget finalLocationDetail(RevenueRecord item, WidgetRef ref) {
  final locations = ref.watch(availableLocationsProvider);
  String? name;
  for (final location in locations) {
    if (location.id == item.restaurantLocationId) {
      name = location.name;
      break;
    }
  }
  return detail('Restaurant location', name ?? 'Current restaurant');
}

Future<void> _deleteRevenue(
  BuildContext context,
  WidgetRef ref,
  RevenueRecord item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove revenue entry?'),
      content: const Text(
        'This removes the entry from financial totals. An audit record of the change will be preserved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-delete-revenue'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(revenueRepositoryProvider).delete(item.id);
    invalidateRevenue(ref, item.id);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Revenue entry removed')));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to remove revenue entry')),
    );
  }
}

Future<void> showRevenueForm(
  BuildContext context,
  WidgetRef ref, {
  RevenueRecord? initial,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => RevenueFormSheet(initial: initial),
);

void invalidateRevenue(WidgetRef ref, [String? id]) {
  ref.invalidate(revenueListProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(previousDashboardProvider);
  if (id != null) ref.invalidate(revenueDetailProvider(id));
}

class RevenueFormSheet extends ConsumerStatefulWidget {
  const RevenueFormSheet({this.initial, super.key});
  final RevenueRecord? initial;

  @override
  ConsumerState<RevenueFormSheet> createState() => _RevenueFormSheetState();
}

class _RevenueFormSheetState extends ConsumerState<RevenueFormSheet> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController notesController;
  late String locationId;
  late DateTime date;
  late ManualRevenueType manualType;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final active = ref.read(activeLocationProvider);
    locationId = widget.initial?.restaurantLocationId ?? active?.id ?? '';
    date = widget.initial?.date ?? DateTime.now();
    manualType = widget.initial?.manualType ?? ManualRevenueType.other;
    amountController = TextEditingController(
      text: widget.initial == null
          ? ''
          : widget.initial!.amount.toStringAsFixed(2),
    );
    notesController = TextEditingController(text: widget.initial?.notes ?? '');
  }

  @override
  void dispose() {
    amountController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(availableLocationsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initial == null ? 'Add Revenue' : 'Edit Revenue',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  key: const Key('revenue-location'),
                  initialValue: locations.any((item) => item.id == locationId)
                      ? locationId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Restaurant location',
                  ),
                  items: locations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: widget.initial == null
                      ? (value) => locationId = value ?? ''
                      : null,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Select a restaurant location'
                      : null,
                ),
                const SizedBox(height: 14),
                ListTile(
                  key: const Key('revenue-date'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sales date'),
                  subtitle: Text(formatDate(date)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: saving ? null : _pickDate,
                ),
                DropdownButtonFormField<ManualRevenueType>(
                  key: const Key('revenue-source'),
                  initialValue: manualType,
                  decoration: const InputDecoration(
                    labelText: 'Revenue source',
                  ),
                  items: ManualRevenueType.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() => manualType = value!),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('revenue-amount'),
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Sales amount',
                    prefixText: r'$ ',
                    helperText:
                        'Restaurant sales excluding sales tax and tips.',
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value ?? '');
                    if (amount == null || amount <= 0) {
                      return 'Enter a positive sales amount';
                    }
                    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value!)) {
                      return 'Use no more than 2 decimal places';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('revenue-notes'),
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('save-revenue'),
                    onPressed: saving ? null : () => _save(),
                    child: Text(saving ? 'Saving...' : 'Save Revenue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null) setState(() => date = selected);
  }

  Future<void> _save({bool? additionalToPos}) async {
    if (date.isAfter(DateTime.now()) ||
        formKey.currentState?.validate() != true) {
      return;
    }
    final mutation = RevenueMutation(
      restaurantLocationId: locationId,
      date: date,
      amount: double.parse(amountController.text),
      manualType: manualType,
      notes: notesController.text,
      additionalToPos:
          additionalToPos ?? widget.initial?.additionalToPos ?? false,
    );
    setState(() => saving = true);
    try {
      final repository = ref.read(revenueRepositoryProvider);
      final saved = widget.initial == null
          ? await repository.create(mutation)
          : await repository.update(widget.initial!.id, mutation);
      invalidateRevenue(ref, saved.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initial == null ? 'Revenue recorded' : 'Revenue updated',
          ),
        ),
      );
    } on RevenueConflictException catch (error) {
      if (!mounted) return;
      if (!error.canAddToSquare) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      } else {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Square sales already recorded'),
            content: Text(
              '${error.message}\n\nContinue only if this amount is separate sales that Square did not capture. It will be added to the Square total.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-square-additional-revenue'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Add Separate Sales'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          setState(() => saving = false);
          await _save(additionalToPos: true);
          return;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unable to save revenue')));
      }
    }
    if (mounted) setState(() => saving = false);
  }
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
String revenueSourceLabel(RevenueRecord item) =>
    item.source == 'MANUAL' && item.manualType != null
    ? item.manualType!.label
    : sourceLabel(item.source);
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
