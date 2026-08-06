import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme.dart';

class ChainItLeaderboard extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final int userId;
  final String nickname;

  const ChainItLeaderboard({
    super.key,
    required this.theme,
    required this.onBack,
    required this.userId,
    required this.nickname,
  });

  @override
  State<ChainItLeaderboard> createState() => _ChainItLeaderboardState();
}

class _ChainItLeaderboardState extends State<ChainItLeaderboard> {
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _monthly = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final res = await http.get(
        Uri.parse('/api/chainit/leaderboard'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _daily = List<Map<String, dynamic>>.from(data['daily'] ?? []);
          _monthly = List<Map<String, dynamic>>.from(data['monthly'] ?? []);
          _history = List<Map<String, dynamic>>.from(data['history'] ?? []);
        });
      }
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
              const Text(
                'Chain.IT Leaderboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    left: 40,
                    right: 40,
                    top: 32,
                    bottom: 20,
                  ),
                  child: Column(
                    children: [
                      // Daily + Monthly side by side (or stacked on narrow screens)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121213).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3A3A3C)),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 400) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildDailyList()),
                                  const SizedBox(width: 24),
                                  Expanded(child: _buildMonthlyList()),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDailyList(),
                                const SizedBox(height: 24),
                                _buildMonthlyList(),
                              ],
                            );
                          },
                        ),
                      ),
                      // History below
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildHistory(),
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

  Widget _buildDailyList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Results",
          style: TextStyle(
            color: widget.theme.correct,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Fewest steps wins',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (_daily.isEmpty)
          const Text(
            'No results yet',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          )
        else
          ..._daily.asMap().entries.map((e) {
            final i = e.key;
            final row = e.value;
            final isMe = row['name'] == widget.nickname;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? widget.theme.correct.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: isMe
                    ? Border.all(
                        color: widget.theme.correct.withOpacity(0.3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '#${i + 1}',
                      style: TextStyle(
                        color: i == 0 ? widget.theme.correct : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row['name'] ?? '',
                      style: TextStyle(
                        color: isMe ? widget.theme.correct : Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${row['steps']} steps',
                    style: TextStyle(
                      color: widget.theme.correct,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMonthlyList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly Standings',
          style: TextStyle(
            color: widget.theme.correct,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Total steps this month',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (_monthly.isEmpty)
          const Text(
            'No results yet',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          )
        else
          ..._monthly.asMap().entries.map((e) {
            final i = e.key;
            final row = e.value;
            final isMe = row['name'] == widget.nickname;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? widget.theme.correct.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: isMe
                    ? Border.all(
                        color: widget.theme.correct.withOpacity(0.3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '#${i + 1}',
                      style: TextStyle(
                        color: i == 0 ? widget.theme.correct : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row['name'] ?? '',
                      style: TextStyle(
                        color: isMe ? widget.theme.correct : Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${row['totalSteps']} steps',
                    style: TextStyle(
                      color: widget.theme.present,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${row['daysPlayed']}d',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHistory() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121213).withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your History',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ..._history.map((row) {
            final date = row['date'] ?? '';
            final startWord =
                (row['startWord'] ?? '').toString().toUpperCase();
            final targetWord =
                (row['targetWord'] ?? '').toString().toUpperCase();
            final steps = row['steps'];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      date,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '$startWord \u2192 $targetWord',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Text(
                    steps != null ? '$steps steps' : '\u2014',
                    style: TextStyle(
                      color: steps != null ? widget.theme.correct : Colors.grey,
                      fontSize: 12,
                      fontWeight: steps != null
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
