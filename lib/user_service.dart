import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> registerOrGetUser(String email, String password) async {
    try {
      final userCred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // User exists
      // ignore: avoid_print
      print('User already exists: ${userCred.user!.uid}');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        final userCred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _firestore.collection('users').doc(userCred.user!.uid).set({
          'uid': userCred.user!.uid,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // ignore: avoid_print
        print('User created: ${userCred.user!.uid}');
      } else {
        // ignore: avoid_print
        print('Auth Error: ${e.message}');
      }
    }
  }
}
