import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/foundation.dart';
import '../price_intelligence/price_changes_screen.dart';
import '../savings/savings_screen.dart';
import '../vendors/vendors_screen.dart';
import '../expenses/expenses_screen.dart';
import '../invoices/invoice_screens.dart';
import '../banking/bank_screens.dart';
import '../pos/pos_integrations_screen.dart';
import 'notification_screen.dart';

class NotificationRouteData {
  const NotificationRouteData({required this.id, required this.type, this.deepLinkId, this.restaurantLocationId});
  final String id, type; final String? deepLinkId, restaurantLocationId;
  factory NotificationRouteData.fromJson(Map<String, dynamic> data) => NotificationRouteData(id: data['notificationId']?.toString() ?? data['id']?.toString() ?? '', type: data['type']?.toString() ?? '', deepLinkId: data['deepLinkId']?.toString(), restaurantLocationId: data['restaurantLocationId']?.toString());
  bool get valid => id.isNotEmpty && type.isNotEmpty;
}
class NotificationRouter {
  Future<void> open(BuildContext context, WidgetRef ref, NotificationRouteData route) async {
    if (!route.valid) return _message(context, 'This notification is no longer available.');
    final requested = route.restaurantLocationId;
    if (requested != null && requested != ref.read(activeLocationProvider)?.id) {
      final location = ref.read(availableLocationsProvider).where((item) => item.id == requested).firstOrNull;
      if (location == null) return _message(context, 'You no longer have access to this restaurant location.');
      await ref.read(activeLocationControllerProvider.notifier).select(location);
    }
    if (!context.mounted) return;
    final Widget screen = switch (route.type) {
      'PRICE_INCREASE' => route.deepLinkId == null ? const PriceChangesScreen() : PriceHistoryScreen(itemKey: route.deepLinkId!),
      'SAVINGS_OPPORTUNITY' => const SavingsOpportunitiesScreen(),
      'VENDOR_SPEND_INCREASE' => const VendorsScreen(),
      'CATEGORY_SPEND_INCREASE' => const ExpensesScreen(),
      'INVOICE_EXTRACTION_FAILED' => route.deepLinkId == null ? const InvoiceListScreen() : InvoiceDetailScreen(invoiceId: route.deepLinkId!),
      'BANK_SYNC_FAILED' || 'BANK_REAUTH_REQUIRED' => const BankAccountsScreen(),
      'POS_SYNC_FAILED' || 'POS_REAUTH_REQUIRED' => const PosIntegrationsScreen(),
      'WEEKLY_DIGEST' => const NotificationCenterScreen(),
      _ => const SizedBox.shrink(),
    };
    if (screen is SizedBox) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
  void _message(BuildContext context, String value) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }
}
final notificationRouterProvider = Provider((_) => NotificationRouter());
