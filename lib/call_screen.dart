import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';
import 'app_error.dart';
import 'package:permission_handler/permission_handler.dart';
import 'video_call_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_log_service.dart';

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
  final CallLogService _callLogService = CallLogService();
  final TextEditingController _messageController = TextEditingController();

  bool _muted = false;
  bool _sendingCallback = false;
  bool _callReady = false;
  bool _isEnding = false;
  late DateTime _callStartTime;
  bool _loggedCall = false;
  String _callDuration = "00:00";

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
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

  void _startCallTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_callReady) return;
      final duration = DateTime.now().difference(_callStartTime);
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _callDuration = "$minutes:$seconds";
      });
      _startCallTimer();
    });
  }

  @override
  void initState() {
    super.initState();
    _callStartTime = DateTime.now();

    Future.microtask(() async {
      try {
        final permitted = await _ensurePermissions();
        if (!permitted) {
          _showError('Microphone permission is required to start a call.');
          if (mounted) Navigator.pop(context);
          return;
        }
        await call.start(widget.callId, widget.isCaller);
        if (mounted) {
          setState(() => _callReady = true);
          _startCallTimer();
        }
        if (!widget.isCaller) {
          await service.updateCallStatus(widget.callId, "accepted");
        }
      } on AppException catch (e) {
        _showError(e.userMessage);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        _showError('Failed to start the call.');
        if (mounted) Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    call.close(widget.callId).catchError((_) {});
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _logCall({
    required String status,
    required String callType,
    required String targetUserId,
    required String targetEmail,
  }) async {
    if (_loggedCall) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final isCaller = widget.isCaller;
      final callerId = isCaller ? currentUser.uid : targetUserId;
      final receiverId = isCaller ? targetUserId : currentUser.uid;

      final callerEmail = isCaller ? (currentUser.email ?? '') : targetEmail;
      final receiverEmail = isCaller ? targetEmail : (currentUser.email ?? '');

      final callerName =
          (isCaller ? currentUser.displayName : null) ?? callerEmail;
      final receiverName =
          (isCaller ? null : currentUser.displayName) ?? receiverEmail;

      await _callLogService.saveCallLog(
        callerId: callerId,
        callerName: callerName,
        callerEmail: callerEmail,
        receiverId: receiverId,
        receiverName: receiverName,
        receiverEmail: receiverEmail,
        callStartTime: _callStartTime,
        callEndTime: DateTime.now(),
        callStatus: status,
        callType: callType,
      );
      _loggedCall = true;
    } catch (e) {
      // Silent fail for logging
      debugPrint('Failed to log call: $e');
    }
  }

  Future<void> _toggleMute() async {
    if (!_callReady) return;
    final tracks = call.localStream?.getAudioTracks() ?? [];

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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Set Callback Reminder",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _messageController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: "Message to caller",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: channel,
                      decoration: InputDecoration(
                        labelText: "Notification Channel",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: "WhatsApp", child: Text("WhatsApp")),
                        DropdownMenuItem(value: "Google", child: Text("Google")),
                        DropdownMenuItem(value: "Phone", child: Text("Phone")),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => channel = v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: remindMinutes,
                      decoration: InputDecoration(
                        labelText: "Remind me in",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 5, child: Text("5 minutes")),
                        DropdownMenuItem(value: 10, child: Text("10 minutes")),
                        DropdownMenuItem(value: 30, child: Text("30 minutes")),
                        DropdownMenuItem(value: 60, child: Text("1 hour")),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => remindMinutes = v);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text("Set Reminder"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
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
        _showSuccess("Callback reminder set successfully!");
      }
    } on AppException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Failed to set the callback reminder.');
    } finally {
      if (mounted) setState(() => _sendingCallback = false);
    }
  }

  Future<void> _endCall(String? targetUserId, String? targetEmail) async {
    if (_isEnding) return;
    setState(() => _isEnding = true);

    if (targetUserId != null && targetEmail != null) {
      await _logCall(
        status: 'completed',
        callType: 'audio',
        targetUserId: targetUserId,
        targetEmail: targetEmail,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent accidental back navigation
        return false;
      },
      child: StreamBuilder(
        stream: service.callStream(widget.callId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load call details.',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data?.data();
          final targetUserId = data == null
              ? null
              : (widget.isCaller ? data["receiverId"] : data["callerId"]) as String?;
          final targetEmail = data == null
              ? null
              : (widget.isCaller ? data["receiverEmail"] : data["callerEmail"]) as String?;

          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Column(
                children: [
                  // Header section
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // User avatar
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade800,
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // User name/email
                        if (targetEmail != null)
                          Text(
                            targetEmail,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const SizedBox(height: 12),
                        
                        // Call status and duration
                        if (_callReady)
                          Text(
                            _callDuration,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 18,
                            ),
                          )
                        else
                          Text(
                            'Connecting...',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                          ),
                        
                        // Audio indicator
                        const SizedBox(height: 32),
                        if (_callReady)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _muted ? Icons.mic_off : Icons.mic,
                                  color: _muted ? Colors.red : Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _muted ? 'Muted' : 'Active',
                                  style: TextStyle(
                                    color: _muted ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Control buttons
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        // Top row buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildControlButton(
                              icon: _muted ? Icons.mic_off : Icons.mic,
                              label: _muted ? "Unmute" : "Mute",
                              onPressed: _callReady ? _toggleMute : null,
                              backgroundColor: _muted ? Colors.red.shade700 : Colors.white24,
                            ),
                            _buildControlButton(
                              icon: Icons.videocam,
                              label: "Video",
                              onPressed: (targetUserId == null) ? null : () {
                                final currentUser = FirebaseAuth.instance.currentUser;
                                if (currentUser == null) {
                                  _showError('Unable to start video call.');
                                  return;
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoCallScreen(
                                      callId: widget.callId,
                                      isCaller: widget.isCaller,
                                      callerId: widget.isCaller ? currentUser.uid : targetUserId,
                                      calleeId: widget.isCaller ? targetUserId : currentUser.uid,
                                    ),
                                  ),
                                );
                              },
                              backgroundColor: Colors.white24,
                            ),
                            _buildControlButton(
                              icon: Icons.schedule,
                              label: _sendingCallback ? "..." : "Callback",
                              onPressed: (targetUserId == null || targetEmail == null || _sendingCallback)
                                  ? null
                                  : () => _showCallbackDialog(
                                        targetUserId: targetUserId,
                                        targetEmail: targetEmail,
                                      ),
                              backgroundColor: Colors.white24,
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // End call button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              elevation: 4,
                            ),
                            onPressed: _isEnding
                                ? null
                                : () => _endCall(targetUserId, targetEmail),
                            child: _isEnding
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.call_end, size: 28),
                                      SizedBox(width: 8),
                                      Text(
                                        "End Call",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color backgroundColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null ? Colors.grey.shade800 : backgroundColor,
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                      color: backgroundColor.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            icon: Icon(icon, size: 28),
            color: onPressed == null ? Colors.grey.shade600 : Colors.white,
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: onPressed == null ? Colors.grey.shade600 : Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}