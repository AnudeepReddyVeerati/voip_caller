import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'call_model.dart';

class CallLogService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  Future<List<CallLog>> getUserCallLogs({int limit = 50}) async {
    try {
      final uid = currentUserId;
      if (uid == null) return [];
      
      final snap = await _firestore
          .collection('call_logs')
          .where('participants', arrayContains: uid)
          .orderBy('callStartTime', descending: true)
          .limit(limit)
          .get();
      
      return snap.docs.map((d) => CallLog.fromDoc(d)).toList();
    } catch (e) {
      print('Error fetching user call logs: $e');
      return [];
    }
  }

  Future<List<CallLog>> getAllCallLogs({int limit = 500}) async {
    try {
      final snap = await _firestore
          .collection('call_logs')
          .orderBy('callStartTime', descending: true)
          .limit(limit)
          .get();
      
      return snap.docs.map((d) => CallLog.fromDoc(d)).toList();
    } catch (e) {
      print('Error fetching all call logs: $e');
      return [];
    }
  }

  Future<bool> deleteCallLog(String callLogId) async {
    try {
      await _firestore.collection('call_logs').doc(callLogId).delete();
      return true;
    } catch (e) {
      print('Error deleting call log: $e');
      return false;
    }
  }

  Future<bool> clearAllCallLogs() async {
    try {
      final uid = currentUserId;
      if (uid == null) return false;
      
      final snap = await _firestore
          .collection('call_logs')
          .where('participants', arrayContains: uid)
          .get();
      
      // Use batch for better performance
    final snapshot = await _firestore.collection("calls").get();

final batch = _firestore.batch();

for (final doc in snapshot.docs) {
  batch.delete(doc.reference);
}

await batch.commit();

      
      return true;
    } catch (e) {
      print('Error clearing call logs: $e');
      return false;
    }
  }

  Future<bool> saveCallLog({
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
    try {
      // Validate inputs
      if (callerId.isEmpty || receiverId.isEmpty) {
        print('Error: Invalid user IDs');
        return false;
      }
      
      final durationSeconds = callEndTime.difference(callStartTime).inSeconds;
      
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
        'createdAt': FieldValue.serverTimestamp(), // Use server timestamp
      });
      
      return true;
    } catch (e) {
      print('Error saving call log: $e');
      return false;
    }
  }

  // Additional useful method
  Stream<List<CallLog>> getUserCallLogsStream({int limit = 50}) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    
    return _firestore
        .collection('call_logs')
        .where('participants', arrayContains: uid)
        .orderBy('callStartTime', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CallLog.fromDoc(d)).toList());
  }
}