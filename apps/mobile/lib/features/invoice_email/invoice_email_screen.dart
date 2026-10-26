import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show demoModeProvider;
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import 'foundation.dart';

class InvoiceEmailScreen extends ConsumerWidget {
  const InvoiceEmailScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    final demoMode = ref.watch(demoModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Email')),
      body: location == null
          ? const EmptyState(message: 'No restaurant locations available')
          : demoMode
          ? const _DemoInvoiceEmailState()
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

class _DemoInvoiceEmailState extends StatelessWidget {
  const _DemoInvoiceEmailState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mark_email_unread_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Invoice email is available in a private account',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'The public demo does not expose a forwarding address. Open Private Account from More to use your restaurant’s secure invoice email.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
