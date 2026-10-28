import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../design/fundwell_theme.dart';
import '../responsive.dart';

class LocationManagementScreen extends ConsumerWidget {
  const LocationManagementScreen({required this.canManage, super.key});
  final bool canManage;

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    RestaurantLocation? location,
  }) async {
    final saved = await Navigator.push<RestaurantLocation>(
      context,
      MaterialPageRoute(builder: (_) => LocationFormScreen(location: location)),
    );
    if (saved == null) return;
    await ref
        .read(activeLocationControllerProvider.notifier)
        .reload(preferredLocationId: saved.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeLocationStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Restaurant Locations')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('add-location'),
              onPressed: () => _openForm(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Location'),
            )
          : null,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.tonal(
            onPressed: () =>
                ref.read(activeLocationControllerProvider.notifier).reload(),
            child: const Text('Retry'),
          ),
        ),
        data: (value) => ResponsiveContent(
          maxWidth: 1000,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
            itemCount: value.locations.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restaurant locations',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        canManage
                            ? 'Add, update, and choose the active restaurant location.'
                            : 'Choose the restaurant location you want to explore.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: FundWellTokens.mutedInk,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final location = value.locations[index - 1];
              final active = location.id == value.active?.id;
              final address = [
                location.addressLine1,
                [
                  location.city,
                  location.state,
                  location.postalCode,
                ].where((part) => part?.isNotEmpty == true).join(' '),
              ].where((part) => part?.isNotEmpty == true).join('\n');
              return Card(
                child: ListTile(
                  key: ValueKey('managed-location-${location.id}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: Icon(
                    active ? Icons.check_circle : Icons.storefront_outlined,
                    color: active
                        ? FundWellTokens.positive
                        : FundWellTokens.purple,
                  ),
                  title: Text(location.name),
                  subtitle: Text(
                    [
                      if (active) 'Active location',
                      if (address.isNotEmpty) address,
                      location.timezone,
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: canManage
                      ? IconButton(
                          tooltip: 'Edit ${location.name}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () =>
                              _openForm(context, ref, location: location),
                        )
                      : null,
                  onTap: active
                      ? null
                      : () => ref
                            .read(activeLocationControllerProvider.notifier)
                            .select(location),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class LocationFormScreen extends ConsumerStatefulWidget {
  const LocationFormScreen({this.location, super.key});
  final RestaurantLocation? location;

  @override
  ConsumerState<LocationFormScreen> createState() => _LocationFormScreenState();
}

class _LocationFormScreenState extends ConsumerState<LocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _postalCode;
  late final TextEditingController _timezone;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.location;
    _name = TextEditingController(text: value?.name ?? '');
    _address = TextEditingController(text: value?.addressLine1 ?? '');
    _city = TextEditingController(text: value?.city ?? '');
    _state = TextEditingController(text: value?.state ?? 'MI');
    _postalCode = TextEditingController(text: value?.postalCode ?? '');
    _timezone = TextEditingController(
      text: value?.timezone ?? 'America/Detroit',
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _city,
      _state,
      _postalCode,
      _timezone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = {
      'name': _name.text.trim(),
      'addressLine1': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim().toUpperCase(),
      'postalCode': _postalCode.text.trim(),
      'timezone': _timezone.text.trim(),
    };
    try {
      final repository = ref.read(locationsRepositoryProvider);
      final current = widget.location;
      final saved = current == null
          ? await repository.create(
              ref.read(activeLocationProvider)!.organizationId,
              data,
            )
          : await repository.update(current, data);
      if (mounted) Navigator.pop(context, saved);
    } on DioException catch (error) {
      setState(() {
        _saving = false;
        _error = error.response?.statusCode == 403
            ? 'You do not have permission to manage locations.'
            : 'Unable to save this location. Check the details and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.location == null ? 'Add Location' : 'Edit Location'),
    ),
    body: ResponsiveContent(
      maxWidth: 760,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              key: const Key('location-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Location name'),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  _required(value) ??
                  (value!.trim().length < 2
                      ? 'Enter at least 2 characters'
                      : null),
            ),
            TextFormField(
              key: const Key('location-address'),
              controller: _address,
              decoration: const InputDecoration(labelText: 'Street address'),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            TextFormField(
              key: const Key('location-city'),
              controller: _city,
              decoration: const InputDecoration(labelText: 'City'),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('location-state'),
                    controller: _state,
                    decoration: const InputDecoration(labelText: 'State'),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) =>
                        _required(value) ??
                        (RegExp(r'^[A-Za-z]{2}$').hasMatch(value!.trim())
                            ? null
                            : 'Use 2 letters'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: const Key('location-postal-code'),
                    controller: _postalCode,
                    decoration: const InputDecoration(labelText: 'ZIP code'),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        _required(value) ??
                        (RegExp(r'^\d{5}(-\d{4})?$').hasMatch(value!.trim())
                            ? null
                            : 'Enter a valid ZIP'),
                  ),
                ),
              ],
            ),
            TextFormField(
              key: const Key('location-timezone'),
              controller: _timezone,
              decoration: const InputDecoration(
                labelText: 'Time zone',
                helperText: 'Use an IANA time zone, such as America/Detroit',
              ),
              validator: _required,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save-location'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Location'),
            ),
          ],
        ),
      ),
    ),
  );
}
