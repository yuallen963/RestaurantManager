import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/invoices/foundation.dart';
import 'package:restaurant_profit_mobile/features/invoices/invoice_upload.dart';

Uint8List _bytes(List<int> signature, [int length = 32]) => Uint8List.fromList([
  ...signature,
  ...List<int>.filled(length - signature.length, 0),
]);

Map<String, dynamic> _invoiceJson({String status = 'PROCESSING'}) => {
  'id': 'invoice-a',
  'restaurantLocationId': 'location-a',
  'originalFileName': 'invoice.jpg',
  'fileType': 'image/jpeg',
  'fileSize': 32,
  'status': status,
  'createdAt': '2026-10-11T12:00:00.000Z',
};

Dio _dioWithHandler(
  void Function(RequestOptions options, RequestInterceptorHandler handler)
  onRequest,
) => Dio()..interceptors.add(InterceptorsWrapper(onRequest: onRequest));

void main() {
  group('invoice file preparation', () {
    test(
      'normalizes a JPEG by its bytes instead of a misleading HEIC name',
      () {
        final prepared = prepareInvoiceFile(
          originalName: 'IMG_0001.HEIC',
          bytes: _bytes([0xff, 0xd8, 0xff]),
          pickedFromPhotoLibrary: true,
        );

        expect(prepared.format, InvoiceFileFormat.jpeg);
        expect(prepared.mimeType, 'image/jpeg');
        expect(prepared.fileName, 'IMG_0001.jpg');
      },
    );

    test('preserves PNG bytes, extension, and MIME type', () {
      final prepared = prepareInvoiceFile(
        originalName: 'screenshot.jpeg',
        bytes: _bytes([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      );

      expect(prepared.format, InvoiceFileFormat.png);
      expect(prepared.mimeType, 'image/png');
      expect(prepared.fileName, 'screenshot.png');
    });

    test('accepts a PDF without changing its bytes', () {
      final bytes = _bytes([0x25, 0x50, 0x44, 0x46]);
      final prepared = prepareInvoiceFile(
        originalName: 'invoice',
        bytes: bytes,
      );
      expect(prepared.mimeType, 'application/pdf');
      expect(prepared.fileName, 'invoice.pdf');
      expect(prepared.bytes, same(bytes));
    });

    test('detects raw HEIC when native iOS conversion did not occur', () {
      final bytes = _bytes([
        0,
        0,
        0,
        24,
        0x66,
        0x74,
        0x79,
        0x70,
        0x68,
        0x65,
        0x69,
        0x63,
      ]);
      expect(
        () => prepareInvoiceFile(
          originalName: 'photo.heic',
          bytes: bytes,
          pickedFromPhotoLibrary: true,
        ),
        throwsA(
          isA<InvoiceUploadFailure>().having(
            (error) => error.safeCode,
            'safe code',
            'HEIC_CONVERSION_FAILED',
          ),
        ),
      );
    });

    test('rejects empty and oversized inputs before upload', () {
      expect(
        () =>
            prepareInvoiceFile(originalName: 'photo.jpg', bytes: Uint8List(0)),
        throwsA(
          isA<InvoiceUploadFailure>().having(
            (error) => error.category,
            'category',
            InvoiceUploadErrorCategory.unreadablePhoto,
          ),
        ),
      );
      final oversized = Uint8List(invoiceUploadLimit + 1)
        ..setRange(0, 3, [0xff, 0xd8, 0xff]);
      expect(
        () => prepareInvoiceFile(originalName: 'photo.jpg', bytes: oversized),
        throwsA(
          isA<InvoiceUploadFailure>().having(
            (error) => error.category,
            'category',
            InvoiceUploadErrorCategory.tooLarge,
          ),
        ),
      );
    });
  });

  test(
    'storage upload uses bytes, explicit length, and no API auth header',
    () async {
      final bytes = _bytes([0xff, 0xd8, 0xff]);
      late RequestOptions storageRequest;
      final api = _dioWithHandler((options, handler) {
        if (options.path == '/invoices/upload-intent') {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 201,
              data: {
                'invoice': _invoiceJson(),
                'uploadUrl': 'https://private-storage.test/upload',
                'headers': {'Content-Type': 'image/jpeg'},
              },
            ),
          );
        } else if (options.path.endsWith('/upload-complete')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: _invoiceJson(status: 'UPLOADED'),
            ),
          );
        } else {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
            ),
          );
        }
      });
      final storage = _dioWithHandler((options, handler) {
        storageRequest = options;
        handler.resolve(Response(requestOptions: options, statusCode: 200));
      });

      final result = await InvoiceRepository(api, storageDio: storage).upload(
        locationId: 'location-a',
        fileName: 'invoice.jpg',
        mimeType: 'image/jpeg',
        bytes: bytes,
      );

      expect(result.status, 'UPLOADED');
      expect(storageRequest.method, 'PUT');
      expect(storageRequest.data, same(bytes));
      expect(storageRequest.headers['Content-Length'], bytes.length);
      expect(storageRequest.headers['Content-Type'], 'image/jpeg');
      expect(storageRequest.headers.containsKey('Authorization'), isFalse);
    },
  );

  test(
    'expired presigned upload is categorized and incomplete record is deleted',
    () async {
      var deleted = false;
      final api = _dioWithHandler((options, handler) {
        if (options.path == '/invoices/upload-intent') {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 201,
              data: {
                'invoice': _invoiceJson(),
                'uploadUrl': 'https://private-storage.test/upload',
                'headers': {'Content-Type': 'image/jpeg'},
              },
            ),
          );
        } else if (options.method == 'DELETE') {
          deleted = true;
          handler.resolve(Response(requestOptions: options, statusCode: 204));
        }
      });
      final storage = _dioWithHandler((options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 403),
            type: DioExceptionType.badResponse,
          ),
        );
      });

      await expectLater(
        InvoiceRepository(api, storageDio: storage).upload(
          locationId: 'location-a',
          fileName: 'invoice.jpg',
          mimeType: 'image/jpeg',
          bytes: _bytes([0xff, 0xd8, 0xff]),
        ),
        throwsA(
          isA<InvoiceUploadFailure>().having(
            (error) => error.category,
            'category',
            InvoiceUploadErrorCategory.authorizationExpired,
          ),
        ),
      );
      expect(deleted, isTrue);
    },
  );

  test('upload-intent timeout has an actionable category', () async {
    final api = _dioWithHandler((options, handler) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
    });

    await expectLater(
      InvoiceRepository(api).upload(
        locationId: 'location-a',
        fileName: 'invoice.jpg',
        mimeType: 'image/jpeg',
        bytes: _bytes([0xff, 0xd8, 0xff]),
      ),
      throwsA(
        isA<InvoiceUploadFailure>().having(
          (error) => error.category,
          'category',
          InvoiceUploadErrorCategory.networkTimeout,
        ),
      ),
    );
  });
}
