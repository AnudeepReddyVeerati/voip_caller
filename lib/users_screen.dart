import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_service.dart';
import 'incoming_call_screen.dart';
import 'call_screen.dart';
import 'app_error.dart';
import 'video_call_screen.dart';
import 'screens/call_history_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/call_history_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _inCall = false;
  bool _reminderDialogOpen = false;
  String? _activeReminderId;
  Timer? _reminderTimer;
  DateTime _now = DateTime.now();
  bool _indexWarningShown = false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleStreamError(Object? error) {
    if (_indexWarningShown) return;
    if (isMissingIndexError(error)) {
      _indexWarningShown = true;
      final e = error as FirebaseException;
      Future.microtask(() {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Missing Firestore Index'),
            content: Text(missingIndexUserMessage(e)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  Future<void> _openCall(BuildContext context, CallService service, String uid, String email,
      {String? callbackId}) async {
    try {
      setState(() => _inCall = true);
      final callId = await service.createCall(uid, email, callbackId: callbackId);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(callId: callId, isCaller: true),
        ),
      );
    } on AppException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Failed to start the call. Please try again.');
    } finally {
      if (mounted) setState(() => _inCall = false);
    }
  }

  Future<void> _openVideoCall(
    BuildContext context,
    CallService service,
    String uid,
    String email,
  ) async {
    try {
      setState(() => _inCall = true);
      final callId = await service.createCall(uid, email);
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showError('You are not logged in.');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            callId: callId,
            isCaller: true,
            callerId: currentUser.uid,
            calleeId: uid,
          ),
        ),
      );
    } on AppException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Failed to start the video call. Please try again.');
    } finally {
      if (mounted) setState(() => _inCall = false);
    }
  }
  Future<void> _showReminderDialog(
    BuildContext context,
    CallService service,
    Map<String, dynamic> callback,
  ) async {
    if (_reminderDialogOpen) return;
    if (_inCall) return;
    final callbackId = callback["id"] as String?;
    if (callbackId != null && callbackId == _activeReminderId) return;
    _reminderDialogOpen = true;
    _activeReminderId = callbackId;

    final targetEmail = callback["targetEmail"] as String? ?? "Unknown";
    final message = callback["message"] as String? ?? "";

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Callback Reminder"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(targetEmail),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(message),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, "snooze_10"),
              child: const Text("Snooze 10m"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, "unanswered"),
              child: const Text("Unanswered"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, "call_now"),
              child: const Text("Call Now"),
            ),
          ],
        );
      },
    );

    _reminderDialogOpen = false;

    if (action == null || callbackId == null) {
      _activeReminderId = null;
      return;
    }
    if (action == "snooze_10") {
      try {
        await service.rescheduleCallback(callbackId, const Duration(minutes: 10));
      } on AppException catch (e) {
        _showError(e.userMessage);
      } catch (e) {
        _showError('Failed to reschedule the reminder.');
      }
      _activeReminderId = null;
      return;
    }
    if (action == "unanswered") {
      try {
        await service.updateCallbackStatus(callbackId, "unanswered");
      } on AppException catch (e) {
        _showError(e.userMessage);
      } catch (e) {
        _showError('Failed to update the callback status.');
      }
      _activeReminderId = null;
      return;
    }
    if (action == "call_now") {
      final targetId = callback["targetId"] as String?;
      final targetEmailValue = callback["targetEmail"] as String?;
      if (targetId != null && targetEmailValue != null) {
        try {
          await service.updateCallbackStatus(callbackId, "calling_back");
          await _openCall(context, service, targetId, targetEmailValue, callbackId: callbackId);
        } on AppException catch (e) {
          _showError(e.userMessage);
        } catch (e) {
          _showError('Failed to place the callback.');
        }
      }
      _activeReminderId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = CallService();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Online Users"),
        actions: [
          IconButton(
            tooltip: 'Call History',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CallHistoryScreenEnhanced()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: service.usersStream(),
                builder: (c, s) {
                  if (s.hasError) {
                    _handleStreamError(s.error);
                    return Center(child: Text('Failed to load users.'));
                  }
                  if (!s.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView(
                      children: s.data!.docs.map((u) {
                        return ListTile(
                          title: Text(u["email"]),
                          subtitle: Text(u["isOnline"] ? "Online" : "Offline"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Voice Call',
                                icon: const Icon(Icons.call),
                                onPressed: u["isOnline"]
                                    ? () => _openCall(context, service, u["uid"], u["email"])
                                    : null,
                              ),
                              IconButton(
                                tooltip: 'Video Call',
                                icon: const Icon(Icons.videocam),
                                onPressed: u["isOnline"]
                                    ? () => _openVideoCall(
                                          context,
                                          service,
                                          u["uid"],
                                          u["email"],
                                        )
                                    : null,
                              ),
                            ],
                          ),
                          onTap: u["isOnline"]
                              ? () => _openCall(context, service, u["uid"], u["email"])
                              : null,
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: service.callbacksLogStream(),
                builder: (c, s) {
                  if (s.hasError) {
                    _handleStreamError(s.error);
                    return Center(child: Text('Failed to load call log.'));
                  }
                  if (!s.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = s.data!.docs;
                    int completed = 0;
                    int unanswered = 0;
                    int pending = 0;
                    for (final d in docs) {
                      final status = d.data()["status"];
                      if (status == "completed") completed++;
                      if (status == "unanswered") unanswered++;
                      if (status == "pending") pending++;
                    }
                    return ListView(
                      children: [
                        ListTile(
                          title: const Text("Call Log"),
                          subtitle: Text(
                            "Completed: $completed | Unanswered: $unanswered | Pending: $pending",
                          ),
                        ),
                        for (final d in docs)
                          ListTile(
                            title: Text(d.data()["targetEmail"] ?? "Unknown"),
                            subtitle: Text(_statusLabel(d.data()["status"])),
                            trailing: Text(d.data()["channel"] ?? ""),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          StreamBuilder<QuerySnapshot>(
            stream: service.incomingCalls(),
            builder: (c, s) {
              if (s.hasError) {
                _handleStreamError(s.error);
                return const SizedBox.shrink();
              }
              if (s.hasData && s.data!.docs.isNotEmpty) {
                Future.microtask(() async {
                  if (_inCall) return;
                  setState(() => _inCall = true);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
  builder: (_) {
    final doc = s.data!.docs.first;
    final data = doc.data() as Map<String, dynamic>;

    return IncomingCallScreen(
  callerId: data['callerId'] ?? '',
  callerName: data['callerName'] ?? 'Unknown',
  callerEmail: data['callerEmail'] ?? '',
  callType: data['callType'] ?? 'audio',
  callId: doc.id,

  onAccept: () async {
    // Close incoming UI
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // START WebRTC as RECEIVER
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: doc.id,
          isCaller: false,
        ),
      ),
    );
  },

  onReject: () async {
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(doc.id)
        .update({'status': 'rejected'});

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  },

  onCallback: () async {
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(doc.id)
        .update({'status': 'callback_later'});

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  },
);

  },
),

                  );
                  if (mounted) setState(() => _inCall = false);
                });
              }
              return const SizedBox.shrink();
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.pendingCallbacksStream(),
            builder: (c, s) {
              if (s.hasError) {
                _handleStreamError(s.error);
                return const SizedBox.shrink();
              }
              if (s.hasData && s.data!.docs.isNotEmpty) {
                final docs = s.data!.docs;
                QueryDocumentSnapshot<Map<String, dynamic>> dueDoc;
                try {
                  dueDoc = docs.firstWhere(
                    (d) {
                      final remindAt = d.data()["remindAt"];
                      if (remindAt is Timestamp) {
                        return remindAt.toDate().isBefore(_now) ||
                            remindAt.toDate().isAtSameMomentAs(_now);
                      }
                      return false;
                    },
                  );
                } catch (_) {
                  dueDoc = docs.first;
                }

                final remindAt = dueDoc.data()["remindAt"];
                final isDue = remindAt is Timestamp
                    ? remindAt.toDate().isBefore(_now) ||
                        remindAt.toDate().isAtSameMomentAs(_now)
                    : false;
                if (isDue) {
                  final data = dueDoc.data();
                  data["id"] = dueDoc.id;
                  Future.microtask(() => _showReminderDialog(context, service, data));
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String? status) {
  switch (status) {
    case "completed":
      return "Callback completed";
    case "unanswered":
      return "Was called back but went unanswered";
    case "calling_back":
      return "Calling back";
    case "pending":
      return "Reminder pending";
    default:
      return status ?? "Unknown";
  }
}
