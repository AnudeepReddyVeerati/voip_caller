import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActiveCallScreenEnhanced extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String otherUserEmail;
  final String callType;
  final Function(bool) onMuteToggle;
  final Function(bool) onSpeakerToggle;
  final Function(bool) onVideoToggle;
  final Function() onEndCall;
  final Widget? videoWidget;
  final String callId;

  const ActiveCallScreenEnhanced({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserEmail,
    required this.callType,
    required this.onMuteToggle,
    required this.onSpeakerToggle,
    required this.onVideoToggle,
    required this.onEndCall,
    required this.callId,
    this.videoWidget,
  });

  @override
  State<ActiveCallScreenEnhanced> createState() =>
      _ActiveCallScreenEnhancedState();
}

class _ActiveCallScreenEnhancedState extends State<ActiveCallScreenEnhanced>
    with WidgetsBindingObserver {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoOn = true;
  int _callDurationSeconds = 0;
  late DateTime _callStartTime;
  bool _isEnding = false;

  @override
  void initState() {
    super.initState();
    _callStartTime = DateTime.now();
    _startCallTimer();
    _logCallStarted();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _logCallStarted() async {
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .update({
        'callConnectedAt': FieldValue.serverTimestamp(),
        'callStartTime': _callStartTime,
        'status': 'active',
      });

      // Update user's active calls
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({
          'currentCall': widget.callId,
          'isInCall': true,
          'lastCallStart': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error logging call start: $e');
    }
  }

  void _startCallTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _callDurationSeconds =
              DateTime.now().difference(_callStartTime).inSeconds;
        });
      }
      return mounted;
    });
  }

  String _formatDuration(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    int secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _endCallConfirm() async {
    if (_isEnding) return;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Call?'),
        content: Text(
          'Are you sure you want to end the call with ${widget.otherUserName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Call', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _endCall();
    }
  }

  Future<void> _endCall() async {
    if (_isEnding) return;
    setState(() => _isEnding = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final callEndTime = DateTime.now();
      final duration = callEndTime.difference(_callStartTime).inSeconds;

      // Update call status
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .update({
        'status': 'ended',
        'callEndTime': callEndTime,
        'durationSeconds': duration,
        'endedAt': FieldValue.serverTimestamp(),
      });

      // Save call log
      await FirebaseFirestore.instance.collection('callLogs').add({
        'callerId': currentUser.uid,
        'callerName': currentUser.displayName ?? 'User',
        'callerEmail': currentUser.email ?? '',
        'receiverId': widget.otherUserId,
        'receiverName': widget.otherUserName,
        'receiverEmail': widget.otherUserEmail,
        'callStartTime': _callStartTime,
        'callEndTime': callEndTime,
        'durationSeconds': duration,
        'callStatus': 'completed',
        'callType': widget.callType,
        'callId': widget.callId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save in user's call history
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('callHistory')
          .add({
        'contactId': widget.otherUserId,
        'contactName': widget.otherUserName,
        'contactEmail': widget.otherUserEmail,
        'callType': widget.callType,
        'duration': duration,
        'timestamp': FieldValue.serverTimestamp(),
        'callStatus': 'completed',
      });

      // Update user's call status
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'currentCall': null,
        'isInCall': false,
        'lastCallEnd': FieldValue.serverTimestamp(),
      });

      widget.onEndCall();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      print('Error ending call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending call: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isEnding = false);
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    widget.onMuteToggle(_isMuted);

    // Log mute action
    _logCallAction('mute', _isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    widget.onSpeakerToggle(_isSpeakerOn);

    // Log speaker action
    _logCallAction('speaker', _isSpeakerOn);
  }

  void _toggleVideo() {
    setState(() => _isVideoOn = !_isVideoOn);
    widget.onVideoToggle(_isVideoOn);

    // Log video action
    _logCallAction('video', _isVideoOn);
  }

  Future<void> _logCallAction(String action, bool state) async {
    try {
      await FirebaseFirestore.instance.collection('callActions').add({
        'callId': widget.callId,
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'action': action,
        'state': state ? 'on' : 'off',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error logging call action: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _endCallConfirm();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Video/Background Layer
            if (widget.callType == 'video' && widget.videoWidget != null)
              widget.videoWidget!
            else
              _buildAudioPlaceholder(),

            // Top Info Bar
            _buildTopInfoBar(),

            // Bottom Controls
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.blue.shade800],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.otherUserName.isNotEmpty
                      ? widget.otherUserName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              widget.otherUserName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Call in progress',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _formatDuration(_callDurationSeconds),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: Colors.greenAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopInfoBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserName,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDuration(_callDurationSeconds),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.callType == 'video' ? '📹' : '🎙️',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.callType == 'video' ? 'Video' : 'Audio',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Control Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    color: _isMuted ? Colors.red.shade600 : Colors.grey.shade700,
                    onTap: _toggleMute,
                  ),
                  _buildControlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    color: _isSpeakerOn ? Colors.blue.shade600 : Colors.grey.shade700,
                    onTap: _toggleSpeaker,
                  ),
                  if (widget.callType == 'video')
                    _buildControlButton(
                      icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
                      label: _isVideoOn ? 'Video' : 'No Video',
                      color: _isVideoOn ? Colors.blue.shade600 : Colors.red.shade600,
                      onTap: _toggleVideo,
                    ),
                ],
              ),
              const SizedBox(height: 28),

              // End Call Button
              GestureDetector(
                onTap: _isEnding ? null : _endCallConfirm,
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isEnding)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 24,
                        ),
                      const SizedBox(width: 12),
                      const Text(
                        'End Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
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
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}