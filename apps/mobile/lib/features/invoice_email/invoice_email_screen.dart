import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show demoModeProvider;
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import '../design/fundwell_theme.dart';
import '../responsive.dart';
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
                  data: (address) => ResponsiveContent(
                    maxWidth: 920,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          'Forward invoices automatically',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          location.name,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: FundWellTokens.purple),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Use this secure address for ${location.name}. Supported attachments are added to your invoice workspace.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: FundWellTokens.mutedInk),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your forwarding address',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: FundWellTokens.mutedInk,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  address,
                                  key: const Key('invoice-email-address'),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: FundWellTokens.purple),
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.icon(
                                      key: const Key('copy-invoice-email'),
                                      onPressed: () async {
                                        await ref
                                            .read(invoiceEmailActionsProvider)
                                            .copy(address);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
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
                                    OutlinedButton.icon(
                                      key: const Key('share-invoice-email'),
                                      onPressed: () => ref
                                          .read(invoiceEmailActionsProvider)
                                          .share(address),
                                      icon: const Icon(Icons.share_outlined),
                                      label: const Text('Share address'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Card(
                          color: FundWellTokens.surfaceSubtle,
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: FundWellTokens.purple,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Forward vendor invoices as PDF, JPG and PNG attachments. Each supported attachment becomes a separate invoice and must be 15 MB or smaller.',
                                  ),
                                ),
                              ],
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

class _DemoInvoiceEmailState extends StatelessWidget {
  const _DemoInvoiceEmailState();

  @override
  Widget build(BuildContext context) => ResponsiveContent(
    maxWidth: 720,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
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
        ),
      ),
    ),
  );
}
