import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'incoming_calls';
  static const String _channelName = 'Incoming Calls';

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(const InitializationSettings(android: android, iOS: ios));

    final androidImpl =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestPermission();
    await _ensureChannel(androidImpl);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((message) async {
      final title = message.notification?.title ?? 'Incoming Call';
      final body = message.notification?.body ?? 'Tap to answer';
      await showIncomingCallNotification(title: title, body: body);
    });

    _initialized = true;
  }

  Future<void> _ensureChannel(
    AndroidFlutterLocalNotificationsPlugin? androidImpl,
  ) async {
    if (androidImpl == null) return;
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notifications for incoming calls',
      importance: Importance.max,
      playSound: true,
    );
    await androidImpl.createNotificationChannel(channel);
  }

  Future<void> showIncomingCallNotification({
    required String title,
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(presentSound: true),
    );
    await _local.show(1001, title, body, details);
  }

  Future<void> registerDeviceToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
