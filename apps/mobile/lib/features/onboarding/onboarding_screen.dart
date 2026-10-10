import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show Home;
import '../banking/bank_screens.dart';
import '../dashboard/foundation.dart';
import '../invoices/foundation.dart';
import '../invoices/invoice_screens.dart';
import '../pos/pos_integrations_screen.dart';
import 'foundation.dart';

// ignore_for_file: curly_braces_in_flow_control_structures

class Onboarding extends ConsumerStatefulWidget {
  const Onboarding({super.key});
  @override
  ConsumerState<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<Onboarding> {
  final formKey = GlobalKey<FormState>();
  final organization = TextEditingController(),
      location = TextEditingController(),
      address = TextEditingController(),
      city = TextEditingController(),
      stateName = TextEditingController(),
      zip = TextEditingController();
  int step = 1;
  bool loading = true, busy = false;
  String timezone = 'America/Detroit';
  String? error;
  final sources = <String>{'INVOICES'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(onboardingRepositoryProvider).get();
      if (!mounted) return;
      if (saved.completed) {
        _goHome();
        return;
      }
      setState(() {
        step = saved.currentStep.clamp(1, 6);
        if (saved.selectedDataSources.isNotEmpty) {
          sources
            ..clear()
            ..addAll(saved.selectedDataSources);
        }
        organization.text = saved.organizationName ?? '';
        location.text = saved.locationName ?? '';
        loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Unable to load setup. Please try again.';
        });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(() => error = 'Unable to save setup. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _advance(int next) => _run(() async {
    await ref
        .read(onboardingRepositoryProvider)
        .progress(next, sources.toList());
    if (mounted) setState(() => step = next);
  });
  Future<void> _saveRestaurant() async {
    if (!formKey.currentState!.validate()) return;
    await _run(() async {
      await ref.read(onboardingRepositoryProvider).setup({
        'organizationName': organization.text.trim(),
        'locationName': location.text.trim(),
        'addressLine1': address.text.trim(),
        'city': city.text.trim(),
        'state': stateName.text.trim(),
        'postalCode': zip.text.trim(),
        'timezone': timezone,
      });
      ref.invalidate(activeLocationControllerProvider);
      await ref.read(activeLocationControllerProvider.future);
      if (mounted) setState(() => step = 3);
    });
  }

  Future<void> _finish() => _run(() async {
    await ref.read(onboardingRepositoryProvider).complete();
    ref.invalidate(onboardingStateProvider);
    ref.invalidate(activeLocationControllerProvider);
    if (mounted) _goHome();
  });
  void _goHome() => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const Home()),
    (_) => false,
  );

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        leading: step > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: busy ? null : () => setState(() => step--),
              )
            : null,
        title: const Text('Set up ProfitLens'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: step / 6),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _content(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null) ...[
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 16),
      ],
      if (step == 1) _welcome(),
      if (step == 2) _restaurant(),
      if (step == 3) _dataSources(),
      if (step == 4) _invoices(),
      if (step == 5) _connections(),
      if (step == 6) _finishView(),
    ],
  );
  Widget _welcome() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('ProfitLens', style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 32),
      Text(
        'Find the costs quietly eating your restaurant’s margin.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 16),
      const Text(
        'Track vendor price increases, understand where costs are rising, and see what deserves your attention.',
      ),
      const SizedBox(height: 32),
      FilledButton(
        onPressed: busy ? null : () => _advance(2),
        child: const Text('Get Started'),
      ),
    ],
  );
  Widget _restaurant() => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tell us about your restaurant',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        _field(organization, 'Organization / business name'),
        _field(location, 'Restaurant location name'),
        _field(address, 'Street address', optional: true),
        Row(
          children: [
            Expanded(child: _field(city, 'City', optional: true)),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: _field(stateName, 'State', optional: true),
            ),
          ],
        ),
        _field(zip, 'ZIP code', optional: true),
        DropdownButtonFormField(
          initialValue: timezone,
          decoration: const InputDecoration(labelText: 'Time zone'),
          items: const [
            DropdownMenuItem(value: 'America/Detroit', child: Text('Eastern')),
            DropdownMenuItem(value: 'America/Chicago', child: Text('Central')),
            DropdownMenuItem(value: 'America/Denver', child: Text('Mountain')),
            DropdownMenuItem(
              value: 'America/Los_Angeles',
              child: Text('Pacific'),
            ),
          ],
          onChanged: (value) => setState(() => timezone = value!),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : _saveRestaurant,
          child: Text(busy ? 'Saving...' : 'Continue'),
        ),
      ],
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: optional
          ? null
          : (value) => (value ?? '').trim().length < 2 ? 'Enter $label' : null,
    ),
  );
  Widget _dataSources() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'How would you like ProfitLens to learn about your restaurant?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      _source(
        'INVOICES',
        'Invoices',
        'Upload or forward vendor invoices to track item-level costs and price changes.',
      ),
      _source(
        'POS',
        'POS',
        'Connect your point-of-sale system to bring in sales automatically.',
      ),
      _source(
        'BANK',
        'Bank',
        'Connect a business bank account to help categorize spending and reconcile purchases.',
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy
            ? null
            : () => _advance(sources.contains('INVOICES') ? 4 : 5),
        child: const Text('Continue'),
      ),
    ],
  );
  Widget _source(String value, String title, String subtitle) =>
      CheckboxListTile(
        value: sources.contains(value),
        title: Text(title),
        subtitle: Text(subtitle),
        contentPadding: EdgeInsets.zero,
        onChanged: (selected) => setState(
          () => selected! ? sources.add(value) : sources.remove(value),
        ),
      );
  Widget _invoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Upload a few recent vendor invoices',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text(
        '3–5 recent invoices gives ProfitLens enough history to start spotting price changes.',
      ),
      const SizedBox(height: 20),
      Consumer(
        builder: (context, ref, child) => ref
            .watch(invoiceListProvider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) =>
                  const Text('Your invoices remain available after upload.'),
              data: (items) => Column(
                children: [
                  for (final item in items.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(item.fileName),
                      trailing: Text(
                        item.extractionStatus.replaceAll('_', ' '),
                      ),
                    ),
                ],
              ),
            ),
      ),
      FilledButton.icon(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InvoiceUploadScreen()),
          );
          ref.invalidate(invoiceListProvider);
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Invoice'),
      ),
      TextButton(
        onPressed: busy ? null : () => _advance(5),
        child: const Text('Skip for now'),
      ),
      OutlinedButton(
        onPressed: busy ? null : () => _advance(5),
        child: const Text('Continue'),
      ),
    ],
  );
  Widget _connections() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Optional connections',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text('You can set these up now or come back later.'),
      const SizedBox(height: 20),
      if (sources.contains('POS'))
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PosIntegrationsScreen()),
          ),
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Set up POS'),
        ),
      if (sources.contains('BANK'))
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BankAccountsScreen()),
          ),
          icon: const Icon(Icons.account_balance),
          label: const Text('Connect Bank'),
        ),
      if (!sources.contains('POS') && !sources.contains('BANK'))
        const Text('No optional connections selected.'),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: busy ? null : () => _advance(6),
        child: const Text('Continue'),
      ),
      TextButton(
        onPressed: busy ? null : () => _advance(6),
        child: const Text('Set up later'),
      ),
    ],
  );
  Widget _finishView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'You’re ready to start.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 24),
      const ListTile(
        leading: Icon(Icons.check_circle),
        title: Text('Restaurant created'),
      ),
      const ListTile(
        leading: Icon(Icons.check_circle),
        title: Text('Location created'),
      ),
      if (sources.contains('INVOICES'))
        const ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('First invoices uploaded (if applicable)'),
        ),
      if (sources.contains('POS'))
        const ListTile(
          leading: Icon(Icons.circle_outlined),
          title: Text('Connect POS'),
        ),
      if (sources.contains('BANK'))
        const ListTile(
          leading: Icon(Icons.circle_outlined),
          title: Text('Connect bank'),
        ),
      if (sources.contains('INVOICES'))
        const ListTile(
          leading: Icon(Icons.circle_outlined),
          title: Text('Forward invoices by email'),
        ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: busy ? null : _finish,
        child: Text(busy ? 'Finishing...' : 'Go to Dashboard'),
      ),
    ],
  );
}
