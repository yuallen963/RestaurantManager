import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const invoiceUploadLimit = 15 * 1024 * 1024;

enum InvoiceFileFormat { pdf, jpeg, png, heic, unknown }

enum InvoiceUploadErrorCategory {
  unsupportedFormat,
  tooLarge,
  unreadablePhoto,
  intentFailed,
  unauthorized,
  authorizationExpired,
  storageFailed,
  completionFailed,
  networkTimeout,
}

class InvoiceUploadFailure implements Exception {
  const InvoiceUploadFailure(
    this.category,
    this.message, {
    required this.stage,
    this.statusCode,
    this.safeCode,
  });

  final InvoiceUploadErrorCategory category;
  final String message;
  final String stage;
  final int? statusCode;
  final String? safeCode;

  @override
  String toString() => message;
}

class PreparedInvoiceFile {
  const PreparedInvoiceFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.format,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final InvoiceFileFormat format;
}

InvoiceFileFormat detectInvoiceFormat(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return InvoiceFileFormat.pdf;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return InvoiceFileFormat.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return InvoiceFileFormat.png;
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
    final brand = ascii
        .decode(bytes.sublist(8, 12), allowInvalid: true)
        .toLowerCase();
    if ({
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'mif1',
      'msf1',
    }.contains(brand)) {
      return InvoiceFileFormat.heic;
    }
  }
  return InvoiceFileFormat.unknown;
}

PreparedInvoiceFile prepareInvoiceFile({
  required String originalName,
  required Uint8List bytes,
  bool pickedFromPhotoLibrary = false,
}) {
  if (bytes.isEmpty) {
    throw const InvoiceUploadFailure(
      InvoiceUploadErrorCategory.unreadablePhoto,
      'Unable to read the selected photo. Please choose it again.',
      stage: 'file_read',
    );
  }
  final format = detectInvoiceFormat(bytes);
  if (format == InvoiceFileFormat.heic) {
    // image_picker on iOS converts HEIC/HEIF through UIImage when imageQuality
    // is supplied. Seeing HEIC here means that native conversion did not run.
    throw const InvoiceUploadFailure(
      InvoiceUploadErrorCategory.unsupportedFormat,
      'Unable to convert this iPhone photo to JPEG. Try selecting it again or export it as JPEG.',
      stage: 'file_prepare',
      safeCode: 'HEIC_CONVERSION_FAILED',
    );
  }
  final metadata = switch (format) {
    InvoiceFileFormat.pdf => ('application/pdf', 'pdf'),
    InvoiceFileFormat.jpeg => ('image/jpeg', 'jpg'),
    InvoiceFileFormat.png => ('image/png', 'png'),
    _ => throw InvoiceUploadFailure(
      InvoiceUploadErrorCategory.unsupportedFormat,
      pickedFromPhotoLibrary
          ? 'This photo format is not supported. Choose a JPEG, PNG, or iPhone camera photo.'
          : 'Select a PDF, JPEG, or PNG invoice file.',
      stage: 'file_prepare',
      safeCode: 'UNSUPPORTED_FILE_FORMAT',
    ),
  };
  if (bytes.length > invoiceUploadLimit) {
    throw const InvoiceUploadFailure(
      InvoiceUploadErrorCategory.tooLarge,
      'Invoice files must be 15 MB or smaller.',
      stage: 'file_prepare',
      safeCode: 'FILE_TOO_LARGE',
    );
  }
  final dot = originalName.lastIndexOf('.');
  final base = (dot > 0 ? originalName.substring(0, dot) : originalName).trim();
  final safeBase = base.isEmpty ? 'invoice' : base;
  return PreparedInvoiceFile(
    fileName: '$safeBase.${metadata.$2}',
    mimeType: metadata.$1,
    bytes: bytes,
    format: format,
  );
}

abstract class InvoicePhotoSource {
  Future<XFile?> pick();
}

class NativeInvoicePhotoSource implements InvoicePhotoSource {
  NativeInvoicePhotoSource([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<XFile?> pick() => _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
    requestFullMetadata: true,
  );
}

final invoicePhotoSourceProvider = Provider<InvoicePhotoSource>(
  (_) => NativeInvoicePhotoSource(),
);

void logInvoiceUpload({
  required String stage,
  required String category,
  int? statusCode,
  String? safeCode,
  InvoiceFileFormat? format,
  int? fileSize,
}) {
  final payload = <String, Object>{
    'event': 'invoice_upload',
    'stage': stage,
    'category': category,
  };
  if (statusCode case final value?) payload['statusCode'] = value;
  if (safeCode case final value?) payload['safeCode'] = value;
  if (format case final value?) payload['format'] = value.name;
  if (fileSize case final value?) payload['fileSize'] = value;
  developer.log(jsonEncode(payload), name: 'fundwell.invoice_upload');
}
