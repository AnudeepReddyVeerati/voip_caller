import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';

Future<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> answerCall(
  String callId,
  RTCPeerConnection pc,
  MediaStream localStream,
) async {
  final callDoc =
      FirebaseFirestore.instance.collection('video_calls').doc(callId);

  for (final track in localStream.getTracks()) {
    pc.addTrack(track, localStream);
  }

  final snapshot = await callDoc.get();
  final data = snapshot.data();
  if (data == null) return;

  final offer = data['offer'] as Map<String, dynamic>?;
  if (offer == null) return;
  await pc.setRemoteDescription(
    RTCSessionDescription(offer['sdp'], offer['type']),
  );

  final answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);
  await callDoc.update({
    'answer': {'sdp': answer.sdp, 'type': answer.type},
    'status': 'connected',
  });

  pc.onIceCandidate = (candidate) {
    callDoc.update({
      'iceCandidatesCallee': FieldValue.arrayUnion([
        {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      ])
    });
    };

  int seenRemoteIceCount = 0;
  final sub = callDoc.snapshots().listen((snap) async {
    final data = snap.data();
    if (data == null) return;
    final remoteIce = data['iceCandidatesCaller'] as List<dynamic>? ?? [];
    for (var i = seenRemoteIceCount; i < remoteIce.length; i++) {
      final cand = remoteIce[i];
      if (cand is Map) {
        await pc.addCandidate(
          RTCIceCandidate(
            cand['candidate'],
            cand['sdpMid'],
            cand['sdpMLineIndex'],
          ),
        );
      }
    }
    seenRemoteIceCount = remoteIce.length;
  });
  return sub;
}
