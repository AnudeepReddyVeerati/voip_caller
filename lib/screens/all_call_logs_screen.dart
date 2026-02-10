import 'package:flutter/material.dart';
import '../call_log_service.dart';
import '../call_model.dart';

class AllCallLogsScreen extends StatefulWidget {
  const AllCallLogsScreen({super.key});

  @override
  State<AllCallLogsScreen> createState() => _AllCallLogsScreenState();
}

class _AllCallLogsScreenState extends State<AllCallLogsScreen> {
  final CallLogService _callLogService = CallLogService();
  List<CallLog> _allCallLogs = [];
  bool _isLoading = true;
  String _filterType = 'all'; // all, video, audio
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAllCallLogs();
  }

  Future<void> _loadAllCallLogs() async {
    setState(() => _isLoading = true);
    final logs = await _callLogService.getAllCallLogs(limit: 500);
    if (!mounted) return;
    setState(() {
      _allCallLogs = logs;
      _isLoading = false;
    });
  }

  List<CallLog> get _filteredLogs {
    var filtered = _allCallLogs;

    if (_filterType == 'video') {
      filtered = filtered.where((log) => log.callType == 'video').toList();
    } else if (_filterType == 'audio') {
      filtered = filtered.where((log) => log.callType == 'audio').toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (log) =>
                log.callerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.callerEmail.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.receiverName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.receiverEmail.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Call Logs'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllCallLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allCallLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.phone_missed, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No call logs found',
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name or email...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', 'all'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Video', 'video'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Audio', 'audio'),
                          ],
                        ),
                      ),
                    ),
                    _buildStatisticsWidget(),
                    Expanded(
                      child: _filteredLogs.isEmpty
                          ? const Center(child: Text('No calls found'))
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

  Widget _buildStatisticsWidget() {
    final stats = {
      'Total Calls': _filteredLogs.length,
      'Total Duration': _formatTotalDuration(),
      'Video Calls': _filteredLogs.where((log) => log.callType == 'video').length,
      'Audio Calls': _filteredLogs.where((log) => log.callType == 'audio').length,
    };

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: stats.entries.map((entry) {
              return Column(
                children: [
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    entry.key,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _formatTotalDuration() {
    final totalSeconds =
        _filteredLogs.fold<int>(0, (sum, log) => sum + log.durationSeconds);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _buildCallIcon(callLog),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${callLog.callerName} → ${callLog.receiverName}'),
            Text(
              '${callLog.callerEmail} → ${callLog.receiverEmail}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        subtitle: Text(
          '${callLog.formattedDate} • ${callLog.formattedTime}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              callLog.formattedDuration,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              callLog.callType == 'video' ? '📹 Video' : '🎙️ Audio',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => _showCallDetails(callLog),
      ),
    );
  }

  Widget _buildCallIcon(CallLog callLog) {
    return Container(
      decoration: BoxDecoration(
        color: callLog.callType == 'video'
            ? Colors.blue.withOpacity(0.2)
            : Colors.green.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        callLog.callType == 'video' ? Icons.videocam : Icons.call,
        color: callLog.callType == 'video' ? Colors.blue : Colors.green,
      ),
    );
  }

  void _showCallDetails(CallLog callLog) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Caller:',
                '${callLog.callerName}\n(${callLog.callerEmail})',
              ),
              _buildDetailRow(
                'Receiver:',
                '${callLog.receiverName}\n(${callLog.receiverEmail})',
              ),
              _buildDetailRow('Date:', callLog.formattedDate),
              _buildDetailRow('Time:', callLog.formattedTime),
              _buildDetailRow('Duration:', callLog.formattedDuration),
              _buildDetailRow('Type:', callLog.callType.toUpperCase()),
              _buildDetailRow('Status:', callLog.callStatus),
              _buildDetailRow('Caller ID:', callLog.callerId),
              _buildDetailRow('Receiver ID:', callLog.receiverId),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
