import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';

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
        data: (value) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: value.locations.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final location = value.locations[index];
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
                leading: Icon(
                  active ? Icons.check_circle : Icons.storefront_outlined,
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
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
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
  );
}
