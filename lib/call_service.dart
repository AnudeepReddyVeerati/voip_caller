import 'dart:math';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'app_error.dart';

class CallService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw AppException('You are not logged in.');
    }
    return user;
  }

  String get uid => _requireUser().uid;
  String? get email => _requireUser().email;

  Future<T> _guardFirestore<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw mapFirestoreException(e);
    }
  }

  Future<void> setUserOnline() async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("users").doc(uid).set({
        "uid": uid,
        "email": _auth.currentUser!.email,
        "isOnline": true,
        "lastSeen": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> setUserOffline() async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("users").doc(uid).update({
        "isOnline": false,
        "lastSeen": FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<QuerySnapshot> usersStream() {
    _requireUser();
    return _firestore
        .collection("users")
        .where("uid", isNotEqualTo: uid)
        .snapshots();
  }

  String _callId() => Random().nextInt(999999).toString();

  Future<String> createCall(
    String receiverId,
    String receiverEmail, {
    String? callbackId,
  }) async {
    return _guardFirestore(() async {
      _requireUser();
      final callId = _callId();
      await _firestore.collection("calls").doc(callId).set({
        "callId": callId,
        "callerId": uid,
        "callerEmail": _auth.currentUser!.email,
        "receiverId": receiverId,
        "receiverEmail": receiverEmail,
        "status": "calling",
        "createdAt": FieldValue.serverTimestamp(),
        if (callbackId != null) "callbackId": callbackId,
      });
      return callId;
    });
  }

  Stream<QuerySnapshot> incomingCalls() {
    _requireUser();
    return _firestore
        .collection("calls")
        .where("receiverId", isEqualTo: uid)
        .where("status", isEqualTo: "calling")
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> callStream(String callId) {
    _requireUser();
    return _firestore.collection("calls").doc(callId).snapshots();
  }

  Future<void> updateCallStatus(String callId, String status) async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("calls").doc(callId).update({
        "status": status,
        "statusUpdatedAt": FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> sendCallbackRequest({
    required String callId,
    required String targetUserId,
    required String targetEmail,
    required String message,
    required String channel,
    required Duration remindIn,
  }) async {
    await _guardFirestore(() async {
      _requireUser();
      final now = Timestamp.now();
      final remindAt = Timestamp.fromDate(DateTime.now().add(remindIn));

      final callbackRef = _firestore.collection("callbacks").doc();
      await callbackRef.set({
        "callId": callId,
        "ownerId": uid,
        "ownerEmail": email,
        "targetId": targetUserId,
        "targetEmail": targetEmail,
        "message": message,
        "channel": channel,
        "status": "pending",
        "attemptCount": 0,
        "createdAt": now,
        "updatedAt": now,
        "remindAt": remindAt,
      });

      await _firestore.collection("notifications").add({
        "toUserId": targetUserId,
        "fromUserId": uid,
        "type": "callback_message",
        "callId": callId,
        "message": message,
        "createdAt": FieldValue.serverTimestamp(),
        "read": false,
      });

      await _firestore.collection("calls").doc(callId).update({
        "callbackStatus": "pending",
        "callbackMessage": message,
        "callbackChannel": channel,
        "callbackRemindAt": remindAt,
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> pendingCallbacksStream() {
    _requireUser();
    return _firestore
        .collection("callbacks")
        .where("ownerId", isEqualTo: uid)
        .where("status", isEqualTo: "pending")
        .orderBy("remindAt")
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> callbacksLogStream() {
    _requireUser();
    return _firestore
        .collection("callbacks")
        .where("ownerId", isEqualTo: uid)
        .orderBy("createdAt", descending: true)
        .snapshots();
  }

  Future<void> updateCallbackStatus(String callbackId, String status) async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("callbacks").doc(callbackId).update({
        "status": status,
        "updatedAt": FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rescheduleCallback(String callbackId, Duration remindIn) async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("callbacks").doc(callbackId).update({
        "status": "pending",
        "attemptCount": FieldValue.increment(1),
        "updatedAt": FieldValue.serverTimestamp(),
        "remindAt": Timestamp.fromDate(DateTime.now().add(remindIn)),
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> unreadNotificationsStream() {
    _requireUser();
    return _firestore
        .collection("notifications")
        .where("toUserId", isEqualTo: uid)
        .where("read", isEqualTo: false)
        .snapshots();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("notifications").doc(notificationId).update({
        "read": true,
      });
    });
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

  Future<T> _guardFirestore<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw mapFirestoreException(e);
    }
  }

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
      await _guardFirestore(() {
        return _firestore.collection("calls").doc(callId).update({"offer": offer.toMap()});
      });

      answerSub = _firestore.collection("calls").doc(callId).snapshots().listen((doc) async {
        if (doc.data()?["answer"] != null) {
          final a = doc["answer"];
          await pc.setRemoteDescription(RTCSessionDescription(a["sdp"], a["type"]));
        }
      });

      iceSub = _listenIce(callId, "receiverIce");
    } else {
      final doc = await _guardFirestore(() {
        return _firestore.collection("calls").doc(callId).get();
      });
      final o = doc["offer"];
      await pc.setRemoteDescription(RTCSessionDescription(o["sdp"], o["type"]));

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _guardFirestore(() {
        return _firestore.collection("calls").doc(callId).update({"answer": answer.toMap()});
      });

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
    await _guardFirestore(() {
      return _firestore.collection("calls").doc(callId).update({"status": "ended"});
    });
  }
}
