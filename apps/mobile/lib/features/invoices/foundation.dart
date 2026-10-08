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
  });
  final String id, restaurantLocationId, fileName, fileType, status;
  final int fileSize;
  final String? vendorId, vendorName, invoiceNumber, notes;
  final DateTime? invoiceDate;
  final DateTime createdAt;
  final double? subtotal, tax, total;
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
