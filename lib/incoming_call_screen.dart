import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  final QueryDocumentSnapshot call;
  const IncomingCallScreen({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(call["callerEmail"], style: const TextStyle(color: Colors.white, fontSize: 22)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(callId: call["callId"], isCaller: false),
                  ),
                );
              },
              child: const Text("Accept"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context),
              child: const Text("Reject"),
            ),
          ],
        ),
      ),
    );
  }
}
