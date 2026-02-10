import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'call_service.dart';
import 'login_screen.dart';
import 'app_error.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } on FirebaseException catch (e) {
    final appError = mapFirestoreException(e);
    debugPrint('Firebase init failed: ${appError.code} - ${appError.originalMessage}');
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    service.setUserOffline().catchError((_) {});
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      service.setUserOnline().catchError((_) {});
    } else {
      service.setUserOffline().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
    );
  }
}
