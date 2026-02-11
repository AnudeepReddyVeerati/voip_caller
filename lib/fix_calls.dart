import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FixCallsScreen extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> callDoc;




  const FixCallsScreen({super.key, required this.callDoc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fix Call Document")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Call ID: ${callDoc["callId"] ?? ""}"),
            const SizedBox(height: 8),
            Text("Caller ID: ${callDoc["callerId"] ?? ""}"),
            const SizedBox(height: 8),
            Text("Caller Name: ${callDoc["callerName"] ?? ""}"),
            const SizedBox(height: 8),
            Text("Receiver ID: ${callDoc["receiverId"] ?? ""}"),
            const SizedBox(height: 8),
            Text("Receiver Name: ${callDoc["receiverName"] ?? ""}"),
            const SizedBox(height: 8),
            Text("Call Type: ${callDoc["callType"] ?? ""}"),
            const SizedBox(height: 8),
            Text("Status: ${callDoc["status"] ?? ""}"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Update missing fields
                  await callDoc.reference.set({
                    "callerId": callDoc["callerId"] ?? "",
                    "callerName": callDoc["callerName"] ?? "Unknown Caller",
                    "callerEmail": callDoc["callerEmail"] ?? "",
                    "receiverId": callDoc["receiverId"] ?? "",
                    "receiverName": callDoc["receiverName"] ?? "Unknown Receiver",
                    "receiverEmail": callDoc["receiverEmail"] ?? "",
                    "status": callDoc["status"] ?? "calling",
                    "callType": callDoc["callType"] ?? "audio",
                    "createdAt": callDoc["createdAt"] ?? FieldValue.serverTimestamp(),
                    // Add empty offer map if missing
                    "offer": callDoc["offer"] ?? {"sdp": "", "type": "offer"},
                  }, SetOptions(merge: true));

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Call document fixed successfully!")),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to fix call: $e")),
                    );
                  }
                }
              },
              child: const Text("Fix Call Fields"),
            ),
          ],
        ),
      ),
    );
  }
}
