import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_service.dart';
import 'incoming_call_screen.dart';
import 'call_screen.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CallService();

    return Scaffold(
      appBar: AppBar(title: const Text("Online Users")),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: service.usersStream(),
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(
                children: s.data!.docs.map((u) {
                  return ListTile(
                    title: Text(u["email"]),
                    subtitle: Text(u["isOnline"] ? "Online" : "Offline"),
                    trailing: const Icon(Icons.call),
                    onTap: u["isOnline"]
                        ? () async {
                      final callId = await service.createCall(u["uid"], u["email"]);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CallScreen(callId: callId, isCaller: true),
                        ),
                      );
                    }
                        : null,
                  );
                }).toList(),
              );
            },
          ),
          StreamBuilder<QuerySnapshot>(
            stream: service.incomingCalls(),
            builder: (c, s) {
              if (s.hasData && s.data!.docs.isNotEmpty) {
                Future.microtask(() {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IncomingCallScreen(call: s.data!.docs.first),
                    ),
                  );
                });
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
