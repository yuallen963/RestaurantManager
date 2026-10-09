import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

class InvoiceEmailRepository {
  InvoiceEmailRepository(this.dio);
  final Dio dio;
  Future<String> address(String restaurantLocationId) async {
    final response = await dio.get(
      '/invoice-email/address',
      queryParameters: {'restaurantLocationId': restaurantLocationId},
    );
    return (response.data as Map)['address'] as String;
  }
}

class InvoiceEmailActions {
  const InvoiceEmailActions();
  Future<void> copy(String address) =>
      Clipboard.setData(ClipboardData(text: address));
  Future<void> share(String address) =>
      Share.share(address, subject: 'Invoice forwarding address');
}

final invoiceEmailRepositoryProvider = Provider(
  (ref) => InvoiceEmailRepository(ref.watch(api)),
);
final invoiceEmailActionsProvider = Provider(
  (_) => const InvoiceEmailActions(),
);
final invoiceEmailAddressProvider = FutureProvider<String>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) throw StateError('No active restaurant location');
  return ref.watch(invoiceEmailRepositoryProvider).address(location.id);
});
