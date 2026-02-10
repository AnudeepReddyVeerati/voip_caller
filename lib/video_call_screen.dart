import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoCallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final String callerId;
  final String calleeId;

  const VideoCallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    required this.callerId,
    required this.calleeId,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _answerSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _iceSub;

  final _firestore = FirebaseFirestore.instance;
  int _seenRemoteIceCount = 0;

  final _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ]
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _startCall();
  }

  Future<bool> _ensurePermissions() async {
    final mic = await Permission.microphone.request();
    final cam = await Permission.camera.request();
    return mic.isGranted && cam.isGranted;
  }

  Future<void> _startCall() async {
    final permitted = await _ensurePermissions();
    if (!permitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera and microphone permissions required.')),
        );
        Navigator.pop(context);
      }
      return;
    }

    _pc = await createPeerConnection(_config);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user', 'width': 1280, 'height': 720}
    });
    _localRenderer.srcObject = _localStream;
    if (mounted) setState(() {});

    for (final track in _localStream!.getTracks()) {
      _pc!.addTrack(track, _localStream!);
    }
    // ignore: avoid_print
    print('Local tracks: ${_localStream!.getTracks().map((t) => t.kind).toList()}');

    _pc!.onTrack = (event) {
      // ignore: avoid_print
      print('onTrack: kind=${event.track.kind} streams=${event.streams.length}');
      if (event.streams.isNotEmpty && event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) setState(() {});
      }
    };
    _pc!.onAddStream = (stream) {
      // ignore: avoid_print
      print('onAddStream: tracks=${stream.getTracks().map((t) => t.kind).toList()}');
      _remoteRenderer.srcObject = stream;
      if (mounted) setState(() {});
    };

    final callDoc = _firestore.collection('video_calls').doc(widget.callId);

    _pc!.onIceCandidate = (c) {
      if (c == null) return;
      final field = widget.isCaller ? 'iceCandidatesCaller' : 'iceCandidatesCallee';
      callDoc.update({
        field: FieldValue.arrayUnion([
          {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          }
        ])
      });
    };

    if (widget.isCaller) {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await callDoc.set({
        'callId': widget.callId,
        'callerId': widget.callerId,
        'calleeId': widget.calleeId,
        'status': 'calling',
        'createdAt': FieldValue.serverTimestamp(),
        'iceCandidatesCaller': [],
        'iceCandidatesCallee': [],
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'answer': {'sdp': '', 'type': 'answer'},
      }, SetOptions(merge: true));

      _answerSub = callDoc.snapshots().listen((doc) async {
        final data = doc.data();
        if (data == null) return;
        final answer = data['answer'];
        if (answer is Map && (answer['sdp'] as String).isNotEmpty) {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(answer['sdp'], answer['type']),
          );
        }
        _applyRemoteIce(data, isCaller: true);
      });
    } else {
      final doc = await callDoc.get();
      final offer = doc.data()?['offer'];
      if (offer == null) return;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await callDoc.set({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'status': 'connected',
      }, SetOptions(merge: true));

      _iceSub = callDoc.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null) return;
        _applyRemoteIce(data, isCaller: false);
      });
    }
  }

  void _applyRemoteIce(Map<String, dynamic> data, {required bool isCaller}) {
    final listKey = isCaller ? 'iceCandidatesCallee' : 'iceCandidatesCaller';
    final remoteIce = data[listKey] as List<dynamic>? ?? [];
    for (var i = _seenRemoteIceCount; i < remoteIce.length; i++) {
      final cand = remoteIce[i];
      if (cand is Map) {
        _pc?.addCandidate(
          RTCIceCandidate(
            cand['candidate'],
            cand['sdpMid'],
            cand['sdpMLineIndex'],
          ),
        );
      }
    }
    _seenRemoteIceCount = remoteIce.length;
  }

  Future<void> _endCall() async {
    await _answerSub?.cancel();
    await _iceSub?.cancel();
    await _localStream?.dispose();
    await _pc?.close();
  }

  @override
  void dispose() {
    _endCall();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            right: 16,
            top: 16,
            width: 120,
            height: 160,
            child: RTCVideoView(_localRenderer, mirror: true),
          ),
          Positioned(
            left: 16,
            bottom: 24,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context),
              child: const Text('End'),
            ),
          ),
        ],
      ),
    );
  }
}
