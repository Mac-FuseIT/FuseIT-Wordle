import 'package:flutter/material.dart';
import '../../models/app_theme.dart';
import '../services/crossword_api.dart';

class CrosswordLeaderboard extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  const CrosswordLeaderboard({super.key, required this.theme, required this.onBack});

  @override
  State<CrosswordLeaderboard> createState() => _CrosswordLeaderboardState();
}

class _CrosswordLeaderboardState extends State<CrosswordLeaderboard> {
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _monthly = [];
  String? _currentUser;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await CrosswordApi.getLeaderboard();
      _daily = List<Map<String, dynamic>>.from(data['daily'] ?? []);
      _monthly = List<Map<String, dynamic>>.from(data['monthly'] ?? []);
      _currentUser = data['currentUserName'];
    } catch (_) {}
    setState(() => _loading = false);
  }

  String _formatTime(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _buildTable(String title, List<Map<String, dynamic>> entries, String timeKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (entries.isEmpty) const Text('No entries yet', style: TextStyle(color: Colors.grey)),
        ...entries.asMap().entries.map((e) {
          final i = e.key;
          final entry = e.value;
          final isMe = _currentUser != null && entry['name'].toString().toLowerCase() == _currentUser!.toLowerCase();
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isMe ? widget.theme.correct.withValues(alpha: 0.25) : i == 0 ? widget.theme.correct.withValues(alpha: 0.1) : const Color(0xFF1A1A1B),
              borderRadius: BorderRadius.circular(4),
              border: isMe ? Border.all(color: widget.theme.correct.withValues(alpha: 0.6)) : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${i + 1}.', style: TextStyle(color: isMe ? widget.theme.correct : Colors.grey, fontSize: 14))),
                Expanded(child: Text(isMe ? '${entry['name']} (you)' : entry['name'], style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: isMe ? FontWeight.bold : FontWeight.normal))),
                Text(_formatTime(entry[timeKey] as int), style: TextStyle(color: isMe ? widget.theme.correct : Colors.grey, fontSize: 14)),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
            const Text('Cross.IT Leaderboard', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        if (_loading)
          Expanded(child: Center(child: CircularProgressIndicator(color: widget.theme.correct)))
        else
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 40, right: 40, top: 32, bottom: 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121213).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3A3A3C)),
                    ),
                    child: LayoutBuilder(builder: (context, constraints) {
                      if (constraints.maxWidth > 500) {
                        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: _buildTable("Today's Times", _daily, 'timeSeconds')),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTable('Monthly Avg Time', _monthly, 'avgTime')),
                        ]);
                      }
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildTable("Today's Times", _daily, 'timeSeconds'),
                        const SizedBox(height: 24),
                        _buildTable('Monthly Avg Time', _monthly, 'avgTime'),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
