import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_log_service.dart';

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
  MediaStream? _remoteStream;

  StreamSubscription? _answerSub;
  StreamSubscription? _iceSub;

  final _firestore = FirebaseFirestore.instance;
  final _callLogService = CallLogService();
  bool _loggedCall = false;
  bool _appliedAnswer = false;
  late DateTime _callStartTime;

  final _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        // Try TCP transport for networks that block UDP
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ]
  };

  @override
  void initState() {
    super.initState();
    _callStartTime = DateTime.now();
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
          const SnackBar(
              content: Text('Camera and microphone permissions required.')),
        );
        Navigator.pop(context);
      }
      return;
    }

    _pc = await createPeerConnection(_config);

    // Log connection / ICE states for easier debugging across networks
    _pc!.onConnectionState = (state) {
      debugPrint('PeerConnection state: $state');
    };
    _pc!.onIceConnectionState = (state) {
      debugPrint('ICE connection state: $state');
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user', 'width': 1280, 'height': 720}
    });
    _localRenderer.srcObject = _localStream;
    if (mounted) setState(() {});

    for (final track in _localStream!.getTracks()) {
      _pc!.addTrack(track, _localStream!);
    }
    debugPrint(
        'Local tracks: ${_localStream!.getTracks().map((t) => t.kind).toList()}');

    _pc!.onTrack = (event) async {
      debugPrint(
          'onTrack: kind=${event.track.kind} streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) setState(() {});
        return;
      }
      _remoteStream ??= await createLocalMediaStream('remote');
      _remoteStream!.addTrack(event.track);
      _remoteRenderer.srcObject = _remoteStream;
      if (mounted) setState(() {});
    };
    final callDoc = _firestore.collection('calls').doc(widget.callId);
    await callDoc.set({
      'callId': widget.callId,
      'callerId': widget.callerId,
      'calleeId': widget.calleeId,
    }, SetOptions(merge: true));

    _pc!.onIceCandidate = (c) async {
      if (c.candidate == null) return;
      try {
        await callDoc
            .collection(widget.isCaller ? 'callerIce' : 'receiverIce')
            .add(c.toMap());
      } catch (e) {
        debugPrint('Failed to add ICE candidate: $e');
      }
    };

    if (widget.isCaller) {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await callDoc.update({
        'status': 'calling',
        'createdAt': FieldValue.serverTimestamp(),
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'offerCreatedAt': FieldValue.serverTimestamp(),
      });

      _answerSub = callDoc.snapshots().listen((doc) async {
        final data = doc.data();
        if (data == null) return;
        final answer = data['answer'];
        if (answer is Map &&
            (answer['sdp'] as String?)?.isNotEmpty == true &&
            !_appliedAnswer) {
          _appliedAnswer = true;
          try {
            await _pc!.setRemoteDescription(
              RTCSessionDescription(answer['sdp'], answer['type']),
            );
            await callDoc.update({'status': 'connected'});
          } catch (e) {
            debugPrint('Failed to set remote description: $e');
          }
        }
      });

      // listen for remote ICE candidates from callee
      _iceSub = callDoc.collection('receiverIce').snapshots().listen((snap) {
        for (var d in snap.docs) {
          final cand = d.data();
          try {
            _pc?.addCandidate(RTCIceCandidate(
                cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']));
          } catch (e) {
            debugPrint('Failed to add ICE candidate: $e');
          }
        }
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
      await callDoc.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'answerCreatedAt': FieldValue.serverTimestamp(),
        'status': 'connected',
      });

      // listen for remote ICE candidates from caller
      _iceSub = callDoc.collection('callerIce').snapshots().listen((snap) {
        for (var d in snap.docs) {
          final cand = d.data();
          try {
            _pc?.addCandidate(RTCIceCandidate(
                cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']));
          } catch (e) {
            debugPrint('Failed to add ICE candidate: $e');
          }
        }
      });
    }
  }

  Future<void> _endCall() async {
    await _answerSub?.cancel();
    await _iceSub?.cancel();
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _pc?.close();
  }

  Future<String> _getUserEmail(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data()?['email'] ?? '';
  }

  Future<void> _logCall({
    required String status,
  }) async {
    if (_loggedCall) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final isCaller = widget.isCaller;
    final callerId = isCaller ? currentUser.uid : widget.callerId;
    final receiverId = isCaller ? widget.calleeId : currentUser.uid;

    final callerEmail = isCaller
        ? (currentUser.email ?? '')
        : await _getUserEmail(widget.callerId);
    final receiverEmail = isCaller
        ? await _getUserEmail(widget.calleeId)
        : (currentUser.email ?? '');

    final callerName = callerEmail.isNotEmpty ? callerEmail : callerId;
    final receiverName = receiverEmail.isNotEmpty ? receiverEmail : receiverId;

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
      callType: 'video',
    );
    _loggedCall = true;
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
              onPressed: () async {
                await _logCall(status: 'completed');
                if (!mounted) return;
                Navigator.of(this.context).pop();
              },
              child: const Text('End'),
            ),
          ),
        ],
      ),
    );
  }
}
