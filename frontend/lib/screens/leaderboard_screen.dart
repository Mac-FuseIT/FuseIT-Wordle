import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../services/api_service.dart';
import '../widgets/leaderboard_table.dart';

class LeaderboardScreen extends StatefulWidget {
  final VoidCallback onBack;
  const LeaderboardScreen({super.key, required this.onBack});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry> _daily = [];
  List<LeaderboardEntry> _monthly = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = await ApiService.getToday();
      final data = await ApiService.getLeaderboard(today['date']);
      _daily = ((data['daily'] ?? []) as List).map((e) => LeaderboardEntry.fromJsonDaily(e)).toList();
      _monthly = ((data['monthly'] ?? []) as List).map((e) => LeaderboardEntry.fromJsonMonthly(e)).toList();
    } catch (_) {}
    setState(() => _loading = false);
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
                  child: Container(
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
                              Expanded(child: LeaderboardTable(title: "Today's Results", entries: _daily)),
                              const SizedBox(width: 24),
                              Expanded(child: LeaderboardTable(title: 'Monthly Standings', entries: _monthly, isMonthly: true)),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LeaderboardTable(title: "Today's Results", entries: _daily),
                            const SizedBox(height: 24),
                            LeaderboardTable(title: 'Monthly Standings', entries: _monthly, isMonthly: true),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
