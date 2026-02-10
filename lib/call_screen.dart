import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';
import 'app_error.dart';
import 'package:permission_handler/permission_handler.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final WebRTCCall call = WebRTCCall();
  final CallService service = CallService();
  final TextEditingController _messageController = TextEditingController();

  bool _muted = false;
  bool _sendingCallback = false;
  bool _callReady = false;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _ensurePermissions() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      return false;
    }
    await Permission.camera.request();
    return true;
  }

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      try {
        final permitted = await _ensurePermissions();
        if (!permitted) {
          _showError('Microphone permission is required to start a call.');
          if (mounted) Navigator.pop(context);
          return;
        }
        await call.start(widget.callId, widget.isCaller);
        _callReady = true;
        if (!widget.isCaller) {
          await service.updateCallStatus(widget.callId, "accepted");
        }
      } on AppException catch (e) {
        _showError(e.userMessage);
      } catch (e) {
        _showError('Failed to start the call.');
      }
    });
  }

  @override
  void dispose() {
    call.close(widget.callId).catchError((_) {});
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    if (!_callReady) return;
    final tracks = call.localStream.getAudioTracks();
    if (tracks.isEmpty) return;
    final current = tracks.first.enabled;
    setState(() => _muted = !current);
    for (final t in tracks) {
      t.enabled = !current;
    }
  }

  Future<void> _showCallbackDialog({
    required String targetUserId,
    required String targetEmail,
  }) async {
    int remindMinutes = 10;
    String channel = "WhatsApp";
    _messageController.text = "I will call you back soon.";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Callback & Reminder"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: "Message to caller",
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: channel,
                decoration: const InputDecoration(labelText: "Channel"),
                items: const [
                  DropdownMenuItem(value: "WhatsApp", child: Text("WhatsApp")),
                  DropdownMenuItem(value: "Google", child: Text("Google")),
                  DropdownMenuItem(value: "Phone", child: Text("Phone")),
                ],
                onChanged: (v) {
                  if (v != null) channel = v;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: remindMinutes,
                decoration: const InputDecoration(labelText: "Remind in"),
                items: const [
                  DropdownMenuItem(value: 5, child: Text("5 minutes")),
                  DropdownMenuItem(value: 10, child: Text("10 minutes")),
                  DropdownMenuItem(value: 30, child: Text("30 minutes")),
                  DropdownMenuItem(value: 60, child: Text("1 hour")),
                ],
                onChanged: (v) {
                  if (v != null) remindMinutes = v;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Set"),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (_sendingCallback) return;
    setState(() => _sendingCallback = true);

    try {
      await service.sendCallbackRequest(
        callId: widget.callId,
        targetUserId: targetUserId,
        targetEmail: targetEmail,
        message: _messageController.text.trim(),
        channel: channel,
        remindIn: Duration(minutes: remindMinutes),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Callback reminder set.")),
        );
      }
    } on AppException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Failed to set the callback reminder.');
    } finally {
      if (mounted) setState(() => _sendingCallback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: service.callStream(widget.callId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Failed to load call details.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final targetUserId = data == null
            ? null
            : (widget.isCaller ? data["receiverId"] : data["callerId"]) as String?;
        final targetEmail = data == null
            ? null
            : (widget.isCaller ? data["receiverEmail"] : data["callerEmail"]) as String?;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (targetEmail != null)
                  Text(
                    targetEmail,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _toggleMute,
                      child: Text(_muted ? "Unmute" : "Mute"),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: (targetUserId == null || targetEmail == null || _sendingCallback)
                          ? null
                          : () => _showCallbackDialog(
                                targetUserId: targetUserId,
                                targetEmail: targetEmail,
                              ),
                      child: const Text("Callback"),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("End Call"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
