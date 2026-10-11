import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';
import 'invoice_upload.dart';

double? _money(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class InvoiceReconciliationDetail {
  const InvoiceReconciliationDetail({
    required this.code,
    this.expected,
    this.actual,
  });

  final String code;
  final String? expected;
  final String? actual;

  factory InvoiceReconciliationDetail.fromJson(Map<String, dynamic> json) =>
      InvoiceReconciliationDetail(
        code: json['code']?.toString() ?? '',
        expected: json['expected']?.toString(),
        actual: json['actual']?.toString(),
      );
}

class InvoiceReconciliation {
  const InvoiceReconciliation({
    this.reasons = const [],
    this.details = const [],
  });

  final List<String> reasons;
  final List<InvoiceReconciliationDetail> details;

  bool get hasDiscrepancy => reasons.isNotEmpty || details.isNotEmpty;

  factory InvoiceReconciliation.fromJson(Map<String, dynamic> json) {
    final reasons = (json['reasons'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    final details = (json['details'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => InvoiceReconciliationDetail.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList();
    return InvoiceReconciliation(reasons: reasons, details: details);
  }
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
    this.vendorAddress,
    this.invoiceNumber,
    this.invoiceDate,
    this.dueDate,
    this.subtotal,
    this.tax,
    this.otherFees,
    this.total,
    this.currency,
    this.notes,
    this.extractionStatus = 'NOT_STARTED',
    this.extractionConfidence,
    this.extractionError,
    this.reviewStatus = 'NOT_REVIEWED',
    this.ingestionSource = 'MANUAL_UPLOAD',
    this.uncertainFields = const [],
    this.reconciliation,
  });
  final String id, restaurantLocationId, fileName, fileType, status;
  final int fileSize;
  final String? vendorId,
      vendorName,
      vendorAddress,
      invoiceNumber,
      notes,
      currency;
  final DateTime? invoiceDate, dueDate;
  final DateTime createdAt;
  final double? subtotal, tax, otherFees, total;
  final String extractionStatus, reviewStatus;
  final String ingestionSource;
  final double? extractionConfidence;
  final String? extractionError;
  final List<String> uncertainFields;
  final InvoiceReconciliation? reconciliation;
  factory InvoiceRecord.fromJson(Map<String, dynamic> json) {
    final rawExtraction = json['rawExtractionJson'];
    final rawMap = rawExtraction is Map
        ? Map<String, dynamic>.from(rawExtraction)
        : null;
    final reconciliationJson = rawMap?['reconciliation'];
    return InvoiceRecord(
      id: json['id'] as String,
      restaurantLocationId: json['restaurantLocationId'] as String,
      fileName: (json['originalFileName'] ?? json['fileName']) as String,
      fileType: json['fileType'] as String,
      fileSize: json['fileSize'] as int,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      vendorId: json['vendorId'] as String?,
      vendorName: json['vendorName'] as String?,
      vendorAddress: json['extractedVendorAddress'] as String?,
      invoiceNumber: json['invoiceNumber'] as String?,
      invoiceDate: json['invoiceDate'] == null
          ? null
          : DateTime.parse(json['invoiceDate'] as String),
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.parse(json['dueDate'] as String),
      subtotal: _money(json['subtotal']),
      tax: _money(json['tax']),
      otherFees: _money(json['otherFees']),
      total: _money(json['total']),
      currency: json['currency'] as String?,
      notes: json['notes'] as String?,
      extractionStatus: json['extractionStatus'] as String? ?? 'NOT_STARTED',
      extractionConfidence: _money(json['extractionConfidence']),
      extractionError: json['extractionError'] as String?,
      reviewStatus: json['reviewStatus'] as String? ?? 'NOT_REVIEWED',
      ingestionSource: json['ingestionSource'] as String? ?? 'MANUAL_UPLOAD',
      uncertainFields: (json['uncertainFields'] as List? ?? const [])
          .cast<String>(),
      reconciliation: reconciliationJson is Map
          ? InvoiceReconciliation.fromJson(
              Map<String, dynamic>.from(reconciliationJson),
            )
          : null,
    );
  }
}

class InvoiceLineItem {
  const InvoiceLineItem({
    required this.id,
    required this.lineNumber,
    required this.rawDescription,
    this.sku,
    this.normalizedName,
    this.quantity,
    this.unit,
    this.packSize,
    this.packCount,
    this.packUnitQuantity,
    this.measurementUnit,
    this.totalPackageQuantity,
    this.productAttributes = const {},
    this.sourcePage,
    this.unitPrice,
    this.extendedPrice,
    this.category,
    this.confidence,
    this.uncertainFields = const [],
  });
  final String id, rawDescription;
  final int lineNumber;
  final String? sku, normalizedName, unit, packSize, measurementUnit, category;
  final double? quantity,
      packCount,
      packUnitQuantity,
      totalPackageQuantity,
      unitPrice,
      extendedPrice,
      confidence;
  final int? sourcePage;
  final Map<String, dynamic> productAttributes;
  final List<String> uncertainFields;
  bool get lowConfidence =>
      (confidence ?? 0) < .75 || uncertainFields.isNotEmpty;
  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) =>
      InvoiceLineItem(
        id: json['id'] as String,
        lineNumber: json['lineNumber'] as int,
        rawDescription: json['rawDescription'] as String,
        normalizedName: json['normalizedName'] as String?,
        sku: json['sku'] as String?,
        quantity: _money(json['quantity']),
        unit: json['unit'] as String?,
        packSize: json['packSize'] as String?,
        packCount: _money(json['packCount']),
        packUnitQuantity: _money(json['packUnitQuantity']),
        measurementUnit: json['measurementUnit'] as String?,
        totalPackageQuantity: _money(json['totalPackageQuantity']),
        productAttributes: Map<String, dynamic>.from(
          json['productAttributes'] as Map? ?? const {},
        ),
        sourcePage: json['sourcePage'] as int?,
        unitPrice: _money(json['unitPrice']),
        extendedPrice: _money(json['extendedPrice']),
        category: json['category'] as String?,
        confidence: _money(json['confidence']),
        uncertainFields: (json['uncertainFields'] as List? ?? const [])
            .cast<String>(),
      );
}

class InvoiceRepository {
  InvoiceRepository(this.dio, {Dio? storageDio})
    : _storageDio =
          storageDio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 90),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
  final Dio dio;
  final Dio _storageDio;
  Future<List<InvoiceRecord>> list(
    String locationId,
    DateRangeState range,
  ) async {
    final response = await dio.get(
      '/invoices',
      queryParameters: {
        'restaurantLocationId': locationId,
        'startDate': range.startDate.toUtc().toIso8601String(),
        'endDate': range.endDate
            .add(const Duration(days: 1))
            .subtract(const Duration(microseconds: 1))
            .toUtc()
            .toIso8601String(),
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
    late final Response<dynamic> intent;
    try {
      intent = await dio.post(
        '/invoices/upload-intent',
        data: {
          'restaurantLocationId': locationId,
          'fileName': fileName,
          'mimeType': mimeType,
          'fileSize': bytes.length,
        },
      );
    } on DioException catch (error) {
      throw _uploadFailure(error, stage: 'upload_intent');
    }
    final body = Map<String, dynamic>.from(intent.data as Map);
    final invoice = InvoiceRecord.fromJson(
      Map<String, dynamic>.from(body['invoice'] as Map),
    );
    try {
      final headers = Map<String, dynamic>.from(body['headers'] as Map)
        ..['Content-Type'] = mimeType
        ..['Content-Length'] = bytes.length;
      await _storageDio.put(
        body['uploadUrl'] as String,
        // A Uint8List gives Dio an explicit content length. The previous
        // unknown-length Stream used chunked transfer encoding, which the
        // S3-compatible presigned endpoint rejects before creating an object.
        data: bytes,
        options: Options(headers: headers, contentType: mimeType),
        onSendProgress: onProgress,
      );
    } on DioException catch (error) {
      await _cancelIncomplete(invoice.id);
      throw _uploadFailure(error, stage: 'storage_upload');
    }
    late final Response<dynamic> complete;
    try {
      complete = await dio.post(
        '/invoices/${invoice.id}/upload-complete',
        data: {'etag': 'uploaded'},
      );
    } on DioException catch (error) {
      // A response timeout can occur after completion committed. Check before
      // deleting or asking the user to retry, avoiding duplicate records.
      try {
        final current = await detail(invoice.id);
        if (current.status != 'PROCESSING') return current;
        await _cancelIncomplete(invoice.id);
      } catch (_) {
        // Preserve the original categorized completion failure.
      }
      throw _uploadFailure(error, stage: 'upload_complete');
    }
    return InvoiceRecord.fromJson(
      Map<String, dynamic>.from(complete.data as Map),
    );
  }

  Future<void> _cancelIncomplete(String id) async {
    try {
      await dio.delete('/invoices/$id');
    } catch (_) {
      // Best effort only. Never replace the useful upload-stage error.
    }
  }

  InvoiceUploadFailure _uploadFailure(
    DioException error, {
    required String stage,
  }) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final safeCode = data is Map ? data['code']?.toString() : null;
    final timeout =
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
    final category = timeout
        ? InvoiceUploadErrorCategory.networkTimeout
        : status == 401
        ? InvoiceUploadErrorCategory.unauthorized
        : stage == 'storage_upload' && status == 403
        ? InvoiceUploadErrorCategory.authorizationExpired
        : stage == 'storage_upload'
        ? InvoiceUploadErrorCategory.storageFailed
        : stage == 'upload_complete'
        ? InvoiceUploadErrorCategory.completionFailed
        : InvoiceUploadErrorCategory.intentFailed;
    final message = switch (category) {
      InvoiceUploadErrorCategory.networkTimeout =>
        'The upload connection timed out. Check your connection and try again.',
      InvoiceUploadErrorCategory.unauthorized =>
        'Your session expired. Restart FundWell and try again.',
      InvoiceUploadErrorCategory.authorizationExpired =>
        'The upload authorization expired. Please try the upload again.',
      InvoiceUploadErrorCategory.storageFailed =>
        'The photo could not be uploaded to secure storage. Please try again.',
      InvoiceUploadErrorCategory.completionFailed =>
        'The photo uploaded, but invoice registration failed. Please try again.',
      _ => 'Unable to start the invoice upload. Please try again.',
    };
    logInvoiceUpload(
      stage: stage,
      category: category.name,
      statusCode: status,
      safeCode: safeCode,
    );
    return InvoiceUploadFailure(
      category,
      message,
      stage: stage,
      statusCode: status,
      safeCode: safeCode,
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
  void fail(
    InvoiceUploadFailure error, {
    int? fileSize,
    InvoiceFileFormat? format,
  }) {
    logInvoiceUpload(
      stage: error.stage,
      category: error.category.name,
      statusCode: error.statusCode,
      safeCode: error.safeCode,
      fileSize: fileSize,
      format: format,
    );
    state = InvoiceUploadState(InvoiceUploadPhase.failed, error: error.message);
  }

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
    } on InvoiceUploadFailure catch (error) {
      logInvoiceUpload(
        stage: error.stage,
        category: error.category.name,
        statusCode: error.statusCode,
        safeCode: error.safeCode,
        fileSize: bytes.length,
      );
      state = InvoiceUploadState(
        InvoiceUploadPhase.failed,
        error: error.message,
      );
      return null;
    } catch (_) {
      logInvoiceUpload(
        stage: 'unknown',
        category: 'unexpected',
        fileSize: bytes.length,
      );
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
