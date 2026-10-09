import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/expenses/foundation.dart';
import 'package:restaurant_profit_mobile/features/invoices/foundation.dart';
import 'package:restaurant_profit_mobile/features/invoices/invoice_screens.dart';

const location = RestaurantLocation(
  id: 'loc-a',
  name: 'Downtown Grill',
  organizationId: 'org-a',
);
final invoice = InvoiceRecord(
  id: 'invoice-a',
  restaurantLocationId: 'loc-a',
  fileName: 'sysco.pdf',
  fileType: 'application/pdf',
  fileSize: 2048,
  status: 'UPLOADED',
  createdAt: DateTime(2026, 10, 4),
  vendorName: 'Sysco',
  invoiceNumber: '1001',
  total: 2842.16,
);

class FakeInvoiceRepository extends InvoiceRepository {
  FakeInvoiceRepository({this.failUpload = false}) : super(Dio());
  final bool failUpload;
  bool deleted = false;
  bool reviewed = false;
  Map<String, dynamic>? correctedLine;
  @override
  Future<InvoiceRecord> upload({
    required String locationId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    ProgressCallback? onProgress,
  }) async {
    if (failUpload) throw DioException(requestOptions: RequestOptions());
    onProgress?.call(bytes.length, bytes.length);
    return invoice;
  }

  @override
  Future<void> delete(String id) async => deleted = true;

  @override
  Future<InvoiceRecord> review(String id, Map<String, dynamic> data) async {
    reviewed = data['markReviewed'] == true;
    return invoice;
  }

  @override
  Future<InvoiceLineItem> updateLineItem(
    String invoiceId,
    String lineItemId,
    Map<String, dynamic> data,
  ) async {
    correctedLine = data;
    return lineItem;
  }
}

final extractedInvoice = InvoiceRecord(
  id: 'invoice-a',
  restaurantLocationId: 'loc-a',
  fileName: 'sysco.pdf',
  fileType: 'application/pdf',
  fileSize: 2048,
  status: 'UPLOADED',
  createdAt: DateTime(2026, 10, 4),
  vendorName: 'Sysco',
  invoiceNumber: 'INV-1001',
  invoiceDate: DateTime(2026, 10, 4),
  subtotal: 100,
  tax: 6,
  total: 106,
  extractionStatus: 'COMPLETED',
  extractionConfidence: .72,
  reviewStatus: 'NEEDS_REVIEW',
);
const lineItem = InvoiceLineItem(
  id: 'line-a',
  lineNumber: 1,
  rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB',
  sku: '384920',
  quantity: 2,
  unit: 'CASE',
  packSize: '4 x 10 lb',
  unitPrice: 50,
  extendedPrice: 100,
  category: 'Food',
  confidence: .62,
);

Widget app(List<Override> overrides, Widget child) => ProviderScope(
  overrides: [
    activeLocationProvider.overrideWith((_) => location),
    ...overrides,
  ],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('invoice list shows loading state', (tester) async {
    await tester.pumpWidget(
      app([
        invoiceListProvider.overrideWith(
          (_) => Completer<List<InvoiceRecord>>().future,
        ),
      ], const InvoiceListScreen()),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('invoice list shows empty state and upload CTA', (tester) async {
    await tester.pumpWidget(
      app([
        invoiceListProvider.overrideWith((_) async => []),
      ], const InvoiceListScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('No invoices uploaded yet.'), findsOneWidget);
    expect(find.text('Upload Invoice'), findsWidgets);
  });

  testWidgets('invoice list renders vendor, total and status', (tester) async {
    await tester.pumpWidget(
      app([
        invoiceListProvider.overrideWith((_) async => [invoice]),
      ], const InvoiceListScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.textContaining(r'$2,842'), findsOneWidget);
    expect(find.text('Uploaded'), findsOneWidget);
  });

  testWidgets('email-ingested invoice shows its source in list and detail', (
    tester,
  ) async {
    final emailed = InvoiceRecord(
      id: 'email-invoice',
      restaurantLocationId: 'loc-a',
      fileName: 'forwarded.pdf',
      fileType: 'application/pdf',
      fileSize: 2048,
      status: 'UPLOADED',
      createdAt: DateTime(2026, 10, 4),
      ingestionSource: 'EMAIL_FORWARD',
    );
    await tester.pumpWidget(
      app([
        invoiceListProvider.overrideWith((_) async => [emailed]),
        invoiceDetailProvider(
          'email-invoice',
        ).overrideWith((_) async => emailed),
      ], const InvoiceListScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Email •'), findsOneWidget);
    await tester.tap(find.text('forwarded.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('invoice list shows error and retry', (tester) async {
    await tester.pumpWidget(
      app([
        invoiceListProvider.overrideWith((_) => Future.error('network')),
      ], const InvoiceListScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load invoices'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('upload screen exposes file and photo selection separately', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [], const InvoiceUploadScreen()));
    expect(find.text('Select PDF or Image File'), findsOneWidget);
    expect(find.text('Choose Photo'), findsOneWidget);
    expect(find.textContaining('15 MB'), findsOneWidget);
  });

  testWidgets('invoice detail renders manual metadata', (tester) async {
    await tester.pumpWidget(
      app([
        invoiceDetailProvider('invoice-a').overrideWith((_) async => invoice),
      ], const InvoiceDetailScreen(invoiceId: 'invoice-a')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text('1001'), findsOneWidget);
    expect(find.textContaining(r'$2,842'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Edit Metadata'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Edit Metadata'), findsOneWidget);
    expect(find.text('Delete Invoice'), findsOneWidget);
  });

  testWidgets('detail shows processing extraction state', (tester) async {
    final processing = InvoiceRecord(
      id: 'invoice-a',
      restaurantLocationId: 'loc-a',
      fileName: 'invoice.pdf',
      fileType: 'application/pdf',
      fileSize: 100,
      status: 'UPLOADED',
      createdAt: DateTime(2026),
      extractionStatus: 'PROCESSING',
    );
    await tester.pumpWidget(
      app([
        invoiceDetailProvider(
          'invoice-a',
        ).overrideWith((_) async => processing),
      ], const InvoiceDetailScreen(invoiceId: 'invoice-a')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Processing invoice extraction...'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Processing invoice extraction...'), findsOneWidget);
  });

  testWidgets('detail shows failed extraction and retry', (tester) async {
    final failed = InvoiceRecord(
      id: 'invoice-a',
      restaurantLocationId: 'loc-a',
      fileName: 'invoice.pdf',
      fileType: 'application/pdf',
      fileSize: 100,
      status: 'UPLOADED',
      createdAt: DateTime(2026),
      extractionStatus: 'FAILED',
      extractionError: 'Unable to read document',
    );
    await tester.pumpWidget(
      app([
        invoiceDetailProvider('invoice-a').overrideWith((_) async => failed),
      ], const InvoiceDetailScreen(invoiceId: 'invoice-a')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Retry Extraction'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Unable to read document'), findsOneWidget);
    expect(find.text('Retry Extraction'), findsOneWidget);
  });

  testWidgets('review highlights low confidence and marks reviewed', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    await tester.pumpWidget(
      app([
        invoiceRepositoryProvider.overrideWithValue(repository),
        invoiceDetailProvider(
          'invoice-a',
        ).overrideWith((_) async => extractedInvoice),
        invoiceLineItemsProvider(
          'invoice-a',
        ).overrideWith((_) async => [lineItem]),
      ], const InvoiceReviewScreen(invoiceId: 'invoice-a')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Needs review'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('CHKN BRST BNLS SKLS 4/10 LB'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CHKN BRST BNLS SKLS 4/10 LB'), findsOneWidget);
    expect(find.textContaining('Confidence: Low'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mark Reviewed'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mark Reviewed'));
    await tester.pump();
    expect(repository.reviewed, isTrue);
  });

  testWidgets('line item correction persists raw description edit', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    await tester.pumpWidget(
      app([
        invoiceRepositoryProvider.overrideWithValue(repository),
        invoiceDetailProvider(
          'invoice-a',
        ).overrideWith((_) async => extractedInvoice),
        invoiceLineItemsProvider(
          'invoice-a',
        ).overrideWith((_) async => [lineItem]),
      ], const InvoiceReviewScreen(invoiceId: 'invoice-a')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('CHKN BRST BNLS SKLS 4/10 LB'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('CHKN BRST BNLS SKLS 4/10 LB'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Corrected chicken breast',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      repository.correctedLine?['rawDescription'],
      'Corrected chicken breast',
    );
  });

  testWidgets('metadata form rejects negative currency', (tester) async {
    await tester.pumpWidget(
      app([
        expenseLookupsProvider.overrideWith(
          (_) async => const ExpenseLookups([], []),
        ),
      ], InvoiceEditScreen(invoice: invoice)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Total').last,
      '-1',
    );
    await tester.tap(find.text('Save Metadata'));
    await tester.pump();
    expect(find.text('Enter a valid non-negative amount'), findsOneWidget);
  });

  test(
    'upload controller reports success and failure without duplicating state',
    () async {
      final success = FakeInvoiceRepository();
      final container = ProviderContainer(
        overrides: [invoiceRepositoryProvider.overrideWithValue(success)],
      );
      addTearDown(container.dispose);
      final result = await container
          .read(invoiceUploadProvider.notifier)
          .upload(
            locationId: 'loc-a',
            fileName: 'invoice.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1, 2, 3]),
          );
      expect(result?.id, 'invoice-a');
      expect(
        container.read(invoiceUploadProvider).phase,
        InvoiceUploadPhase.complete,
      );

      final failedContainer = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(
            FakeInvoiceRepository(failUpload: true),
          ),
        ],
      );
      addTearDown(failedContainer.dispose);
      final failed = await failedContainer
          .read(invoiceUploadProvider.notifier)
          .upload(
            locationId: 'loc-a',
            fileName: 'invoice.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1]),
          );
      expect(failed, isNull);
      expect(
        failedContainer.read(invoiceUploadProvider).phase,
        InvoiceUploadPhase.failed,
      );
    },
  );

  testWidgets('delete flow confirms deletion through repository', (
    tester,
  ) async {
    final repository = FakeInvoiceRepository();
    await tester.pumpWidget(
      app([
        invoiceRepositoryProvider.overrideWithValue(repository),
        invoiceDetailProvider('invoice-a').overrideWith((_) async => invoice),
      ], const InvoiceDetailScreen(invoiceId: 'invoice-a')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Delete Invoice'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Delete Invoice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Invoice'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isTrue);
  });
}
