import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_service.dart';
import 'call_screen.dart';
import 'app_error.dart';

class IncomingCallScreen extends StatelessWidget {
  final QueryDocumentSnapshot call;
  const IncomingCallScreen({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final service = CallService();
    void showError(String message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
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
              onPressed: () async {
                try {
                  await service.updateCallStatus(call["callId"], "rejected");
                  if (context.mounted) Navigator.pop(context);
                } on AppException catch (e) {
                  showError(e.userMessage);
                } catch (e) {
                  showError('Failed to reject the call.');
                }
              },
              child: const Text("Reject"),
            ),
          ],
        ),
      ),
    );
  }
}
