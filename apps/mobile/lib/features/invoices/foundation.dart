import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

double? _money(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class InvoiceRecord {
  const InvoiceRecord({
    required this.id,
    required this.restaurantLocationId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    this.vendorId,
    this.vendorName,
    this.invoiceNumber,
    this.invoiceDate,
    this.subtotal,
    this.tax,
    this.total,
    this.notes,
    this.extractionStatus = 'NOT_STARTED',
    this.extractionConfidence,
    this.extractionError,
    this.reviewStatus = 'NOT_REVIEWED',
    this.ingestionSource = 'MANUAL_UPLOAD',
  });
  final String id, restaurantLocationId, fileName, fileType, status;
  final int fileSize;
  final String? vendorId, vendorName, invoiceNumber, notes;
  final DateTime? invoiceDate;
  final DateTime createdAt;
  final double? subtotal, tax, total;
  final String extractionStatus, reviewStatus;
  final String ingestionSource;
  final double? extractionConfidence;
  final String? extractionError;
  factory InvoiceRecord.fromJson(Map<String, dynamic> json) => InvoiceRecord(
    id: json['id'] as String,
    restaurantLocationId: json['restaurantLocationId'] as String,
    fileName: (json['originalFileName'] ?? json['fileName']) as String,
    fileType: json['fileType'] as String,
    fileSize: json['fileSize'] as int,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    vendorId: json['vendorId'] as String?,
    vendorName: json['vendorName'] as String?,
    invoiceNumber: json['invoiceNumber'] as String?,
    invoiceDate: json['invoiceDate'] == null
        ? null
        : DateTime.parse(json['invoiceDate'] as String),
    subtotal: _money(json['subtotal']),
    tax: _money(json['tax']),
    total: _money(json['total']),
    notes: json['notes'] as String?,
    extractionStatus: json['extractionStatus'] as String? ?? 'NOT_STARTED',
    extractionConfidence: _money(json['extractionConfidence']),
    extractionError: json['extractionError'] as String?,
    reviewStatus: json['reviewStatus'] as String? ?? 'NOT_REVIEWED',
    ingestionSource: json['ingestionSource'] as String? ?? 'MANUAL_UPLOAD',
  );
}

class InvoiceLineItem {
  const InvoiceLineItem({
    required this.id,
    required this.lineNumber,
    required this.rawDescription,
    this.sku,
    this.quantity,
    this.unit,
    this.packSize,
    this.unitPrice,
    this.extendedPrice,
    this.category,
    this.confidence,
  });
  final String id, rawDescription;
  final int lineNumber;
  final String? sku, unit, packSize, category;
  final double? quantity, unitPrice, extendedPrice, confidence;
  bool get lowConfidence => (confidence ?? 0) < .75;
  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) =>
      InvoiceLineItem(
        id: json['id'] as String,
        lineNumber: json['lineNumber'] as int,
        rawDescription: json['rawDescription'] as String,
        sku: json['sku'] as String?,
        quantity: _money(json['quantity']),
        unit: json['unit'] as String?,
        packSize: json['packSize'] as String?,
        unitPrice: _money(json['unitPrice']),
        extendedPrice: _money(json['extendedPrice']),
        category: json['category'] as String?,
        confidence: _money(json['confidence']),
      );
}

class InvoiceRepository {
  InvoiceRepository(this.dio);
  final Dio dio;
  Future<List<InvoiceRecord>> list(
    String locationId,
    DateRangeState range,
  ) async {
    final response = await dio.get(
      '/invoices',
      queryParameters: {
        'restaurantLocationId': locationId,
        'startDate': range.startDate.toIso8601String(),
        'endDate': range.endDate.toIso8601String(),
      },
    );
    return (response.data as List)
        .map(
          (item) =>
              InvoiceRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<InvoiceRecord> detail(String id) async {
    final response = await dio.get('/invoices/$id');
    return InvoiceRecord.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<InvoiceRecord> upload({
    required String locationId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    ProgressCallback? onProgress,
  }) async {
    final intent = await dio.post(
      '/invoices/upload-intent',
      data: {
        'restaurantLocationId': locationId,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSize': bytes.length,
      },
    );
    final body = Map<String, dynamic>.from(intent.data as Map);
    final invoice = InvoiceRecord.fromJson(
      Map<String, dynamic>.from(body['invoice'] as Map),
    );
    await Dio().put(
      body['uploadUrl'] as String,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: Map<String, dynamic>.from(body['headers'] as Map),
        contentType: mimeType,
      ),
      onSendProgress: onProgress,
    );
    final complete = await dio.post(
      '/invoices/${invoice.id}/upload-complete',
      data: {'etag': 'uploaded'},
    );
    return InvoiceRecord.fromJson(
      Map<String, dynamic>.from(complete.data as Map),
    );
  }

  Future<InvoiceRecord> update(String id, Map<String, dynamic> data) async {
    final response = await dio.patch('/invoices/$id', data: data);
    return InvoiceRecord.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> delete(String id) => dio.delete('/invoices/$id');
  Future<List<InvoiceLineItem>> lineItems(String id) async {
    final response = await dio.get('/invoices/$id/line-items');
    return (response.data as List)
        .map(
          (item) =>
              InvoiceLineItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> extract(String id) => dio.post('/invoices/$id/extract');
  Future<InvoiceRecord> review(String id, Map<String, dynamic> data) async {
    final response = await dio.patch('/invoices/$id/review', data: data);
    return InvoiceRecord.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<InvoiceLineItem> updateLineItem(
    String invoiceId,
    String lineItemId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.patch(
      '/invoices/$invoiceId/line-items/$lineItemId',
      data: data,
    );
    return InvoiceLineItem.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

final invoiceRepositoryProvider = Provider(
  (ref) => InvoiceRepository(ref.watch(api)),
);
final invoiceListProvider = FutureProvider<List<InvoiceRecord>>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  return ref
      .watch(invoiceRepositoryProvider)
      .list(location.id, ref.watch(dateRangeProvider));
});
final invoiceDetailProvider = FutureProvider.family<InvoiceRecord, String>(
  (ref, id) => ref.watch(invoiceRepositoryProvider).detail(id),
);
final invoiceLineItemsProvider =
    FutureProvider.family<List<InvoiceLineItem>, String>(
      (ref, id) => ref.watch(invoiceRepositoryProvider).lineItems(id),
    );

class InvoiceExtractionController extends StateNotifier<AsyncValue<void>> {
  InvoiceExtractionController(this.ref) : super(const AsyncData(null));
  final Ref ref;
  Future<void> extract(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(invoiceRepositoryProvider).extract(id);
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final invoice = await ref.read(invoiceRepositoryProvider).detail(id);
        ref.invalidate(invoiceDetailProvider(id));
        if (invoice.extractionStatus != 'PROCESSING') {
          ref.invalidate(invoiceLineItemsProvider(id));
          break;
        }
      }
      state = const AsyncData(null);
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }
}

final invoiceExtractionProvider =
    StateNotifierProvider<InvoiceExtractionController, AsyncValue<void>>(
      (ref) => InvoiceExtractionController(ref),
    );

enum InvoiceUploadPhase { idle, selecting, uploading, complete, failed }

class InvoiceUploadState {
  const InvoiceUploadState(this.phase, {this.progress = 0, this.error});
  final InvoiceUploadPhase phase;
  final double progress;
  final String? error;
}

class InvoiceUploadController extends StateNotifier<InvoiceUploadState> {
  InvoiceUploadController(this.ref)
    : super(const InvoiceUploadState(InvoiceUploadPhase.idle));
  final Ref ref;
  void selecting() =>
      state = const InvoiceUploadState(InvoiceUploadPhase.selecting);
  Future<InvoiceRecord?> upload({
    required String locationId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (state.phase == InvoiceUploadPhase.uploading) return null;
    state = const InvoiceUploadState(InvoiceUploadPhase.uploading);
    try {
      final invoice = await ref
          .read(invoiceRepositoryProvider)
          .upload(
            locationId: locationId,
            fileName: fileName,
            mimeType: mimeType,
            bytes: bytes,
            onProgress: (sent, total) {
              if (total > 0) {
                state = InvoiceUploadState(
                  InvoiceUploadPhase.uploading,
                  progress: sent / total,
                );
              }
            },
          );
      state = const InvoiceUploadState(
        InvoiceUploadPhase.complete,
        progress: 1,
      );
      ref.invalidate(invoiceListProvider);
      return invoice;
    } catch (_) {
      state = const InvoiceUploadState(
        InvoiceUploadPhase.failed,
        error: 'Unable to upload invoice. Please try again.',
      );
      return null;
    }
  }

  void reset() => state = const InvoiceUploadState(InvoiceUploadPhase.idle);
}

final invoiceUploadProvider =
    StateNotifierProvider<InvoiceUploadController, InvoiceUploadState>(
      (ref) => InvoiceUploadController(ref),
    );
