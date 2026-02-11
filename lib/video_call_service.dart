import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

class VideoCallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RTCPeerConnection _peerConnection;
  final MediaStream _localStream;
  final String callerId;
  final String calleeId;

  DocumentReference<Map<String, dynamic>>? callDoc;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _iceSub;
  int _seenRemoteIceCount = 0;
  bool _appliedAnswer = false;

  VideoCallService({
    required this.callerId,
    required this.calleeId,
    required RTCPeerConnection peerConnection,
    required MediaStream localStream,
  })  : _peerConnection = peerConnection,
        _localStream = localStream;

  Future<void> startCall() async {
    final callId = const Uuid().v4();
    callDoc = _firestore.collection('video_calls').doc(callId);

    await callDoc!.set({
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      'status': 'calling',
      'createdAt': FieldValue.serverTimestamp(),
      'offer': {},
      'answer': {},
      'iceCandidatesCaller': [],
      'iceCandidatesCallee': [],
    });

    for (final track in _localStream.getTracks()) {
      _peerConnection.addTrack(track, _localStream);
    }

    final offer = await _peerConnection.createOffer();
    await _peerConnection.setLocalDescription(offer);

    await callDoc!.update({
      'offer': {'sdp': offer.sdp, 'type': offer.type}
    });

    _callSub = callDoc!.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer is Map &&
          (answer['sdp'] as String?)?.isNotEmpty == true &&
          !_appliedAnswer) {
        _appliedAnswer = true;
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
        await callDoc!.update({'status': 'connected'});
      }
    });

    _peerConnection.onIceCandidate = (candidate) {
      callDoc!.update({
        'iceCandidatesCaller': FieldValue.arrayUnion([
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        ])
      });
        };

    _iceSub = callDoc!.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      final remoteIce = data['iceCandidatesCallee'] as List<dynamic>? ?? [];
      for (var i = _seenRemoteIceCount; i < remoteIce.length; i++) {
        final cand = remoteIce[i];
        if (cand is Map) {
          await _peerConnection.addCandidate(
            RTCIceCandidate(
              cand['candidate'],
              cand['sdpMid'],
              cand['sdpMLineIndex'],
            ),
          );
        }
      }
      _seenRemoteIceCount = remoteIce.length;
    });
  }

  Future<void> endCall() async {
    await callDoc?.update({'status': 'ended'});
    await _callSub?.cancel();
    await _iceSub?.cancel();
    await _peerConnection.close();
  }
}
