import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/users_screen.dart'; // for UsersScreenEnhanced
import 'fix_calls.dart';
import 'app_error.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } on FirebaseException catch (e) {
    final appError = mapFirestoreException(e);
    debugPrint(
        'Firebase init failed: ${appError.code} - ${appError.originalMessage}');
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final CallService service = CallService();
  StreamSubscription<QuerySnapshot>? _incomingCallSub;
  StreamSubscription<User?>? _authSub;
  final Set<String> _processedCallIds = {};
  bool _isInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
    _listenToAuthChanges();
  }

  @override
  void dispose() {
    _cleanup();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await service.setUserOnline().catchError((e) {
        debugPrint('Failed to set user online: $e');
      });
      _listenForIncomingCalls();
    }
  }

  void _listenToAuthChanges() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        service.setUserOnline().catchError((_) {});
        _listenForIncomingCalls();
      } else {
        _cleanup();
      }
    });
  }

  void _cleanup() {
    _incomingCallSub?.cancel();
    _incomingCallSub = null;
    _authSub?.cancel();
    _authSub = null;
    _processedCallIds.clear();
    service.setUserOffline().catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isInForeground = true;
        service.setUserOnline().catchError((_) {});
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _isInForeground = false;
        service.setUserOffline().catchError((_) {});
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        service.setUserOffline().catchError((_) {});
        break;
    }
  }

  void _listenForIncomingCalls() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _incomingCallSub?.cancel();

    _incomingCallSub = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', whereIn: ['calling', 'incoming'])
        .snapshots()
        .listen(
      (snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;

          final doc = change.doc;
          final callId = doc.id;

          if (_processedCallIds.contains(callId)) continue;
          _processedCallIds.add(callId);

          if (!_isInForeground) continue;

          final data = doc.data();

          if (data == null) continue;

          final status = data['status'] as String?;
          if (status != 'calling' && status != 'incoming') continue;

          _showIncomingCall(doc);
        }

        final activeCallIds = snapshot.docs.map((d) => d.id).toSet();
        _processedCallIds.retainWhere((id) => activeCallIds.contains(id));
      },
      onError: (error) {
        debugPrint('Incoming call listener error: $error');
      },
      cancelOnError: false,
    );
  }

void _showIncomingCall(DocumentSnapshot<Map<String, dynamic>> doc) {
  if (!mounted) return;

  // Do nothing here.
  // UsersScreen will handle incoming calls.
}



  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VOIP App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            // Go directly to enhanced contacts/call screen
            return const UsersScreenEnhanced();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}