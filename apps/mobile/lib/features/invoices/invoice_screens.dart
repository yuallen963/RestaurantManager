import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show demoModeProvider;
import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart' show formatCurrency;
import '../design/fundwell_theme.dart';
import '../expenses/foundation.dart';
import '../needs_attention/foundation.dart';
import '../price_intelligence/foundation.dart';
import 'foundation.dart';
import 'invoice_upload.dart';
import '../responsive.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  final searchController = TextEditingController();
  String search = '';
  String status = 'ALL';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(activeLocationProvider);
    final invoices = ref.watch(invoiceListProvider);
    final readOnly = ref.watch(demoModeProvider);
    void openUpload() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InvoiceUploadScreen()),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      floatingActionButton: location == null || readOnly
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(28, 8, 28, 0),
                    child: Text(
                      'Bank activity can show payments, but invoice uploads add item-level pricing, package sizes, and vendor cost intelligence.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!readOnly)
                    FilledButton(
                      onPressed: location == null ? null : openUpload,
                      child: const Text('Upload Invoice'),
                    )
                  else
                    const _DemoInvoiceNotice(),
                ],
              ),
            );
          }
          final visible = items.where((invoice) {
            final query = search.trim().toLowerCase();
            final matchesSearch =
                query.isEmpty ||
                (invoice.vendorName ?? '').toLowerCase().contains(query) ||
                (invoice.invoiceNumber ?? '').toLowerCase().contains(query) ||
                invoice.fileName.toLowerCase().contains(query);
            final matchesStatus =
                status == 'ALL' ||
                (status == 'NEEDS_REVIEW'
                    ? invoice.reviewStatus != 'REVIEWED'
                    : invoice.reviewStatus == 'REVIEWED');
            return matchesSearch && matchesStatus;
          }).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(invoiceListProvider.future),
            child: ResponsiveContent(
              maxWidth: 1240,
              child: ListView(
                padding: const EdgeInsets.all(FundWellTokens.space6),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invoice activity',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Review vendor bills, extracted details, and expense status.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (readOnly) const _ReadOnlyChip(),
                    ],
                  ),
                  if (readOnly) ...[
                    const SizedBox(height: FundWellTokens.space4),
                    const _DemoInvoiceNotice(),
                  ],
                  const SizedBox(height: FundWellTokens.space4),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: FundWellTokens.space2,
                      runSpacing: FundWellTokens.space2,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 700
                              ? constraints.maxWidth
                              : 420,
                          child: TextField(
                            key: const Key('invoice-search'),
                            controller: searchController,
                            onChanged: (value) =>
                                setState(() => search = value),
                            decoration: const InputDecoration(
                              hintText: 'Search vendor or invoice number',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'ALL', label: Text('All')),
                            ButtonSegment(
                              value: 'NEEDS_REVIEW',
                              label: Text('Needs Review'),
                            ),
                            ButtonSegment(
                              value: 'REVIEWED',
                              label: Text('Reviewed'),
                            ),
                          ],
                          selected: {status},
                          onSelectionChanged: (value) =>
                              setState(() => status = value.first),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: FundWellTokens.space4),
                  if (visible.isEmpty)
                    const _InvoiceFilteredEmptyState()
                  else
                    LayoutBuilder(
                      builder: (context, constraints) => Column(
                        children: [
                          if (constraints.maxWidth >= 900)
                            const _InvoiceTableHeader(),
                          for (final invoice in visible) ...[
                            _InvoiceRow(
                              invoice: invoice,
                              desktop: constraints.maxWidth >= 900,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InvoiceDetailScreen(
                                    invoiceId: invoice.id,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReadOnlyChip extends StatelessWidget {
  const _ReadOnlyChip();
  @override
  Widget build(BuildContext context) => const Chip(
    avatar: Icon(Icons.visibility_outlined, size: 17),
    label: Text('Demo · View only'),
  );
}

class _DemoInvoiceNotice extends StatelessWidget {
  const _DemoInvoiceNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: FundWellTokens.surfaceSubtle,
      borderRadius: BorderRadius.circular(FundWellTokens.radius),
      border: Border.all(color: FundWellTokens.outline),
    ),
    child: const Row(
      children: [
        Icon(Icons.visibility_outlined, size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Public demo is view only. Browse invoices and extracted details; uploads and financial changes are disabled.',
          ),
        ),
      ],
    ),
  );
}

class _InvoiceFilteredEmptyState extends StatelessWidget {
  const _InvoiceFilteredEmptyState();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: Text('No invoices match these filters.')),
    ),
  );
}

class _InvoiceTableHeader extends StatelessWidget {
  const _InvoiceTableHeader();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
    child: Row(
      children: [
        Expanded(flex: 4, child: Text('VENDOR / INVOICE')),
        Expanded(flex: 2, child: Text('INVOICE DATE')),
        Expanded(flex: 2, child: Text('STATUS')),
        SizedBox(width: 140, child: Text('AMOUNT', textAlign: TextAlign.right)),
        SizedBox(width: 28),
      ],
    ),
  );
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.desktop,
    required this.onTap,
  });
  final InvoiceRecord invoice;
  final bool desktop;
  final VoidCallback onTap;

  String get vendor => invoice.vendorName ?? invoice.fileName;
  String get source =>
      invoice.ingestionSource == 'EMAIL_FORWARD' ? 'Email' : 'Manual Upload';

  @override
  Widget build(BuildContext context) {
    final statusLabel = invoice.reviewStatus == 'REVIEWED'
        ? 'Reviewed'
        : invoice.extractionStatus == 'COMPLETED'
        ? 'Needs Review'
        : _status(invoice.status);
    final identifier = invoice.invoiceNumber == null
        ? '$source • ${_date(invoice.invoiceDate ?? invoice.createdAt)}'
        : 'Invoice ${invoice.invoiceNumber} · $source';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(FundWellTokens.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: desktop
              ? Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _InvoiceIdentity(
                        vendor: vendor,
                        detail: identifier,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _date(invoice.invoiceDate ?? invoice.createdAt),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _InvoiceStatus(label: statusLabel),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: Text(
                        invoice.total == null
                            ? 'Total not entered'
                            : formatCurrency(invoice.total!),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _InvoiceIdentity(
                            vendor: vendor,
                            detail: identifier,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          invoice.total == null
                              ? '—'
                              : formatCurrency(invoice.total!),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _InvoiceStatus(label: statusLabel),
                        Text(_date(invoice.invoiceDate ?? invoice.createdAt)),
                        Text(
                          invoice.paymentStatus == 'PAID'
                              ? 'Paid'
                              : 'Awaiting payment',
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _InvoiceIdentity extends StatelessWidget {
  const _InvoiceIdentity({required this.vendor, required this.detail});
  final String vendor, detail;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        vendor,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        detail,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _InvoiceStatus extends StatelessWidget {
  const _InvoiceStatus({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final needsReview = label == 'Needs Review';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: needsReview ? const Color(0xFFFFF4DF) : const Color(0xFFEAF6F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: needsReview ? FundWellTokens.warning : FundWellTokens.positive,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class InvoiceUploadScreen extends ConsumerWidget {
  const InvoiceUploadScreen({super.key});

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    ref.read(invoiceUploadProvider.notifier).selecting();
    try {
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
      final prepared = prepareInvoiceFile(
        originalName: file.name,
        bytes: file.bytes ?? Uint8List(0),
      );
      if (!context.mounted) return;
      await _upload(context, ref, file: prepared);
    } on InvoiceUploadFailure catch (error) {
      ref.read(invoiceUploadProvider.notifier).fail(error);
    } catch (_) {
      ref
          .read(invoiceUploadProvider.notifier)
          .fail(
            const InvoiceUploadFailure(
              InvoiceUploadErrorCategory.unreadablePhoto,
              'Unable to read the selected file. Please choose it again.',
              stage: 'file_read',
            ),
          );
    }
  }

  Future<void> _pickPhoto(BuildContext context, WidgetRef ref) async {
    ref.read(invoiceUploadProvider.notifier).selecting();
    try {
      final file = await ref.read(invoicePhotoSourceProvider).pick();
      if (file == null) {
        ref.read(invoiceUploadProvider.notifier).reset();
        return;
      }
      // Copy the temporary picker result into memory immediately. This avoids
      // losing access when iOS reclaims the security-scoped temporary file.
      final bytes = await file.readAsBytes();
      final prepared = prepareInvoiceFile(
        originalName: file.name,
        bytes: bytes,
        pickedFromPhotoLibrary: true,
      );
      logInvoiceUpload(
        stage: 'file_prepared',
        category: 'success',
        format: prepared.format,
        fileSize: prepared.bytes.length,
      );
      if (!context.mounted) return;
      await _upload(context, ref, file: prepared);
    } on InvoiceUploadFailure catch (error) {
      ref.read(invoiceUploadProvider.notifier).fail(error);
    } catch (_) {
      ref
          .read(invoiceUploadProvider.notifier)
          .fail(
            const InvoiceUploadFailure(
              InvoiceUploadErrorCategory.unreadablePhoto,
              'Unable to read the selected photo. Please choose it again.',
              stage: 'file_read',
            ),
          );
    }
  }

  Future<void> _upload(
    BuildContext context,
    WidgetRef ref, {
    required PreparedInvoiceFile file,
  }) async {
    final location = ref.read(activeLocationProvider);
    if (location == null) {
      ref.read(invoiceUploadProvider.notifier).reset();
      return;
    }
    final invoice = await ref
        .read(invoiceUploadProvider.notifier)
        .upload(
          locationId: location.id,
          fileName: file.fileName,
          mimeType: file.mimeType,
          bytes: file.bytes,
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

String _reconciliationMessage(String code) => switch (code) {
  'TOTAL_MISMATCH' => 'Invoice total may be incorrect.',
  'SUBTOTAL_MISMATCH' =>
    'Invoice subtotal does not match the sum of the line items.',
  'LINE_EXTENSION_MISMATCH' => 'One or more line-item totals may be incorrect.',
  'LINE_MATH_MISMATCH' =>
    'One or more item quantities and prices do not match the extended total.',
  _ => 'Some extracted values need review.',
};

String _uncertainFieldLabel(String field) => switch (field) {
  'TOTAL_MISMATCH' ||
  'SUBTOTAL_MISMATCH' ||
  'LINE_EXTENSION_MISMATCH' ||
  'LINE_MATH_MISMATCH' => _reconciliationMessage(field),
  'vendorName' => 'Vendor needs review',
  'invoiceNumber' => 'Invoice number needs review',
  'invoiceDate' => 'Invoice date needs review',
  'dueDate' => 'Due date needs review',
  'total' => 'Total needs review',
  'subtotal' => 'Subtotal needs review',
  _ => 'Extracted value needs review',
};

String _reconciliationAmount(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null) return value ?? 'Not available';
  final fixed = parsed.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${parsed < 0 ? '-' : ''}\$$whole.${parts.last}';
}

class _ReconciliationWarning extends StatelessWidget {
  const _ReconciliationWarning({required this.reconciliation});
  final InvoiceReconciliation? reconciliation;

  @override
  Widget build(BuildContext context) {
    if (reconciliation == null || !reconciliation!.hasDiscrepancy) {
      return const SizedBox.shrink();
    }
    final detailsByCode = <String, InvoiceReconciliationDetail>{
      for (final detail in reconciliation!.details) detail.code: detail,
    };
    final codes = <String>{
      ...reconciliation!.reasons,
      ...reconciliation!.details.map((detail) => detail.code),
    };
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Check invoice totals',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              "Some extracted values do not match FundWell's calculations. Review these fields before using this invoice for cost analysis.",
            ),
            for (final code in codes) ...[
              const SizedBox(height: 8),
              Text(_reconciliationMessage(code)),
              if (detailsByCode[code]?.expected != null &&
                  detailsByCode[code]?.actual != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${code == 'SUBTOTAL_MISMATCH' ? 'Extracted subtotal' : 'Extracted total'}: ${_reconciliationAmount(detailsByCode[code]!.expected)}\n'
                    '${code == 'SUBTOTAL_MISMATCH' ? 'Calculated line-item subtotal' : 'Calculated total'}: ${_reconciliationAmount(detailsByCode[code]!.actual)}',
                  ),
                ),
            ],
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
            final extractionState = ref.watch(invoiceExtractionProvider);
            final readOnly = ref.watch(demoModeProvider);
            return ResponsiveContent(
              maxWidth: 1120,
              child: ListView(
                padding: const EdgeInsets.all(FundWellTokens.space6),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.vendorName ?? 'Invoice details',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              invoice.invoiceNumber == null
                                  ? invoice.fileName
                                  : 'Invoice ${invoice.invoiceNumber}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (readOnly) const _ReadOnlyChip(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (readOnly) ...[
                    const _DemoInvoiceNotice(),
                    const SizedBox(height: 16),
                  ],
                  _ReconciliationWarning(
                    reconciliation: invoice.reconciliation,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice overview',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 28,
                            runSpacing: 18,
                            children: [
                              _InvoiceDetailField(
                                label: 'Source',
                                value:
                                    invoice.ingestionSource == 'EMAIL_FORWARD'
                                    ? 'Email'
                                    : 'Manual Upload',
                              ),
                              _InvoiceDetailField(
                                label: 'Invoice number',
                                value: invoice.invoiceNumber ?? 'Not entered',
                              ),
                              _InvoiceDetailField(
                                label: 'Invoice date',
                                value: invoice.invoiceDate == null
                                    ? 'Not entered'
                                    : _date(invoice.invoiceDate!),
                              ),
                              if (invoice.dueDate != null)
                                _InvoiceDetailField(
                                  label: 'Due date',
                                  value: _date(invoice.dueDate!),
                                ),
                              _InvoiceDetailField(
                                label: 'Status',
                                value: _status(invoice.status),
                              ),
                              _InvoiceDetailField(
                                label: 'Review',
                                value: _status(invoice.reviewStatus),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          Wrap(
                            spacing: 32,
                            runSpacing: 18,
                            children: [
                              _InvoiceDetailField(
                                label: 'Subtotal',
                                value: invoice.subtotal == null
                                    ? 'Not entered'
                                    : formatCurrency(invoice.subtotal!),
                              ),
                              _InvoiceDetailField(
                                label: 'Tax',
                                value: invoice.tax == null
                                    ? 'Not entered'
                                    : formatCurrency(invoice.tax!),
                              ),
                              _InvoiceDetailField(
                                label: 'Total',
                                value: invoice.total == null
                                    ? 'Not entered'
                                    : formatCurrency(invoice.total!),
                                emphasized: true,
                              ),
                              _InvoiceDetailField(
                                label: 'Payment status',
                                value: invoice.paymentStatus == 'PAID'
                                    ? 'Paid'
                                    : 'Awaiting payment',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (invoice.extractionStatus == 'PROCESSING') ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('Processing invoice extraction...'),
                        ],
                      ),
                    ),
                  ],
                  if (invoice.extractionStatus == 'FAILED') ...[
                    Text(
                      invoice.extractionError ??
                          'Unable to process this invoice. Retry or enter the fields manually.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (extractionState.hasError) ...[
                    Text(
                      'Unable to start extraction. Check the service configuration and try again later.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (!readOnly &&
                      (invoice.extractionStatus == 'NOT_STARTED' ||
                          (invoice.extractionStatus == 'FAILED' &&
                              invoice.canRetryExtraction)))
                    FilledButton.icon(
                      onPressed: extractionState.isLoading
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
                        readOnly || invoice.reviewStatus == 'REVIEWED'
                            ? 'View Reviewed Invoice'
                            : 'Review Extracted Invoice',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Original document',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          _InvoiceDetailField(
                            label: 'File',
                            value: invoice.fileName,
                            width: 320,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 24,
                            runSpacing: 12,
                            children: [
                              _InvoiceDetailField(
                                label: 'File type',
                                value: invoice.fileType,
                                width: 240,
                              ),
                              _InvoiceDetailField(
                                label: 'File size',
                                value: _size(invoice.fileSize),
                              ),
                              _InvoiceDetailField(
                                label: 'Uploaded',
                                value: _date(invoice.createdAt),
                              ),
                              _InvoiceDetailField(
                                label: 'Extraction',
                                value: _status(invoice.extractionStatus),
                              ),
                            ],
                          ),
                          if (invoice.notes != null) ...[
                            const Divider(height: 28),
                            _InvoiceDetailField(
                              label: 'Notes',
                              value: invoice.notes!,
                              width: 320,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!readOnly) ...[
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
                ],
              ),
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

class _InvoiceDetailField extends StatelessWidget {
  const _InvoiceDetailField({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.width,
  });
  final String label, value;
  final bool emphasized;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width ?? (emphasized ? 180 : 170),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: emphasized
              ? Theme.of(context).textTheme.headlineSmall
              : Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _ReviewFieldTile extends StatelessWidget {
  const _ReviewFieldTile({
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label, value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: emphasized
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
  );
}

class InvoiceReviewScreen extends ConsumerWidget {
  const InvoiceReviewScreen({required this.invoiceId, super.key});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(invoiceDetailProvider(invoiceId));
    final lineItems = ref.watch(invoiceLineItemsProvider(invoiceId));
    final readOnly = ref.watch(demoModeProvider);
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
              if (data.invoiceNumber == null) 'invoiceNumber',
              if (data.invoiceDate == null) 'date',
              if (data.total == null) 'total',
              ...data.uncertainFields,
              ...items
                  .where((item) => item.lowConfidence)
                  .map((item) => item.id),
            ].length;
            return ResponsiveContent(
              maxWidth: 1040,
              child: ListView(
                padding: const EdgeInsets.all(FundWellTokens.space6),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.vendorName ?? 'Review extracted invoice',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              'Compare extracted values with the original document before confirming.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (readOnly) const _ReadOnlyChip(),
                    ],
                  ),
                  if (readOnly) ...[
                    const SizedBox(height: 16),
                    const _DemoInvoiceNotice(),
                  ],
                  const SizedBox(height: 16),
                  _ReconciliationWarning(reconciliation: data.reconciliation),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice Summary',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 20,
                            runSpacing: 20,
                            children: [
                              _ReviewFieldTile(
                                label: 'Vendor',
                                value: _reviewFieldValue(
                                  data,
                                  'vendorName',
                                  data.vendorName,
                                  data.uncertainFields.contains('vendorName'),
                                ),
                              ),
                              if (data.vendorAddress != null)
                                _ReviewFieldTile(
                                  label: 'Vendor address',
                                  value: data.vendorAddress!,
                                ),
                              _ReviewFieldTile(
                                label: 'Invoice number',
                                value: _reviewFieldValue(
                                  data,
                                  'invoiceNumber',
                                  data.invoiceNumber,
                                  data.uncertainFields.contains(
                                    'invoiceNumber',
                                  ),
                                ),
                              ),
                              _ReviewFieldTile(
                                label: 'Invoice date',
                                value: _reviewFieldValue(
                                  data,
                                  'invoiceDate',
                                  data.invoiceDate == null
                                      ? null
                                      : _date(data.invoiceDate!),
                                  data.uncertainFields.contains('invoiceDate'),
                                ),
                              ),
                              if (data.dueDate != null)
                                _ReviewFieldTile(
                                  label: 'Due date',
                                  value: _reviewFieldValue(
                                    data,
                                    'dueDate',
                                    _date(data.dueDate!),
                                    data.uncertainFields.contains('dueDate'),
                                  ),
                                ),
                              _ReviewFieldTile(
                                label: 'Subtotal',
                                value: _reviewFieldValue(
                                  data,
                                  'subtotal',
                                  data.subtotal == null
                                      ? null
                                      : formatCurrency(data.subtotal!),
                                  data.uncertainFields.contains('subtotal'),
                                ),
                              ),
                              _ReviewFieldTile(
                                label: 'Tax',
                                value: _reviewFieldValue(
                                  data,
                                  'tax',
                                  data.tax == null
                                      ? null
                                      : formatCurrency(data.tax!),
                                  data.uncertainFields.contains('tax'),
                                ),
                              ),
                              _ReviewFieldTile(
                                label: 'Total',
                                value: _reviewFieldValue(
                                  data,
                                  'total',
                                  data.total == null
                                      ? null
                                      : formatCurrency(data.total!),
                                  data.uncertainFields.contains('total'),
                                ),
                                emphasized: true,
                              ),
                              _ReviewFieldTile(
                                label: 'Other fees',
                                value: _reviewFieldValue(
                                  data,
                                  'otherFees',
                                  data.otherFees == null
                                      ? null
                                      : formatCurrency(data.otherFees!),
                                  data.uncertainFields.contains('otherFees'),
                                ),
                              ),
                              _ReviewFieldTile(
                                label: 'Discount',
                                value: _reviewFieldValue(
                                  data,
                                  'discount',
                                  data.discount == null
                                      ? null
                                      : formatCurrency(data.discount!),
                                  data.uncertainFields.contains('discount'),
                                ),
                              ),
                              _ReviewFieldTile(
                                label: 'Currency',
                                value: _reviewFieldValue(
                                  data,
                                  'currency',
                                  data.currency,
                                  data.uncertainFields.contains('currency'),
                                ),
                              ),
                              if (data.extractionConfidence != null)
                                _ReviewFieldTile(
                                  label: 'Extraction confidence',
                                  value:
                                      '${(data.extractionConfidence! * 100).toStringAsFixed(0)}%',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!readOnly && data.reviewStatus != 'REVIEWED')
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
                        onTap: readOnly || data.reviewStatus == 'REVIEWED'
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
                                  if (!readOnly &&
                                      data.reviewStatus != 'REVIEWED')
                                    const Icon(Icons.edit_outlined),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  if (item.normalizedName != null)
                                    'Interpreted as: ${item.normalizedName}',
                                  if (item.sku != null) 'SKU: ${item.sku}',
                                  if (item.sourcePage != null)
                                    'Page: ${item.sourcePage}',
                                  'Quantity: ${item.quantity?.toString() ?? 'Missing'} ${item.unit ?? ''}',
                                  if (item.packSize != null)
                                    'Pack: ${item.packSize}',
                                  if (item.totalPackageQuantity != null)
                                    'Package total: ${item.totalPackageQuantity!.toStringAsFixed(1)} ${item.measurementUnit ?? ''}',
                                  'Unit price: ${item.unitPrice == null ? 'Missing' : formatCurrency(item.unitPrice!)}',
                                  'Extended: ${item.extendedPrice == null ? 'Missing' : formatCurrency(item.extendedPrice!)}',
                                  'Confidence: ${item.lowConfidence
                                      ? 'Low'
                                      : (item.confidence ?? 0) < .9
                                      ? 'Medium'
                                      : 'High'}',
                                  if (item.uncertainFields.isNotEmpty)
                                    'Check: ${item.uncertainFields.map(_uncertainFieldLabel).join(', ')}',
                                  if (item.fieldProvenance.values.any(
                                    (value) => value.kind == 'OBSERVED',
                                  ))
                                    'Evidence: page ${item.sourcePage ?? '?'} • confirm quantities and prices against the printed row',
                                  if (item.productAttributes.values.any(
                                    (value) => value != null,
                                  ))
                                    'Attributes: ${item.productAttributes.entries.where((entry) => entry.value != null).map((entry) => '${entry.key}: ${entry.value}').join(', ')}',
                                ].join('\n'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (!readOnly && data.reviewStatus != 'REVIEWED')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Marking reviewed confirms that you checked the displayed values against the original invoice.',
                      ),
                    ),
                  if (!readOnly && data.reviewStatus != 'REVIEWED')
                    FilledButton.icon(
                      onPressed: () => _markReviewed(context, ref, data),
                      icon: const Icon(Icons.check),
                      label: const Text('Mark Reviewed'),
                    ),
                ],
              ),
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
      ref.invalidate(priceChangesProvider);
      ref.invalidate(priceHistoryProvider);
      ref.invalidate(needsAttentionProvider);
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
    final normalizedName = TextEditingController(text: item.normalizedName);
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
                MapEntry('Normalized name', normalizedName),
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
        'normalizedName': normalizedName.text.trim().isEmpty
            ? null
            : normalizedName.text.trim(),
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
    ref.invalidate(priceChangesProvider);
    ref.invalidate(priceHistoryProvider);
    ref.invalidate(needsAttentionProvider);
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
  late final otherFees = TextEditingController(
    text: widget.invoice.otherFees?.toStringAsFixed(2),
  );
  late final discount = TextEditingController(
    text: widget.invoice.discount?.toStringAsFixed(2),
  );
  late final total = TextEditingController(
    text: widget.invoice.total?.toStringAsFixed(2),
  );
  late final currency = TextEditingController(text: widget.invoice.currency);
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
              MapEntry('Other fees', otherFees),
              MapEntry('Discount', discount),
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
              controller: currency,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'Currency code',
                hintText: 'USD',
              ),
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
      'otherFees': otherFees.text.trim().isEmpty ? null : otherFees.text.trim(),
      'discount': discount.text.trim().isEmpty ? null : discount.text.trim(),
      'total': total.text.trim().isEmpty ? null : total.text.trim(),
      'currency': currency.text.trim().isEmpty
          ? null
          : currency.text.trim().toUpperCase(),
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
    ref.invalidate(priceChangesProvider);
    ref.invalidate(priceHistoryProvider);
    ref.invalidate(needsAttentionProvider);
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

String _reviewValue(String? value, bool uncertain) {
  final displayed = value ?? 'Missing';
  return uncertain ? '$displayed • Needs review' : displayed;
}

String _reviewFieldValue(
  InvoiceRecord invoice,
  String field,
  String? value,
  bool uncertain,
) {
  final displayed = _reviewValue(value, uncertain);
  final provenance = invoice.fieldProvenance[field];
  if (provenance == null) return displayed;
  if (provenance.kind == 'CALCULATED') {
    final calculated = provenance.calculatedValue;
    return '$displayed\nCalculated estimate${calculated == null ? '' : ': ${_reconciliationAmount(calculated)}'} • confirm before approval';
  }
  if (provenance.kind == 'MISSING') {
    return '$displayed\nNot found in the document';
  }
  if (provenance.verified) return '$displayed\nConfirmed by you';
  final page = provenance.sourcePage == null
      ? ''
      : ' on page ${provenance.sourcePage}';
  final quote = provenance.sourceText == null
      ? ''
      : ': “${provenance.sourceText}”';
  return '$displayed\nObserved$page$quote • confirm before approval';
}

String _status(String value) => value
    .toLowerCase()
    .split('_')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _size(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(1)} KB';
