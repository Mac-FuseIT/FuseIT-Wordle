import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../models/game_state.dart';
import '../services/api_service.dart';
import '../widgets/leaderboard_table.dart';

class LeaderboardScreen extends StatefulWidget {
  final VoidCallback onBack;
  final int userId;
  final AppTheme theme;
  const LeaderboardScreen({super.key, required this.onBack, required this.userId, required this.theme});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry> _daily = [];
  List<LeaderboardEntry> _monthly = [];
  List<LeaderboardEntry> _prevTop3 = [];
  List<Map<String, dynamic>> _dayBreakdown = [];
  String _prevMonthLabel = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = await ApiService.getToday();
      final data = await ApiService.getLeaderboard(today['date'], userId: widget.userId);
      _daily = ((data['daily'] ?? []) as List).map((e) => LeaderboardEntry.fromJsonDaily(e)).toList();
      _monthly = ((data['monthly'] ?? []) as List).map((e) => LeaderboardEntry.fromJsonMonthly(e)).toList();
      _prevTop3 = ((data['previousMonth'] ?? []) as List).map((e) => LeaderboardEntry.fromJsonMonthly(e)).toList();
      _prevMonthLabel = data['previousMonthLabel'] ?? '';
      _dayBreakdown = List<Map<String, dynamic>>.from(data['dayBreakdown'] ?? []);
    } catch (_) {}
    setState(() => _loading = false);
  }

  String _formatMonth(String yyyyMm) {
    if (yyyyMm.isEmpty) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final parts = yyyyMm.split('-');
    final m = int.tryParse(parts[1]) ?? 1;
    return '${months[m - 1]} ${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
              const Text('Leaderboard', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF6AAA64))))
        else
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 40, right: 40, top: 32, bottom: 20),
                  child: Column(
                    children: [
                      // Previous month top 3
                      if (_prevTop3.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121213).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: widget.theme.correct.withValues(alpha: 0.4), width: 1),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.emoji_events, color: Color(0xFFC9B458), size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_formatMonth(_prevMonthLabel)} Winners',
                                    style: const TextStyle(color: Color(0xFFC9B458), fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.emoji_events, color: Color(0xFFC9B458), size: 22),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: _prevTop3.asMap().entries.map((e) {
                                  final i = e.key;
                                  final entry = e.value;
                                  final medals = ['🥇', '🥈', '🥉'];
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A1B),
                                      borderRadius: BorderRadius.circular(8),
                                      border: i == 0
                                          ? Border.all(color: widget.theme.correct.withValues(alpha: 0.5), width: 1)
                                          : null,
                                    ),
                                    child: Column(
                                      children: [
                                        Text(medals[i], style: const TextStyle(fontSize: 24)),
                                        const SizedBox(height: 4),
                                        Text(entry.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                        Text('${entry.totalGuesses} pts', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      // Current leaderboards
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121213).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3A3A3C), width: 1),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 500) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: LeaderboardTable(title: "Today's Results", entries: _daily, accentColor: widget.theme.correct)),
                                  const SizedBox(width: 24),
                                  Expanded(child: LeaderboardTable(title: 'Monthly Standings', entries: _monthly, isMonthly: true, accentColor: widget.theme.correct)),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LeaderboardTable(title: "Today's Results", entries: _daily, accentColor: widget.theme.correct),
                                const SizedBox(height: 24),
                                LeaderboardTable(title: 'Monthly Standings', entries: _monthly, isMonthly: true, accentColor: widget.theme.correct),
                              ],
                            );
                          },
                        ),
                      ),
                      // Day-by-day breakdown
                      if (_dayBreakdown.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121213).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF3A3A3C), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Your Month Breakdown', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                'Total: ${_dayBreakdown.fold<int>(0, (sum, d) => sum + (d['numGuesses'] as int))}',
                                style: TextStyle(color: widget.theme.correct, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              ..._dayBreakdown.map((day) {
                                final played = day['played'] as bool;
                                final solved = day['solved'] as bool;
                                final guesses = day['numGuesses'] as int;
                                final word = day['word'] as String;
                                final date = day['date'] as String;
                                final length = day['length'] as int;

                                Color statusColor;
                                String statusText;
                                if (!played) {
                                  statusColor = Colors.redAccent;
                                  statusText = '+$guesses (missed)';
                                } else if (solved) {
                                  statusColor = widget.theme.correct;
                                  statusText = '$guesses ✓';
                                } else {
                                  statusColor = const Color(0xFFC9B458);
                                  statusText = '$guesses ✗';
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1B),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 90,
                                        child: Text(date, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          word.toUpperCase(),
                                          style: TextStyle(
                                            color: played ? Colors.white : Colors.grey,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ),
                                      Text('${length}L', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      const Spacer(),
                                      Text(statusText, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
