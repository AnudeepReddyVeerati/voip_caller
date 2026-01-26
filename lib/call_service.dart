import 'dart:math';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  Future<void> setUserOnline() async {
    await _firestore.collection("users").doc(uid).set({
      "uid": uid,
      "email": _auth.currentUser!.email,
      "isOnline": true,
      "lastSeen": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setUserOffline() async {
    await _firestore.collection("users").doc(uid).update({
      "isOnline": false,
      "lastSeen": FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> usersStream() {
    return _firestore
        .collection("users")
        .where("uid", isNotEqualTo: uid)
        .snapshots();
  }

  String _callId() => Random().nextInt(999999).toString();

  Future<String> createCall(String receiverId, String receiverEmail) async {
    final callId = _callId();
    await _firestore.collection("calls").doc(callId).set({
      "callId": callId,
      "callerId": uid,
      "callerEmail": _auth.currentUser!.email,
      "receiverId": receiverId,
      "receiverEmail": receiverEmail,
      "status": "calling",
    });
    return callId;
  }

  Stream<QuerySnapshot> incomingCalls() {
    return _firestore
        .collection("calls")
        .where("receiverId", isEqualTo: uid)
        .where("status", isEqualTo: "calling")
        .snapshots();
  }
}

// ================= WEBRTC =================

class WebRTCCall {
  late RTCPeerConnection pc;
  late MediaStream localStream;

  StreamSubscription? answerSub;
  StreamSubscription? iceSub;

  final _firestore = FirebaseFirestore.instance;

  final config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ]
  };

  Future<void> start(String callId, bool isCaller) async {
    pc = await createPeerConnection(config);

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    for (var track in localStream.getAudioTracks()) {
      track.enabled = true; // 🎤 mic ON
      pc.addTrack(track, localStream);
    }

    pc.onIceCandidate = (c) {
      if (c != null) {
        _firestore
            .collection("calls")
            .doc(callId)
            .collection(isCaller ? "callerIce" : "receiverIce")
            .add(c.toMap());
      }
    };

    if (isCaller) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _firestore.collection("calls").doc(callId).update({"offer": offer.toMap()});

      answerSub = _firestore.collection("calls").doc(callId).snapshots().listen((doc) async {
        if (doc.data()?["answer"] != null) {
          final a = doc["answer"];
          await pc.setRemoteDescription(RTCSessionDescription(a["sdp"], a["type"]));
        }
      });

      iceSub = _listenIce(callId, "receiverIce");
    } else {
      final doc = await _firestore.collection("calls").doc(callId).get();
      final o = doc["offer"];
      await pc.setRemoteDescription(RTCSessionDescription(o["sdp"], o["type"]));

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _firestore.collection("calls").doc(callId).update({"answer": answer.toMap()});

      iceSub = _listenIce(callId, "callerIce");
    }
  }

  StreamSubscription _listenIce(String callId, String path) {
    return _firestore
        .collection("calls")
        .doc(callId)
        .collection(path)
        .snapshots()
        .listen((s) {
      for (var d in s.docs) {
        pc.addCandidate(RTCIceCandidate(
          d["candidate"],
          d["sdpMid"],
          d["sdpMLineIndex"],
        ));
      }
    });
  }

  Future<void> close(String callId) async {
    await answerSub?.cancel();
    await iceSub?.cancel();
    await localStream.dispose();
    await pc.close();
    await _firestore.collection("calls").doc(callId).update({"status": "ended"});
  }
}
