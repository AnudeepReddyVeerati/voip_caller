import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

class VideoCallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RTCPeerConnection _peerConnection;
  final MediaStream _localStream;
  final String callerId;
  final String calleeId;

  DocumentReference<Map<String, dynamic>>? callDoc;

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

    callDoc!.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer is Map && answer.isNotEmpty) {
        await _peerConnection.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
      }
    });

    _peerConnection.onIceCandidate = (candidate) {
      if (candidate != null) {
        callDoc!.update({
          'iceCandidatesCaller':
              FieldValue.arrayUnion([candidate.toMap()['candidate']])
        });
      }
    };

    callDoc!.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;
      final remoteIce = data['iceCandidatesCallee'] as List<dynamic>? ?? [];
      for (final cand in remoteIce) {
        await _peerConnection.addCandidate(RTCIceCandidate(cand, '', 0));
      }
    });
  }

  Future<void> endCall() async {
    await callDoc?.update({'status': 'ended'});
    await _peerConnection.close();
  }
}
