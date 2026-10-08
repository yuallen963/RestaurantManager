import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart' show formatCurrency;
import '../expenses/foundation.dart';
import 'foundation.dart';

class InvoiceListScreen extends ConsumerWidget {
  const InvoiceListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    final invoices = ref.watch(invoiceListProvider);
    void openUpload() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InvoiceUploadScreen()),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      floatingActionButton: location == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('upload-invoice'),
              onPressed: openUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Invoice'),
            ),
      body: invoices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Unable to load invoices'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.invalidate(invoiceListProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No invoices uploaded yet.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: location == null ? null : openUpload,
                    child: const Text('Upload Invoice'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(invoiceListProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final invoice = items[index];
                return Card(
                  child: ListTile(
                    title: Text(invoice.vendorName ?? invoice.fileName),
                    subtitle: Text(
                      '${_date(invoice.invoiceDate ?? invoice.createdAt)}\n'
                      '${invoice.total == null ? 'Total not entered' : formatCurrency(invoice.total!)}',
                    ),
                    isThreeLine: true,
                    trailing: Chip(label: Text(_status(invoice.status))),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            InvoiceDetailScreen(invoiceId: invoice.id),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class InvoiceUploadScreen extends ConsumerWidget {
  const InvoiceUploadScreen({super.key});
  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final location = ref.read(activeLocationProvider);
    if (location == null) return;
    ref.read(invoiceUploadProvider.notifier).selecting();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null) {
      ref.read(invoiceUploadProvider.notifier).reset();
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    final mime = switch (file.extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => null,
    };
    if (bytes == null || mime == null) {
      ref.read(invoiceUploadProvider.notifier).reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a PDF, JPG, JPEG, or PNG file.'),
          ),
        );
      }
      return;
    }
    if (bytes.length > 15 * 1024 * 1024) {
      ref.read(invoiceUploadProvider.notifier).reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invoice files must be 15 MB or smaller.'),
          ),
        );
      }
      return;
    }
    final invoice = await ref
        .read(invoiceUploadProvider.notifier)
        .upload(
          locationId: location.id,
          fileName: file.name,
          mimeType: mime,
          bytes: bytes,
        );
    if (invoice != null && context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => InvoiceEditScreen(invoice: invoice)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(invoiceUploadProvider);
    final busy =
        state.phase == InvoiceUploadPhase.selecting ||
        state.phase == InvoiceUploadPhase.uploading;
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Invoice')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 72),
            const SizedBox(height: 20),
            const Text(
              'Choose a PDF or invoice photo. Maximum file size: 15 MB.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (state.phase == InvoiceUploadPhase.uploading) ...[
              LinearProgressIndicator(
                value: state.progress == 0 ? null : state.progress,
              ),
              const SizedBox(height: 8),
              const Text('Uploading...', textAlign: TextAlign.center),
            ],
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: busy ? null : () => _pick(context, ref),
              icon: const Icon(Icons.attach_file),
              label: Text(busy ? 'Please wait...' : 'Select File or Photo'),
            ),
          ],
        ),
      ),
    );
  }
}

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({required this.invoiceId, super.key});
  final String invoiceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Invoice Details')),
    body: ref
        .watch(invoiceDetailProvider(invoiceId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Unable to load invoice')),
          data: (invoice) {
            final rows = <MapEntry<String, String>>[
              MapEntry('Vendor', invoice.vendorName ?? 'Not selected'),
              MapEntry(
                'Invoice number',
                invoice.invoiceNumber ?? 'Not entered',
              ),
              MapEntry(
                'Invoice date',
                invoice.invoiceDate == null
                    ? 'Not entered'
                    : _date(invoice.invoiceDate!),
              ),
              MapEntry(
                'Subtotal',
                invoice.subtotal == null
                    ? 'Not entered'
                    : formatCurrency(invoice.subtotal!),
              ),
              MapEntry(
                'Tax',
                invoice.tax == null
                    ? 'Not entered'
                    : formatCurrency(invoice.tax!),
              ),
              MapEntry(
                'Total',
                invoice.total == null
                    ? 'Not entered'
                    : formatCurrency(invoice.total!),
              ),
              MapEntry('File', invoice.fileName),
              MapEntry('File type', invoice.fileType),
              MapEntry('File size', _size(invoice.fileSize)),
              MapEntry('Uploaded', _date(invoice.createdAt)),
              MapEntry('Status', _status(invoice.status)),
              MapEntry('Notes', invoice.notes ?? 'None'),
            ];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final row in rows)
                  ListTile(title: Text(row.key), subtitle: Text(row.value)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InvoiceEditScreen(invoice: invoice),
                      ),
                    );
                    ref.invalidate(invoiceDetailProvider(invoiceId));
                  },
                  child: const Text('Edit Metadata'),
                ),
                OutlinedButton(
                  onPressed: () => _delete(context, ref, invoice),
                  child: const Text('Delete Invoice'),
                ),
              ],
            );
          },
        ),
  );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    InvoiceRecord invoice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: const Text('This removes the invoice and its uploaded file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(invoiceRepositoryProvider).delete(invoice.id);
      ref.invalidate(invoiceListProvider);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class InvoiceEditScreen extends ConsumerStatefulWidget {
  const InvoiceEditScreen({required this.invoice, super.key});
  final InvoiceRecord invoice;
  @override
  ConsumerState<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends ConsumerState<InvoiceEditScreen> {
  final formKey = GlobalKey<FormState>();
  late final number = TextEditingController(text: widget.invoice.invoiceNumber);
  late final subtotal = TextEditingController(
    text: widget.invoice.subtotal?.toStringAsFixed(2),
  );
  late final tax = TextEditingController(
    text: widget.invoice.tax?.toStringAsFixed(2),
  );
  late final total = TextEditingController(
    text: widget.invoice.total?.toStringAsFixed(2),
  );
  late final notes = TextEditingController(text: widget.invoice.notes);
  String? vendorId;
  DateTime? date;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    vendorId = widget.invoice.vendorId;
    date = widget.invoice.invoiceDate;
  }

  String? validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value);
    return parsed == null || parsed < 0
        ? 'Enter a valid non-negative amount'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final vendors =
        ref.watch(expenseLookupsProvider).valueOrNull?.vendors ??
        const <ExpenseVendorOption>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Metadata')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String?>(
              initialValue: vendorId,
              decoration: const InputDecoration(labelText: 'Vendor'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No vendor')),
                ...vendors.map(
                  (vendor) => DropdownMenuItem(
                    value: vendor.id,
                    child: Text(vendor.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => vendorId = value),
            ),
            TextFormField(
              controller: number,
              decoration: const InputDecoration(labelText: 'Invoice number'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invoice date'),
              subtitle: Text(date == null ? 'Not entered' : _date(date!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            for (final field in [
              MapEntry('Subtotal', subtotal),
              MapEntry('Tax', tax),
              MapEntry('Total', total),
            ])
              TextFormField(
                controller: field.value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: field.key,
                  prefixText: r'$',
                ),
                validator: validateAmount,
              ),
            TextFormField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving...' : 'Save Metadata'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: date ?? DateTime.now(),
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    await ref.read(invoiceRepositoryProvider).update(widget.invoice.id, {
      'vendorId': vendorId,
      'invoiceNumber': number.text.trim().isEmpty ? null : number.text.trim(),
      'invoiceDate': date?.toIso8601String(),
      'subtotal': subtotal.text.trim().isEmpty ? null : subtotal.text.trim(),
      'tax': tax.text.trim().isEmpty ? null : tax.text.trim(),
      'total': total.text.trim().isEmpty ? null : total.text.trim(),
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      'status': 'COMPLETED',
    });
    ref.invalidate(invoiceListProvider);
    ref.invalidate(invoiceDetailProvider(widget.invoice.id));
    if (mounted) Navigator.pop(context);
  }
}

String _date(DateTime value) {
  const months = [
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
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _status(String value) => value
    .toLowerCase()
    .split('_')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _size(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(1)} KB';
