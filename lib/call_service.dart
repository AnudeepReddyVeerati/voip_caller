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

  String _generateCallId() {
    // Better ID generation with timestamp to ensure uniqueness
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    return '$timestamp$random';
  }

  Future<String> createCall(
    String receiverId,
    String receiverEmail, {
    String? callbackId,
  }) async {
    return _guardFirestore(() async {
      _requireUser();
      final callId = _generateCallId();
      
      // Validate receiver
      if (receiverId.isEmpty || receiverEmail.isEmpty) {
        throw AppException('Invalid receiver information.');
      }
      
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
      
      // Validate inputs
      if (message.trim().isEmpty) {
        throw AppException('Message cannot be empty.');
      }
      
      final now = Timestamp.now();
      final remindAt = Timestamp.fromDate(DateTime.now().add(remindIn));

      final callbackRef = _firestore.collection("callbacks").doc();
      await callbackRef.set({
        "callbackId": callbackRef.id,
        "callId": callId,
        "ownerId": uid,
        "ownerEmail": email,
        "targetId": targetUserId,
        "targetEmail": targetEmail,
        "message": message.trim(),
        "channel": channel,
        "status": "pending",
        "attemptCount": 0,
        "createdAt": now,
        "updatedAt": now,
        "remindAt": remindAt,
      });

      // Send notification
      await _firestore.collection("notifications").add({
        "toUserId": targetUserId,
        "fromUserId": uid,
        "fromEmail": email,
        "type": "callback_message",
        "callId": callId,
        "message": message.trim(),
        "createdAt": FieldValue.serverTimestamp(),
        "read": false,
      });

      // Update call document
      await _firestore.collection("calls").doc(callId).update({
        "callbackStatus": "pending",
        "callbackMessage": message.trim(),
        "callbackChannel": channel,
        "callbackRemindAt": remindAt,
        "callbackUpdatedAt": FieldValue.serverTimestamp(),
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
        .orderBy("createdAt", descending: true)
        .snapshots();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("notifications").doc(notificationId).update({
        "read": true,
        "readAt": FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markAllNotificationsRead() async {
    await _guardFirestore(() async {
      _requireUser();
      final snapshot = await _firestore
          .collection("notifications")
          .where("toUserId", isEqualTo: uid)
          .where("read", isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          "read": true,
          "readAt": FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    });
  }

  Future<void> deleteNotification(String notificationId) async {
    await _guardFirestore(() {
      _requireUser();
      return _firestore.collection("notifications").doc(notificationId).delete();
    });
  }

  Future<void> endCall(String callId) async {
    await _guardFirestore(() async {
      _requireUser();
      await _firestore.collection("calls").doc(callId).update({
        "status": "ended",
        "endedAt": FieldValue.serverTimestamp(),
      });
    });
  }
}

// ================= WEBRTC =================

class WebRTCCall {
  RTCPeerConnection? pc;
  MediaStream? localStream;

  StreamSubscription? answerSub;
  StreamSubscription? iceSub;
  bool _appliedAnswer = false;
  final Set<String> _seenIceIds = {};
  bool _isClosing = false;

  final _firestore = FirebaseFirestore.instance;

  final config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'iceCandidatePoolSize': 10,
  };

  Future<T> _guardFirestore<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw mapFirestoreException(e);
    }
  }

  Future<void> start(String callId, bool isCaller) async {
    try {
      pc = await createPeerConnection(config);

      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      if (localStream == null || pc == null) return;

for (var track in localStream!.getAudioTracks()) {
  track.enabled = true;
  await pc!.addTrack(track, localStream!);
}


      pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          _firestore
              .collection("calls")
              .doc(callId)
              .collection(isCaller ? "callerIce" : "receiverIce")
              .add(candidate.toMap())
              .catchError((e) {
            // Silent fail for ICE candidates
            print('Failed to add ICE candidate: $e');
          });
        }
      };

      pc!.onConnectionState = (state) {
        print('Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          // Connection failed or closed
          _handleConnectionFailure(callId);
        }
      };

      if (isCaller) {
        final offer = await pc!.createOffer();
        await pc!.setLocalDescription(offer);
        await _guardFirestore(() {
          return _firestore.collection("calls").doc(callId).update({
            "offer": offer.toMap(),
            "offerCreatedAt": FieldValue.serverTimestamp(),
          });
        });

        answerSub = _firestore
            .collection("calls")
            .doc(callId)
            .snapshots()
            .listen((doc) async {
          if (_appliedAnswer || pc == null) return;
          final data = doc.data();
          if (data == null) return;
          
          final answer = data["answer"];
          if (answer is Map && (answer["sdp"] as String?)?.isNotEmpty == true) {
            _appliedAnswer = true;
            try {
              await pc!.setRemoteDescription(
                RTCSessionDescription(answer["sdp"], answer["type"]),
              );
            } catch (e) {
              print('Failed to set remote description: $e');
            }
          }
        });

        iceSub = _listenIce(callId, "receiverIce");
      } else {
        final doc = await _guardFirestore(() {
          return _firestore.collection("calls").doc(callId).get();
        });
        
        final data = doc.data();
        if (data == null) {
          throw AppException('Call data not found.');
        }
        
        final offer = data["offer"];
        if (offer == null) {
          throw AppException('Call offer not found.');
        }

        await pc!.setRemoteDescription(
          RTCSessionDescription(offer["sdp"], offer["type"]),
        );

        final answer = await pc!.createAnswer();
        await pc!.setLocalDescription(answer);
        await _guardFirestore(() {
          return _firestore.collection("calls").doc(callId).update({
            "answer": answer.toMap(),
            "answerCreatedAt": FieldValue.serverTimestamp(),
          });
        });

        iceSub = _listenIce(callId, "callerIce");
      }
    } catch (e) {
      await _cleanup();
      rethrow;
    }
  }

  StreamSubscription _listenIce(String callId, String path) {
    return _firestore
        .collection("calls")
        .doc(callId)
        .collection(path)
        .snapshots()
        .listen(
      (snapshot) {
        for (var doc in snapshot.docs) {
          if (_seenIceIds.contains(doc.id) || pc == null) continue;
          _seenIceIds.add(doc.id);
          
          try {
            final data = doc.data();
            pc!.addCandidate(RTCIceCandidate(
              data["candidate"],
              data["sdpMid"],
              data["sdpMLineIndex"],
            ));
          } catch (e) {
            print('Failed to add ICE candidate: $e');
          }
        }
      },
      onError: (e) {
        print('Error listening to ICE candidates: $e');
      },
    );
  }

  void _handleConnectionFailure(String callId) {
    // Handle connection failure
    print('WebRTC connection failed for call: $callId');
  }

  Future<void> _cleanup() async {
    try {
      await answerSub?.cancel();
      await iceSub?.cancel();
      
      if (localStream != null) {
        for (var track in localStream!.getTracks()) {
          await track.stop();
        }
        await localStream!.dispose();
        localStream = null;
      }
      
      if (pc != null) {
        await pc!.close();
        pc = null;
      }
    } catch (e) {
      print('Error during cleanup: $e');
    }
  }

  Future<void> close(String callId) async {
    if (_isClosing) return;
    _isClosing = true;

    try {
      await _cleanup();
      
      await _guardFirestore(() {
        return _firestore.collection("calls").doc(callId).update({
          "status": "ended",
          "endedAt": FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      print('Error closing call: $e');
    } finally {
      _isClosing = false;
    }
  }

  // Toggle audio track
  void toggleAudio(bool enabled) {
    if (localStream == null) return;
    for (var track in localStream!.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  // Check if audio is enabled
  bool isAudioEnabled() {
    if (localStream == null) return false;
    final tracks = localStream!.getAudioTracks();
    return tracks.isNotEmpty && tracks.first.enabled;
  }
}