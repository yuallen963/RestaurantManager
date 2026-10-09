import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

abstract class PushClient {
  Future<bool> requestPermission();
  Future<String?> token();
  Stream<String> get onTokenRefresh;
}
class FirebasePushClient implements PushClient {
  FirebasePushClient._(this.messaging);
  final FirebaseMessaging messaging;
  static Future<FirebasePushClient?> create() async { try { await Firebase.initializeApp(); return FirebasePushClient._(FirebaseMessaging.instance); } catch (_) { return null; } }
  @override Future<bool> requestPermission() async { final settings = await messaging.requestPermission(); return settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional; }
  @override Future<String?> token() => messaging.getToken();
  @override Stream<String> get onTokenRefresh => messaging.onTokenRefresh;
}

class PushMessageCoordinator {
  PushMessageCoordinator(this.client);
  final FirebasePushClient? client;
  StreamSubscription<RemoteMessage>? _foreground, _opened;
  String? _consumed;
  Future<void> start({required Future<void> Function(Map<String, dynamic>) onOpen, required void Function() onForeground}) async {
    final messaging = client?.messaging;
    if (messaging == null) return;
    _foreground = FirebaseMessaging.onMessage.listen((_) => onForeground());
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) => _open(message.data, onOpen));
    final initial = await messaging.getInitialMessage();
    if (initial != null) await _open(initial.data, onOpen);
  }
  Future<void> _open(Map<String, dynamic> data, Future<void> Function(Map<String, dynamic>) callback) async { final id = data['notificationId']?.toString(); if (id == null || id.isEmpty || _consumed == id) return; _consumed = id; await callback(data); }
  Future<void> dispose() async { await _foreground?.cancel(); await _opened?.cancel(); }
}
