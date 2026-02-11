import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../incoming_call_screen.dart';
import 'active_call_screen.dart';
import 'call_history_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../call_screen.dart';


class UsersScreenEnhanced extends StatefulWidget {
  const UsersScreenEnhanced({super.key});

  @override
  State<UsersScreenEnhanced> createState() => _UsersScreenEnhancedState();
}

class _UsersScreenEnhancedState extends State<UsersScreenEnhanced> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingCallSub;
  StreamSubscription<User?>? _authSub;
  final currentUser = FirebaseAuth.instance.currentUser;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late Stream<List<Map<String, dynamic>>> _usersStream;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _updateOnlineStatus(true);
  }
  @override
  void dispose() {
  _searchController.dispose();
  _authSub?.cancel();
  _incomingCallSub?.cancel();   // <-- ADD THIS LINE
  _updateOnlineStatus(false);
  super.dispose();
}


  void _setupStreams() {
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
  _incomingCallSub?.cancel();

  _incomingCallSub = FirebaseFirestore.instance
      .collection('calls')
      .where('receiverId', isEqualTo: currentUser?.uid)
      .where('status', isEqualTo: 'ringing')
      .snapshots()
      .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {

    if (!mounted) return;

    for (final doc in snapshot.docs) {
      final data = doc.data();

      _showIncomingCallDialog(
        callerId: data['callerId'] ?? '',
        callerName: data['callerName'] ?? 'Unknown',
        callerEmail: data['callerEmail'] ?? '',
        callType: data['callType'] ?? 'video',
        callId: doc.id,
      );
    }
  });
}



void _showIncomingCallDialog({
  required String callerId,
  required String callerName,
  required String callerEmail,
  required String callType,
  required String callId,
}) {
  if (!mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return WillPopScope(
        onWillPop: () async => false,
        child: IncomingCallScreen(
          callerId: callerId,
          callerName: callerName,
          callerEmail: callerEmail,
          callType: callType,
          callId: callId,
          onAccept: () async {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop(); // close dialog
            }

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  callId: callId,
                  isCaller: false,
                ),
              ),
            );
          },
          onReject: () async {
            await _rejectCall(callId);
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
          onCallback: () async {
            await _rejectCall(callId);
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
        ),
      );
    },
  );
}



  Future<void> _acceptCall(String callId, String callerId) async {
    try {
      final callerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(callerId)
          .get();

      if (!mounted) return;

      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'accepted',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();

      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => ActiveCallScreenEnhanced(
            otherUserId: callerId,
            otherUserName: callerDoc['displayName'] ?? 'User',
            otherUserEmail: callerDoc['email'] ?? '',
            callType: 'video',
            callId: callId,
            onMuteToggle: (isMuted) {},
            onSpeakerToggle: (isSpeaker) {},
            onVideoToggle: (isOn) {},
            onEndCall: () {},
          ),
        ),
      );
    } catch (e) {
      print('Error accepting call: $e');
    }
  }

  Future<void> _rejectCall(String callId) async {
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'rejected',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error rejecting call: $e');
    }
  }

  Future<void> _initiateCall(
    String recipientId,
    String recipientName,
    String recipientEmail,
  ) async {
    try {
      final callDoc = await FirebaseFirestore.instance.collection('calls').add({
        'callerId': currentUser?.uid,
        'callerName': currentUser?.displayName ?? 'User',
        'callerEmail': currentUser?.email ?? '',
        'receiverId': recipientId,
        'receiverName': recipientName,
        'receiverEmail': recipientEmail,
        'callType': 'video',
        'status': 'ringing',
        'createdAt': FieldValue.serverTimestamp(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => ActiveCallScreenEnhanced(
            otherUserId: recipientId,
            otherUserName: recipientName,
            otherUserEmail: recipientEmail,
            callType: 'video',
            callId: callDoc.id,
            onMuteToggle: (isMuted) {},
            onSpeakerToggle: (isSpeaker) {},
            onVideoToggle: (isOn) {},
            onEndCall: () {},
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _updateOnlineStatus(bool isOnline) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser?.uid)
          .update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> _getUsersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('uid', isNotEqualTo: currentUser?.uid)
        .snapshots()
        .map((snapshot) {
      var users = snapshot.docs
          .map((doc) => {
            'uid': doc.id,
            'email': doc['email'] ?? '',
            'displayName': doc['displayName'] ?? 'User',
            'isOnline': doc['isOnline'] ?? false,
            'lastSeen': doc['lastSeen'],
          })
          .toList();

      if (_searchQuery.isNotEmpty) {
        users = users
            .where((user) =>
                user['email']
                    .toString()
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ||
                user['displayName']
                    .toString()
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
            .toList();
      }

      users.sort((a, b) => (b['isOnline'] ? 1 : 0).compareTo(a['isOnline'] ? 1 : 0));
      return users;
    });
  }

  @override
  Widget build(BuildContext context) {
    _usersStream = _getUsersStream();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue,
        title: const Text(
          'Contacts',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CallHistoryScreenEnhanced(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar with gradient
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search, color: Colors.blue),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Users list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _usersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading contacts',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                final users = snapshot.data ?? [];

                if (users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No contacts found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _buildUserCard(user);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isOnline = user['isOnline'] ?? false;
    final initials = user['displayName']
        .toString()
        .split(' ')
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: isOnline
                    ? LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      )
                    : LinearGradient(
                        colors: [Colors.grey.shade300, Colors.grey.shade400],
                      ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? Colors.green : Colors.grey,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          user['displayName'] ?? 'User',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color: isOnline ? Colors.green : Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Container(
          width: 100,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Audio call
              IconButton(
                icon: const Icon(Icons.call, color: Colors.blue, size: 22),
                onPressed: isOnline
                    ? () => _initiateCall(
                          user['uid'],
                          user['displayName'],
                          user['email'],
                        )
                    : null,
                tooltip: 'Audio Call',
              ),
              // Video call
              IconButton(
                icon: const Icon(Icons.videocam, color: Colors.blue, size: 22),
                onPressed: isOnline
                    ? () => _initiateCall(
                          user['uid'],
                          user['displayName'],
                          user['email'],
                        )
                    : null,
                tooltip: 'Video Call',
              ),
            ],
          ),
        ),
        onTap: isOnline
            ? () => _showUserDetails(user)
            : null,
      ),
    );
  }

  void _showUserDetails(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.blue.shade600],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  user['displayName']
                      .toString()
                      .split(' ')
                      .take(2)
                      .map((e) => e[0].toUpperCase())
                      .join(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Name
            Text(
              user['displayName'],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),

            // Email
            Text(
              user['email'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),

            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '● Online',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _initiateCall(
                        user['uid'],
                        user['displayName'],
                        user['email'],
                      );
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _initiateCall(
                        user['uid'],
                        user['displayName'],
                        user['email'],
                      );
                    },
                    icon: const Icon(Icons.videocam),
                    label: const Text('Video'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (Route<dynamic> route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}