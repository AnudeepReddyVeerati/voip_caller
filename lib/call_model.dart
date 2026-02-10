import 'package:cloud_firestore/cloud_firestore.dart';

class CallLog {
  final String id;
  final String callerId;
  final String callerName;
  final String callerEmail;
  final String receiverId;
  final String receiverName;
  final String receiverEmail;
  final String callType; // audio | video
  final String callStatus; // missed | completed | answered | etc
  final int durationSeconds;
  final DateTime createdAt;

  CallLog({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.callerEmail,
    required this.receiverId,
    required this.receiverName,
    required this.receiverEmail,
    required this.callType,
    required this.callStatus,
    required this.durationSeconds,
    required this.createdAt,
  });

  factory CallLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CallLog(
      id: doc.id,
      callerId: data['callerId'] ?? '',
      callerName: data['callerName'] ?? '',
      callerEmail: data['callerEmail'] ?? '',
      receiverId: data['receiverId'] ?? '',
      receiverName: data['receiverName'] ?? '',
      receiverEmail: data['receiverEmail'] ?? '',
      callType: data['callType'] ?? 'audio',
      callStatus: data['callStatus'] ?? 'completed',
      durationSeconds: (data['durationSeconds'] ?? 0) as int,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return minutes > 0
        ? '${minutes}m ${seconds}s'
        : '${seconds}s';
  }

  String get formattedDate {
    final y = createdAt.year.toString().padLeft(4, '0');
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get formattedTime {
    final h = createdAt.hour.toString().padLeft(2, '0');
    final m = createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
