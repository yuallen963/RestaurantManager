import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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
                      '${invoice.ingestionSource == 'EMAIL_FORWARD' ? 'Email' : 'Manual Upload'} • ${_date(invoice.invoiceDate ?? invoice.createdAt)}\n'
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

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
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
    if (!context.mounted) return;
    await _upload(
      context,
      ref,
      fileName: file.name,
      extension: file.extension,
      bytes: file.bytes,
    );
  }

  Future<void> _pickPhoto(BuildContext context, WidgetRef ref) async {
    ref.read(invoiceUploadProvider.notifier).selecting();
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) {
      ref.read(invoiceUploadProvider.notifier).reset();
      return;
    }
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    await _upload(
      context,
      ref,
      fileName: file.name,
      extension: file.name.split('.').last,
      bytes: bytes,
    );
  }

  Future<void> _upload(
    BuildContext context,
    WidgetRef ref, {
    required String fileName,
    required String? extension,
    required List<int>? bytes,
  }) async {
    final location = ref.read(activeLocationProvider);
    if (location == null) {
      ref.read(invoiceUploadProvider.notifier).reset();
      return;
    }
    final mime = switch (extension?.toLowerCase()) {
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
          fileName: fileName,
          mimeType: mime,
          bytes: Uint8List.fromList(bytes),
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
              onPressed: busy ? null : () => _pickFile(context, ref),
              icon: const Icon(Icons.attach_file),
              label: Text(busy ? 'Please wait...' : 'Select PDF or Image File'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _pickPhoto(context, ref),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose Photo'),
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
              MapEntry(
                'Source',
                invoice.ingestionSource == 'EMAIL_FORWARD'
                    ? 'Email'
                    : 'Manual Upload',
              ),
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
              MapEntry('Extraction', _status(invoice.extractionStatus)),
              MapEntry('Review', _status(invoice.reviewStatus)),
              MapEntry('Notes', invoice.notes ?? 'None'),
            ];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final row in rows)
                  ListTile(title: Text(row.key), subtitle: Text(row.value)),
                if (invoice.extractionStatus == 'PROCESSING') ...[
                  const LinearProgressIndicator(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Processing invoice extraction...'),
                  ),
                ],
                if (invoice.extractionStatus == 'FAILED') ...[
                  Text(
                    invoice.extractionError ?? 'Extraction failed',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (invoice.extractionStatus == 'NOT_STARTED' ||
                    invoice.extractionStatus == 'FAILED')
                  FilledButton.icon(
                    onPressed: ref.watch(invoiceExtractionProvider).isLoading
                        ? null
                        : () => ref
                              .read(invoiceExtractionProvider.notifier)
                              .extract(invoice.id),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(
                      invoice.extractionStatus == 'FAILED'
                          ? 'Retry Extraction'
                          : 'Extract Invoice',
                    ),
                  ),
                if (invoice.extractionStatus == 'COMPLETED')
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              InvoiceReviewScreen(invoiceId: invoice.id),
                        ),
                      );
                      ref.invalidate(invoiceDetailProvider(invoiceId));
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      invoice.reviewStatus == 'REVIEWED'
                          ? 'View Reviewed Invoice'
                          : 'Review Extracted Invoice',
                    ),
                  ),
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

class InvoiceReviewScreen extends ConsumerWidget {
  const InvoiceReviewScreen({required this.invoiceId, super.key});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(invoiceDetailProvider(invoiceId));
    final lineItems = ref.watch(invoiceLineItemsProvider(invoiceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Review Invoice')),
      body: invoice.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Unable to load invoice')),
        data: (data) => lineItems.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Unable to load line items')),
          data: (items) {
            final issueCount = [
              if (data.vendorName == null) 'vendor',
              if (data.invoiceDate == null) 'date',
              if (data.total == null) 'total',
              ...items
                  .where((item) => item.lowConfidence)
                  .map((item) => item.id),
            ].length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: issueCount > 0
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    leading: Icon(
                      issueCount > 0
                          ? Icons.warning_amber
                          : Icons.check_circle_outline,
                    ),
                    title: Text(
                      data.reviewStatus == 'REVIEWED'
                          ? 'Reviewed'
                          : issueCount > 0
                          ? 'Needs review'
                          : 'Ready for review',
                    ),
                    subtitle: Text(
                      issueCount == 1
                          ? '1 field needs attention'
                          : '$issueCount fields need attention',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Invoice Summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ListTile(
                  title: const Text('Vendor'),
                  subtitle: Text(data.vendorName ?? 'Missing'),
                ),
                ListTile(
                  title: const Text('Invoice number'),
                  subtitle: Text(data.invoiceNumber ?? 'Missing'),
                ),
                ListTile(
                  title: const Text('Invoice date'),
                  subtitle: Text(
                    data.invoiceDate == null
                        ? 'Missing'
                        : _date(data.invoiceDate!),
                  ),
                ),
                ListTile(
                  title: const Text('Subtotal'),
                  subtitle: Text(
                    data.subtotal == null
                        ? 'Missing'
                        : formatCurrency(data.subtotal!),
                  ),
                ),
                ListTile(
                  title: const Text('Tax'),
                  subtitle: Text(
                    data.tax == null ? 'Missing' : formatCurrency(data.tax!),
                  ),
                ),
                ListTile(
                  title: const Text('Total'),
                  subtitle: Text(
                    data.total == null
                        ? 'Missing'
                        : formatCurrency(data.total!),
                  ),
                ),
                if (data.extractionConfidence != null)
                  ListTile(
                    title: const Text('Extraction confidence'),
                    subtitle: Text(
                      '${(data.extractionConfidence! * 100).toStringAsFixed(0)}%',
                    ),
                  ),
                if (data.reviewStatus != 'REVIEWED')
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoiceEditScreen(
                            invoice: data,
                            reviewMode: true,
                          ),
                        ),
                      );
                      ref.invalidate(invoiceDetailProvider(invoiceId));
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Invoice Fields'),
                  ),
                const Divider(height: 32),
                Text(
                  'Extracted Line Items',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No line items were extracted.'),
                  ),
                for (final item in items)
                  Card(
                    color: item.lowConfidence
                        ? Theme.of(context).colorScheme.errorContainer
                        : null,
                    child: InkWell(
                      onTap: data.reviewStatus == 'REVIEWED'
                          ? null
                          : () => _editLine(context, ref, data, item),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.rawDescription,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                if (data.reviewStatus != 'REVIEWED')
                                  const Icon(Icons.edit_outlined),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              [
                                if (item.sku != null) 'SKU: ${item.sku}',
                                'Quantity: ${item.quantity?.toString() ?? 'Missing'} ${item.unit ?? ''}',
                                if (item.packSize != null)
                                  'Pack: ${item.packSize}',
                                'Unit price: ${item.unitPrice == null ? 'Missing' : formatCurrency(item.unitPrice!)}',
                                'Extended: ${item.extendedPrice == null ? 'Missing' : formatCurrency(item.extendedPrice!)}',
                                'Confidence: ${item.lowConfidence
                                    ? 'Low'
                                    : (item.confidence ?? 0) < .9
                                    ? 'Medium'
                                    : 'High'}',
                              ].join('\n'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (data.reviewStatus != 'REVIEWED')
                  FilledButton.icon(
                    onPressed: () => _markReviewed(context, ref, data),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark Reviewed'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _markReviewed(
    BuildContext context,
    WidgetRef ref,
    InvoiceRecord invoice,
  ) async {
    try {
      await ref.read(invoiceRepositoryProvider).review(invoice.id, {
        'markReviewed': true,
      });
      ref.invalidate(invoiceDetailProvider(invoice.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice marked reviewed')),
        );
      }
    } on DioException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.response?.data is Map
                  ? (error.response?.data['message']?.toString() ??
                        'Unable to mark reviewed')
                  : 'Unable to mark reviewed',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editLine(
    BuildContext context,
    WidgetRef ref,
    InvoiceRecord invoice,
    InvoiceLineItem item,
  ) async {
    final description = TextEditingController(text: item.rawDescription);
    final sku = TextEditingController(text: item.sku);
    final quantity = TextEditingController(text: item.quantity?.toString());
    final unit = TextEditingController(text: item.unit);
    final pack = TextEditingController(text: item.packSize);
    final unitPrice = TextEditingController(
      text: item.unitPrice?.toStringAsFixed(2),
    );
    final extended = TextEditingController(
      text: item.extendedPrice?.toStringAsFixed(2),
    );
    final category = TextEditingController(text: item.category);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Line Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in <MapEntry<String, TextEditingController>>[
                MapEntry('Description', description),
                MapEntry('SKU', sku),
                MapEntry('Quantity', quantity),
                MapEntry('Unit', unit),
                MapEntry('Pack size', pack),
                MapEntry('Unit price', unitPrice),
                MapEntry('Extended price', extended),
                MapEntry('Category', category),
              ])
                TextField(
                  controller: field.value,
                  decoration: InputDecoration(labelText: field.key),
                  keyboardType:
                      [
                        'Quantity',
                        'Unit price',
                        'Extended price',
                      ].contains(field.key)
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    double? number(TextEditingController controller) =>
        controller.text.trim().isEmpty
        ? null
        : double.tryParse(controller.text.trim());
    await ref.read(invoiceRepositoryProvider).updateLineItem(
      invoice.id,
      item.id,
      {
        'rawDescription': description.text.trim(),
        'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
        'quantity': number(quantity),
        'unit': unit.text.trim().isEmpty ? null : unit.text.trim(),
        'packSize': pack.text.trim().isEmpty ? null : pack.text.trim(),
        'unitPrice': number(unitPrice),
        'extendedPrice': number(extended),
        'category': category.text.trim().isEmpty ? null : category.text.trim(),
      },
    );
    ref.invalidate(invoiceLineItemsProvider(invoice.id));
  }
}

class InvoiceEditScreen extends ConsumerStatefulWidget {
  const InvoiceEditScreen({
    required this.invoice,
    this.reviewMode = false,
    super.key,
  });
  final InvoiceRecord invoice;
  final bool reviewMode;
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
  late final vendorName = TextEditingController(
    text: widget.invoice.vendorName,
  );
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
            if (widget.reviewMode)
              TextFormField(
                controller: vendorName,
                decoration: const InputDecoration(labelText: 'Vendor name'),
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
    final payload = {
      'vendorId': vendorId,
      if (widget.reviewMode)
        'vendorName': vendorName.text.trim().isEmpty
            ? null
            : vendorName.text.trim(),
      'invoiceNumber': number.text.trim().isEmpty ? null : number.text.trim(),
      'invoiceDate': date?.toIso8601String(),
      'subtotal': subtotal.text.trim().isEmpty ? null : subtotal.text.trim(),
      'tax': tax.text.trim().isEmpty ? null : tax.text.trim(),
      'total': total.text.trim().isEmpty ? null : total.text.trim(),
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      'status': 'COMPLETED',
    };
    if (widget.reviewMode) {
      await ref
          .read(invoiceRepositoryProvider)
          .review(widget.invoice.id, payload);
    } else {
      await ref
          .read(invoiceRepositoryProvider)
          .update(widget.invoice.id, payload);
    }
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
