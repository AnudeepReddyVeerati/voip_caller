import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../call_log_service.dart';
import '../call_model.dart';

class CallHistoryScreenEnhanced extends StatefulWidget {
  const CallHistoryScreenEnhanced({super.key});

  @override
  State<CallHistoryScreenEnhanced> createState() =>
      _CallHistoryScreenEnhancedState();
}

class _CallHistoryScreenEnhancedState extends State<CallHistoryScreenEnhanced>
    with SingleTickerProviderStateMixin {
  final CallLogService _callLogService = CallLogService();
  List<CallLog> _callLogs = [];
  bool _isLoading = true;
  String _filterType = 'all';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCallLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      _filterType = ['all', 'video', 'audio', 'missed'][_tabController.index];
    });
  }

  Future<void> _loadCallLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _callLogService.getUserCallLogs(limit: 100);
      setState(() {
        _callLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load call logs')),
        );
      }
    }
  }

  List<CallLog> get _filteredLogs {
    if (_filterType == 'all') return _callLogs;
    if (_filterType == 'video') {
      return _callLogs.where((log) => log.callType == 'video').toList();
    }
    if (_filterType == 'audio') {
      return _callLogs.where((log) => log.callType == 'audio').toList();
    }
    if (_filterType == 'missed') {
      return _callLogs.where((log) => log.callStatus == 'missed').toList();
    }
    return _callLogs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue,
        title: const Text(
          'Call History',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCallLogs,
          ),
          if (_callLogs.isNotEmpty)
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: const [
                      Icon(Icons.delete_forever, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Clear All'),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'clear') {
                  _showClearConfirmation();
                }
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(child: _buildTabLabel('All', _callLogs.length)),
            Tab(
              child: _buildTabLabel(
                'Video',
                _callLogs.where((e) => e.callType == 'video').length,
              ),
            ),
            Tab(
              child: _buildTabLabel(
                'Audio',
                _callLogs.where((e) => e.callType == 'audio').length,
              ),
            ),
            Tab(
              child: _buildTabLabel(
                'Missed',
                _callLogs.where((e) => e.callStatus == 'missed').length,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildCallsList(),
    );
  }

  Widget _buildTabLabel(String label, int count) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildCallsList() {
    if (_filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_missed,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No $_filterType calls',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      itemCount: _filteredLogs.length,
      itemBuilder: (context, index) {
        final callLog = _filteredLogs[index];
        return _buildCallLogCard(callLog);
      },
    );
  }

  Widget _buildCallLogCard(CallLog callLog) {
    final isMissed = callLog.callStatus == 'missed';
    final isIncoming = callLog.receiverId == _callLogService.currentUserId;
    final contactName =
        isIncoming ? callLog.callerName : callLog.receiverName;
    final contactInitial = contactName.isNotEmpty
        ? contactName[0].toUpperCase()
        : '?';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: isMissed
                ? LinearGradient(
                    colors: [Colors.red.shade300, Colors.red.shade500],
                  )
                : callLog.callType == 'video'
                    ? LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      )
                    : LinearGradient(
                        colors: [Colors.green.shade400, Colors.green.shade600],
                      ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              isMissed
                  ? Icons.call_missed
                  : isIncoming
                      ? Icons.call_received
                      : Icons.call_made,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        title: Text(
          contactName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            callLog.formattedDate,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMissed)
              Text(
                callLog.formattedDuration,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              )
            else
              Text(
                'Missed',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              callLog.callType == 'video' ? '📹' : '🎙️',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        onTap: () => _showCallDetails(callLog),
        onLongPress: () => _showCallOptions(callLog),
      ),
    );
  }

  void _showCallDetails(CallLog callLog) {
    final isIncoming = callLog.receiverId == _callLogService.currentUserId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Call Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Type',
                callLog.callType == 'video' ? '📹 Video' : '🎙️ Audio',
              ),
              _buildDetailRow(
                'Direction',
                isIncoming ? '📥 Incoming' : '📤 Outgoing',
              ),
              _buildDetailRow(
                'Contact',
                isIncoming ? callLog.callerName : callLog.receiverName,
              ),
              _buildDetailRow('Date', callLog.formattedDate),
              _buildDetailRow('Time', callLog.formattedTime),
              if (callLog.callStatus != 'missed')
                _buildDetailRow('Duration', callLog.formattedDuration),
              _buildDetailRow(
                'Status',
                callLog.callStatus[0].toUpperCase() +
                    callLog.callStatus.substring(1),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCallOptions(CallLog callLog) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.blue),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(context);
                _showCallDetails(callLog);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(callLog.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(String callLogId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Call Log?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _callLogService.deleteCallLog(callLogId);
              if (!mounted) return;
              Navigator.pop(context);
              _loadCallLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call log deleted')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Call Logs?'),
        content:
            const Text('This will permanently delete all your call history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _callLogService.clearAllCallLogs();
              if (!mounted) return;
              Navigator.pop(context);
              _loadCallLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All call logs cleared')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}