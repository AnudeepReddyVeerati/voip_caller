import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _messageOpenedSub;

  static const String _channelId = 'incoming_calls';
  static const String _channelName = 'Incoming Calls';
  static const String _channelDescription = 'Notifications for incoming calls';

  Future<void> init() async {
    if (_initialized) return;
    
    try {
      // Initialize local notifications
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      await _local.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channel for Android
      final AndroidFlutterLocalNotificationsPlugin? androidImpl =
    _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

await _ensureChannel(androidImpl);


      // Request FCM permissions
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        criticalAlert: false,
        announcement: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('User granted provisional notification permission');
      } else {
        print('User declined or has not accepted notification permission');
      }

      // Listen to foreground messages
      _messageSub = FirebaseMessaging.onMessage.listen((message) async {
        print('Received foreground message: ${message.messageId}');
        await _handleIncomingMessage(message);
      });

      // Listen to messages that opened the app
      _messageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        print('App opened from notification: ${message.messageId}');
        _handleNotificationOpen(message);
      });

      // Check if app was opened from a terminated state
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        print('App opened from terminated state: ${initialMessage.messageId}');
        _handleNotificationOpen(initialMessage);
      }

      // Register device token
      await registerDeviceToken();

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        print('FCM token refreshed: $newToken');
        _updateDeviceToken(newToken);
      });

      _initialized = true;
    } catch (e) {
      print('Failed to initialize notifications: $e');
      rethrow;
    }
  }

  Future<void> _ensureChannel(
    AndroidFlutterLocalNotificationsPlugin? androidImpl,
  ) async {
    if (androidImpl == null) return;
    
    try {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      );
      await androidImpl.createNotificationChannel(channel);
      print('Notification channel created successfully');
    } catch (e) {
      print('Failed to create notification channel: $e');
    }
  }

  Future<void> _handleIncomingMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      final title = notification.title ?? 'Incoming Call';
      final body = notification.body ?? 'Tap to answer';
      await showIncomingCallNotification(
        title: title,
        body: body,
        payload: data,
      );
    } else if (data.isNotEmpty) {
      // Handle data-only messages
      final title = data['title'] ?? 'Incoming Call';
      final body = data['body'] ?? 'Tap to answer';
      await showIncomingCallNotification(
        title: title,
        body: body,
        payload: data,
      );
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    // Handle navigation when notification is tapped
    final data = message.data;
    print('Notification opened with data: $data');
    
    // TODO: Navigate to appropriate screen based on data
    // For example: if data contains callId, navigate to call screen
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Handle local notification tap
    // You can parse the payload and navigate accordingly
  }

  Future<void> showIncomingCallNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
    int id = 1001,
  }) async {
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          color: const Color(0xFF2196F3),
          icon: '@mipmap/ic_launcher',
          fullScreenIntent: true, // Shows notification even when screen is locked
          category: AndroidNotificationCategory.call,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
          interruptionLevel: InterruptionLevel.critical,
        ),
      );
      
      await _local.show(
        id,
        title,
        body,
        details,
        payload: payload != null ? payload.toString() : null,
      );
    } catch (e) {
      print('Failed to show notification: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _local.cancel(id);
    } catch (e) {
      print('Failed to cancel notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _local.cancelAll();
    } catch (e) {
      print('Failed to cancel all notifications: $e');
    }
  }

  Future<void> registerDeviceToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user logged in, skipping token registration');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        print('Failed to get FCM token');
        return;
      }

      await _updateDeviceToken(token);
    } catch (e) {
      print('Failed to register device token: $e');
    }
  }

  Future<void> _updateDeviceToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
        'platform': _getPlatform(),
      }, SetOptions(merge: true));

      print('FCM token updated successfully: $token');
    } catch (e) {
      print('Failed to update device token: $e');
    }
  }

  String _getPlatform() {
    // You can use Platform.isAndroid/Platform.isIOS if you import dart:io
    // For now, returning generic platform info
    return 'mobile';
  }

  Future<void> unregisterDeviceToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
      });

      await FirebaseMessaging.instance.deleteToken();
      print('FCM token unregistered successfully');
    } catch (e) {
      print('Failed to unregister device token: $e');
    }
  }

  Future<void> dispose() async {
    await _messageSub?.cancel();
    await _messageOpenedSub?.cancel();
    _initialized = false;
  }

  // Get current notification permission status
  Future<bool> areNotificationsEnabled() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      print('Failed to check notification permission: $e');
      return false;
    }
  }

  // Show a callback reminder notification
  Future<void> showCallbackReminder({
    required String targetName,
    required String message,
    int id = 2001,
  }) async {
    await showIncomingCallNotification(
      title: 'Callback Reminder',
      body: 'Time to call back $targetName: $message',
      id: id,
    );
  }

  // Show a missed call notification
  Future<void> showMissedCallNotification({
    required String callerName,
    int id = 3001,
  }) async {
    await showIncomingCallNotification(
      title: 'Missed Call',
      body: 'You missed a call from $callerName',
      id: id,
    );
  }
}

// Import this in main.dart
