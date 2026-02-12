import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';

Future<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> answerCall(
  String callId,
  RTCPeerConnection pc,
  MediaStream localStream,
) async {
  final callDoc = FirebaseFirestore.instance.collection('calls').doc(callId);

  // Add local tracks
  for (final track in localStream.getTracks()) {
    pc.addTrack(track, localStream);
  }

  final snapshot = await callDoc.get();
  final data = snapshot.data();

  if (data == null) {
    throw Exception('Call document has no data');
  }

  final offer = data['offer'] as Map<String, dynamic>?;
  if (offer == null) {
    throw Exception('Offer is missing in call document');
  }

  // Set remote description
  await pc.setRemoteDescription(
    RTCSessionDescription(
      offer['sdp'],
      offer['type'],
    ),
  );

  // Create answer
  final answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);

  await callDoc.update({
    'answer': {
      'sdp': answer.sdp,
      'type': answer.type,
    },
    'status': 'connected',
  });

  // Send ICE candidates
  pc.onIceCandidate = (candidate) async {
    if (candidate.candidate == null) return;
    try {
      await callDoc.collection('receiverIce').add(candidate.toMap());
    } catch (e) {
      debugPrint('Failed to add ICE candidate: $e');
    }
  };

  final sub = callDoc.collection('callerIce').snapshots().listen((snap) async {
    for (var doc in snap.docs) {
      final cand = doc.data();
      try {
        await pc.addCandidate(RTCIceCandidate(
          cand['candidate'],
          cand['sdpMid'],
          cand['sdpMLineIndex'],
        ));
      } catch (e) {
        debugPrint('Failed to add ICE candidate: $e');
      }
    }
  });

  return sub;
}
