import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<void> answerCall(
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
  final data = snapshot.data() as Map<String, dynamic>?;
  if (data == null) return;

  final offer = data['offer'] as Map<String, dynamic>?;
  if (offer == null) return;
  await pc.setRemoteDescription(
    RTCSessionDescription(offer['sdp'], offer['type']),
  );

  final answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);
  await callDoc.update({
    'answer': {'sdp': answer.sdp, 'type': answer.type}
  });

  pc.onIceCandidate = (candidate) {
    if (candidate != null) {
      callDoc.update({
        'iceCandidatesCallee':
            FieldValue.arrayUnion([candidate.toMap()['candidate']])
      });
    }
  };

  callDoc.snapshots().listen((snap) async {
    final data = snap.data();
    if (data == null) return;
    final remoteIce = data['iceCandidatesCaller'] as List<dynamic>? ?? [];
    for (final cand in remoteIce) {
      await pc.addCandidate(RTCIceCandidate(cand, '', 0));
    }
  });
}
