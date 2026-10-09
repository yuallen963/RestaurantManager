import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart' show api, storage;
import '../dashboard/foundation.dart';
import 'push_service.dart';
import 'notification_router.dart';

class NotificationItem {
  const NotificationItem(
    this.id,
    this.title,
    this.body,
    this.type,
    this.readAt,
    this.createdAt,
  );
  final String id, title, body, type;
  final DateTime? readAt;
  final DateTime createdAt;
  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
    j['id'],
    j['title'],
    j['body'],
    j['type'],
    j['readAt'] == null ? null : DateTime.parse(j['readAt']),
    DateTime.parse(j['createdAt']),
  );
}

class NotificationRepo {
  NotificationRepo(this.dio);
  final Dio dio;
  Future<Map<String, dynamic>> list(bool unread) async =>
      Map<String, dynamic>.from(
        (await dio.get(
          '/notifications',
          queryParameters: {if (unread) 'unreadOnly': true},
        )).data,
      );
  Future<void> read(String id) => dio.patch('/notifications/$id/read');
  Future<void> all() => dio.post('/notifications/read-all');
  Future<Map<String, dynamic>> preference(String organizationId) async =>
      Map<String, dynamic>.from(
        (await dio.get(
          '/notifications/preferences',
          queryParameters: {'organizationId': organizationId},
        )).data,
      );
  Future<void> savePreference(Map<String, dynamic> value) =>
      dio.patch('/notifications/preferences', data: value);
  Future<void> registerToken(String token) => dio.post('/notifications/devices', data: {'token': token, 'platform': 'IOS'});
}

final notificationRepoProvider = Provider(
  (r) => NotificationRepo(r.watch(api)),
);
final notificationUnreadProvider = StateProvider((_) => false);
final notificationListProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref
      .watch(notificationRepoProvider)
      .list(ref.watch(notificationUnreadProvider)),
);
final notificationPreferenceProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) {
  final location = ref.watch(activeLocationProvider);
  if (location == null) throw StateError('No restaurant location');
  return ref
      .watch(notificationRepoProvider)
      .preference(location.organizationId);
});

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});
  @override
  Widget build(BuildContext c, WidgetRef r) {
    final data = r.watch(notificationListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => r
                .read(notificationRepoProvider)
                .all()
                .then((_) => r.invalidate(notificationListProvider)),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Unable to load notifications')),
        data: (json) {
          final items = (json['items'] as List)
              .map(
                (e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
          return Column(
            children: [
              SwitchListTile(
                title: const Text('Unread only'),
                value: r.watch(notificationUnreadProvider),
                onChanged: (v) {
                  r.read(notificationUnreadProvider.notifier).state = v;
                },
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No notifications yet'))
                    : ListView(
                        children: items
                            .map(
                              (n) => ListTile(
                                key: Key('notification-${n.id}'),
                                leading: Icon(
                                  n.readAt == null
                                      ? Icons.circle
                                      : Icons.notifications_none,
                                  color: n.readAt == null
                                      ? Theme.of(c).colorScheme.primary
                                      : null,
                                ),
                                title: Text(n.title),
                                subtitle: Text(n.body),
                                trailing: Text(
                                  '${n.createdAt.month}/${n.createdAt.day}',
                                ),
                                onTap: () async { try { await r.read(notificationRepoProvider).read(n.id); } catch (_) {} r.invalidate(notificationListProvider); if (c.mounted) await r.read(notificationRouterProvider).open(c, r, NotificationRouteData(id: n.id, type: n.type)); },
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool push = true,
      digest = true,
      price = true,
      savings = true,
      cost = true,
      sync = true;
  TimeOfDay? start, end;
  bool initialized = false;
  String? error;
  void load(Map<String, dynamic> value) {
    if (initialized) return;
    initialized = true;
    push = value['pushEnabled'] as bool? ?? true;
    digest = value['weeklyDigestEnabled'] as bool? ?? true;
    price = value['priceAlertsEnabled'] as bool? ?? true;
    savings = value['savingsAlertsEnabled'] as bool? ?? true;
    cost = value['costAlertsEnabled'] as bool? ?? true;
    sync = value['syncAlertsEnabled'] as bool? ?? true;
    start = _time(value['quietHoursStart'] as String?);
    end = _time(value['quietHoursEnd'] as String?);
  }

  TimeOfDay? _time(String? value) {
    if (value == null) return null;
    final p = value.split(':');
    return p.length == 2
        ? TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]))
        : null;
  }

  String? _string(TimeOfDay? value) => value == null
      ? null
      : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  Future<void> save() async {
    final location = ref.read(activeLocationProvider);
    if (location == null) return;
    try {
      await ref.read(notificationRepoProvider).savePreference({
        'organizationId': location.organizationId,
        'restaurantLocationId': location.id,
        'pushEnabled': push,
        'weeklyDigestEnabled': digest,
        'priceAlertsEnabled': price,
        'savingsAlertsEnabled': savings,
        'costAlertsEnabled': cost,
        'syncAlertsEnabled': sync,
        'quietHoursStart': _string(start),
        'quietHoursEnd': _string(end),
        'timezone': 'America/Detroit',
      });
      ref.invalidate(notificationPreferenceProvider);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to save notification preferences');
      }
    }
  }
  Future<void> togglePush(bool enabled) async {
    if (!enabled) { setState(() => push = false); await save(); return; }
    final client = await FirebasePushClient.create();
    if (client == null || !await client.requestPermission()) { if (mounted) setState(() { push = false; error = 'Notifications are disabled in system settings.'; }); return; }
    final token = await client.token();
    if (token == null) { if (mounted) setState(() { push = false; error = 'Unable to register this device for notifications.'; }); return; }
    await ref.read(notificationRepoProvider).registerToken(token);
    await storage.write(key: 'fcmToken', value: token);
    client.onTokenRefresh.listen((next) async { await ref.read(notificationRepoProvider).registerToken(next); await storage.write(key: 'fcmToken', value: next); });
    if (mounted) { setState(() => push = true); await save(); }
  }

  @override
  Widget build(BuildContext c) {
    final preference = ref.watch(notificationPreferenceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: preference.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Unable to load notification preferences'),
        ),
        data: (value) {
          load(value);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Choose which useful alerts you receive.'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
              SwitchListTile(
                title: const Text('Push Notifications'),
                value: push,
                onChanged: togglePush,
              ),
              SwitchListTile(
                title: const Text('Weekly Digest'),
                value: digest,
                onChanged: (v) {
                  setState(() => digest = v);
                  save();
                },
              ),
              SwitchListTile(
                title: const Text('Price Alerts'),
                value: price,
                onChanged: (v) {
                  setState(() => price = v);
                  save();
                },
              ),
              SwitchListTile(
                title: const Text('Savings Alerts'),
                value: savings,
                onChanged: (v) {
                  setState(() => savings = v);
                  save();
                },
              ),
              SwitchListTile(
                title: const Text('Cost Alerts'),
                value: cost,
                onChanged: (v) {
                  setState(() => cost = v);
                  save();
                },
              ),
              SwitchListTile(
                title: const Text('Sync Alerts'),
                value: sync,
                onChanged: (v) {
                  setState(() => sync = v);
                  save();
                },
              ),
              ListTile(
                title: const Text('Quiet Hours'),
                subtitle: Text(
                  start == null
                      ? 'Not set'
                      : '${start!.format(c)} – ${end?.format(c) ?? ''}',
                ),
                onTap: () async {
                  final s = await showTimePicker(
                    context: c,
                    initialTime: start ?? const TimeOfDay(hour: 22, minute: 0),
                  );
                  if (s == null || !c.mounted) {
                    return;
                  }
                  final e = await showTimePicker(
                    context: c,
                    initialTime: end ?? const TimeOfDay(hour: 7, minute: 0),
                  );
                  if (e != null) {
                    setState(() {
                      start = s;
                      end = e;
                    });
                    save();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
