import 'package:flutter/material.dart';
import '../call_log_service.dart';
import '../call_model.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final CallLogService _callLogService = CallLogService();
  List<CallLog> _callLogs = [];
  bool _isLoading = true;
  String _filterType = 'all'; // all, video, audio, missed

  @override
  void initState() {
    super.initState();
    _loadCallLogs();
  }

  Future<void> _loadCallLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _callLogService.getUserCallLogs(limit: 100);
      if (!mounted) return;
      setState(() {
        _callLogs = logs;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load call logs.')),
      );
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
      appBar: AppBar(
        title: const Text('Call History'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCallLogs,
          ),
          PopupMenuButton(
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clear',
                child: Text('Clear All'),
              ),
            ],
            onSelected: (value) {
              if (value == 'clear') {
                _showClearConfirmationDialog();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _callLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.phone_missed, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No call history',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', 'all'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Video', 'video'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Audio', 'audio'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Missed', 'missed'),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filteredLogs.isEmpty
                          ? Center(child: Text('No $_filterType calls'))
                          : ListView.builder(
                              itemCount: _filteredLogs.length,
                              itemBuilder: (context, index) {
                                final callLog = _filteredLogs[index];
                                return _buildCallLogTile(callLog);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterType = value);
      },
      selectedColor: Colors.blue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
      ),
    );
  }

  Widget _buildCallLogTile(CallLog callLog) {
    final isMissed = callLog.callStatus == 'missed';
    final isIncoming =
        callLog.receiverId == _callLogService.currentUserId;

    return ListTile(
      leading: _buildCallIcon(callLog, isIncoming, isMissed),
      title: Text(
        isIncoming ? callLog.callerName : callLog.receiverName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${callLog.formattedDate} • ${callLog.formattedTime}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMissed)
            Text(
              callLog.formattedDuration,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            )
          else
            const Text(
              'Missed',
              style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 4),
          Text(
            callLog.callType == 'video' ? '📹' : '🎙️',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
      onTap: () => _showCallDetails(callLog),
      onLongPress: () => _showCallOptions(callLog),
    );
  }

  Widget _buildCallIcon(CallLog callLog, bool isIncoming, bool isMissed) {
    if (isMissed) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.call_missed, color: Colors.red),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: callLog.callType == 'video'
            ? Colors.blue.withOpacity(0.2)
            : Colors.green.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isIncoming ? Icons.call_received : Icons.call_made,
        color: callLog.callType == 'video' ? Colors.blue : Colors.green,
      ),
    );
  }

  void _showCallDetails(CallLog callLog) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('From:', callLog.callerName),
            _buildDetailRow('To:', callLog.receiverName),
            _buildDetailRow('Date:', callLog.formattedDate),
            _buildDetailRow('Time:', callLog.formattedTime),
            _buildDetailRow('Duration:', callLog.formattedDuration),
            _buildDetailRow('Type:', callLog.callType.toUpperCase()),
            _buildDetailRow('Status:', callLog.callStatus),
          ],
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
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showCallOptions(CallLog callLog) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(context);
              _deleteCallLog(callLog.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('Details'),
            onTap: () {
              Navigator.pop(context);
              _showCallDetails(callLog);
            },
          ),
        ],
      ),
    );
  }

  void _deleteCallLog(String callLogId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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

  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Call Logs?'),
        content: const Text('This will permanently delete all your call history.'),
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
