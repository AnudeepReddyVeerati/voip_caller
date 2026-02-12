import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callerId;
  final String callerName;
  final String callerEmail;
  final String callType;
  final String callId;

  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCallback;

  const IncomingCallScreen({
    super.key,
    required this.callerId,
    required this.callerName,
    required this.callerEmail,
    required this.callType,
    required this.callId,
    required this.onAccept,
    required this.onReject,
    required this.onCallback,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isProcessing = false;
  String? _callbackMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _logIncomingCall();
  }

  Future<void> _logIncomingCall() async {
    await FirebaseFirestore.instance
        .collection('calls') // ⚠️ USE SAME COLLECTION EVERYWHERE
        .doc(widget.callId)
        .update({
      'incomingReceivedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ================= ACCEPT =================

  Future<void> _acceptCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      widget.onAccept(); // Navigate to CallScreen
    } catch (e) {
      debugPrint("Accept error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ================= REJECT =================

  Future<void> _rejectCall() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) widget.onReject();
    } catch (e) {
      debugPrint("Reject error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ================= CALLBACK =================

  Future<void> _callbackCall() async {
    final controller = TextEditingController();

    final message = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Send Message"),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "I'll call you back soon...",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim()),
              child: const Text("Send")),
        ],
      ),
    );

    if (message == null || message.isEmpty) return;

    _callbackMessage = message;

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .update({
      'status': 'callback_later',
      'callbackMessage': message,
      'callbackAt': FieldValue.serverTimestamp(),
    });

    widget.onCallback();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade900,
                Colors.blue.shade700,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ScaleTransition(
                        scale: Tween(begin: 0.9, end: 1.1)
                            .animate(_pulseController),
                        child: CircleAvatar(
                          radius: 70,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          child: Text(
                            widget.callerName.isNotEmpty
                                ? widget.callerName[0].toUpperCase()
                                : "?",
                            style: const TextStyle(
                                fontSize: 50, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        widget.callerName,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.callerEmail,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.callType == "video"
                            ? "📹 Video Call"
                            : "🎙️ Audio Call",
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Incoming Call...",
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14),
                      )
                    ],
                  ),
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton(
  heroTag: 'incoming_reject_${widget.callId}',
  backgroundColor: Colors.red,
  onPressed: _rejectCall,
  child: const Icon(Icons.call_end),
),

FloatingActionButton(
  heroTag: 'incoming_accept_${widget.callId}',
  backgroundColor: Colors.green,
  onPressed: _acceptCall,
  child: const Icon(Icons.call),
),

FloatingActionButton(
  heroTag: 'incoming_callback_${widget.callId}',
  backgroundColor: Colors.orange,
  onPressed: _callbackCall,
  child: const Icon(Icons.schedule),
),

                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
