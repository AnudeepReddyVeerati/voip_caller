import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';

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

  @override
  void initState() {
    super.initState();

    // ✅ EARPIECE MODE (MOST RELIABLE)
    Helper.setAudioFocus();

    call.start(widget.callId, widget.isCaller);
  }

  @override
  void dispose() {
    call.close(widget.callId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context),
          child: const Text("End Call"),
        ),
      ),
    );
  }
}
