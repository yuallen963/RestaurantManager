import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import 'foundation.dart';

class InvoiceEmailScreen extends ConsumerWidget {
  const InvoiceEmailScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Email')),
      body: location == null
          ? const EmptyState(message: 'No restaurant locations available')
          : ref
                .watch(invoiceEmailAddressProvider)
                .when(
                  loading: () => const LoadingState(
                    label: 'Loading forwarding address...',
                  ),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load invoice forwarding address',
                    onRetry: () => ref.invalidate(invoiceEmailAddressProvider),
                  ),
                  data: (address) => ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        location.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Invoice forwarding address',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        address,
                        key: const Key('invoice-email-address'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('copy-invoice-email'),
                              onPressed: () async {
                                await ref
                                    .read(invoiceEmailActionsProvider)
                                    .copy(address);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Forwarding address copied',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy address'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('share-invoice-email'),
                              onPressed: () => ref
                                  .read(invoiceEmailActionsProvider)
                                  .share(address),
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Share address'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Forward vendor invoices to this address. PDF, JPG and PNG attachments will be added automatically.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Each supported attachment becomes a separate invoice. Keep attachments at or below 15 MB.',
                      ),
                    ],
                  ),
                ),
    );
  }
}
