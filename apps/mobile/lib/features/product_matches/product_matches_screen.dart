import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import 'foundation.dart';

class ProductMatchesScreen extends ConsumerWidget {
  const ProductMatchesScreen({super.key});

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool confirm,
  ) async {
    try {
      final repository = ref.read(productMatchesRepositoryProvider);
      if (confirm) {
        await repository.confirm(id);
      } else {
        await repository.reject(id);
      }
      ref.invalidate(productMatchCandidatesProvider);
      ref.invalidate(productGroupsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save product match decision'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Product Matches')),
      body: location == null
          ? const EmptyState(message: 'No restaurant locations available')
          : ref
                .watch(productMatchCandidatesProvider)
                .when(
                  loading: () =>
                      const LoadingState(label: 'Loading product matches...'),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load product matches',
                    onRetry: () =>
                        ref.invalidate(productMatchCandidatesProvider),
                  ),
                  data: (candidates) => ref
                      .watch(productGroupsProvider)
                      .when(
                        loading: () => const LoadingState(
                          label: 'Loading trusted products...',
                        ),
                        error: (_, _) => ErrorState(
                          message: 'Unable to load trusted products',
                          onRetry: () => ref.invalidate(productGroupsProvider),
                        ),
                        data: (groups) => ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: [
                            Text(
                              location.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Pending Matches',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (candidates.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No product matches need review.'),
                              ),
                            for (final candidate in candidates)
                              _CandidateCard(
                                candidate: candidate,
                                onConfirm: () =>
                                    _decide(context, ref, candidate.id, true),
                                onReject: () =>
                                    _decide(context, ref, candidate.id, false),
                              ),
                            const SizedBox(height: 20),
                            Text(
                              'Trusted Products',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (groups.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No trusted product groups yet.'),
                              ),
                            for (final group in groups)
                              ListTile(
                                key: Key('product-group-${group.id}'),
                                title: Text(group.displayName),
                                subtitle: Text(
                                  '${group.members.length} vendor items',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ProductGroupDetailScreen(group: group),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.onConfirm,
    required this.onReject,
  });
  final ProductMatchCandidate candidate;
  final VoidCallback onConfirm, onReject;
  @override
  Widget build(BuildContext context) => Card(
    key: Key('product-match-${candidate.id}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.itemA.vendorName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(candidate.itemA.description),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.swap_vert),
            ),
          ),
          Text(
            candidate.itemB.vendorName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(candidate.itemB.description),
          const SizedBox(height: 12),
          Text(
            'Confidence: ${candidate.confidence[0]}${candidate.confidence.substring(1).toLowerCase()}',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  child: const Text('Same Product'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Not Same'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ProductGroupDetailScreen extends ConsumerStatefulWidget {
  const ProductGroupDetailScreen({required this.group, super.key});
  final ProductGroup group;
  @override
  ConsumerState<ProductGroupDetailScreen> createState() =>
      _ProductGroupDetailScreenState();
}

class _ProductGroupDetailScreenState
    extends ConsumerState<ProductGroupDetailScreen> {
  late final controller = TextEditingController(text: widget.group.displayName);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trusted Product')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('product-group-name'),
          controller: controller,
          decoration: const InputDecoration(labelText: 'Product name'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            await ref
                .read(productMatchesRepositoryProvider)
                .rename(widget.group.id, controller.text);
            ref.invalidate(productGroupsProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save Name'),
        ),
        const SizedBox(height: 20),
        for (final member in widget.group.members)
          ListTile(
            title: Text(member.vendorName),
            subtitle: Text(member.description),
          ),
      ],
    ),
  );
}
