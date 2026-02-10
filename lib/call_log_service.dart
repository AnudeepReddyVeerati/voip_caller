import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_model.dart';

class CallLogService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  Future<List<CallLog>> getUserCallLogs({int limit = 50}) async {
    final uid = currentUserId;
    if (uid == null) return [];
    final snap = await _firestore
        .collection('call_logs')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => CallLog.fromDoc(d)).toList();
  }

  Future<List<CallLog>> getAllCallLogs({int limit = 500}) async {
    final snap = await _firestore
        .collection('call_logs')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => CallLog.fromDoc(d)).toList();
  }

  Future<void> deleteCallLog(String callLogId) async {
    await _firestore.collection('call_logs').doc(callLogId).delete();
  }

  Future<void> clearAllCallLogs() async {
    final uid = currentUserId;
    if (uid == null) return;
    final snap = await _firestore
        .collection('call_logs')
        .where('participants', arrayContains: uid)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> saveCallLog({
    required String callerId,
    required String callerName,
    required String callerEmail,
    required String receiverId,
    required String receiverName,
    required String receiverEmail,
    required DateTime callStartTime,
    required DateTime callEndTime,
    required String callStatus,
    required String callType,
  }) async {
    final durationSeconds =
        callEndTime.difference(callStartTime).inSeconds;
    await _firestore.collection('call_logs').add({
      'callerId': callerId,
      'callerName': callerName,
      'callerEmail': callerEmail,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverEmail': receiverEmail,
      'callStartTime': Timestamp.fromDate(callStartTime),
      'callEndTime': Timestamp.fromDate(callEndTime),
      'durationSeconds': durationSeconds < 0 ? 0 : durationSeconds,
      'callStatus': callStatus,
      'callType': callType,
      'participants': [callerId, receiverId],
      'createdAt': Timestamp.fromDate(callStartTime),
    });
  }
}
