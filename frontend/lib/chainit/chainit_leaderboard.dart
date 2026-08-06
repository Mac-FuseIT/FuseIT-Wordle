import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';

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

class _ChainItLeaderboardState extends State<ChainItLeaderboard> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _monthly = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getChainItLeaderboard();
      setState(() {
        _daily = List<Map<String, dynamic>>.from(data['daily'] ?? []);
        _monthly = List<Map<String, dynamic>>.from(data['monthly'] ?? []);
        _history = List<Map<String, dynamic>>.from(data['history'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Failed to load leaderboard'; _loading = false; });
    }
  }

  // ---------------------------------------------------------------------------
  // Tab views
  // ---------------------------------------------------------------------------

  Widget _dailyTab() {
    if (_daily.isEmpty) {
      return _emptyState('No entries yet today');
    }
    return _scrollList(_daily.asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      final name = entry['name'] as String;
      final steps = entry['steps'] as int;
      final isMe = name == widget.nickname;
      return _leaderRow(
        rank: i + 1,
        name: name,
        trailingText: '$steps step${steps == 1 ? '' : 's'}',
        highlight: isMe,
      );
    }).toList());
  }

  Widget _monthlyTab() {
    if (_monthly.isEmpty) {
      return _emptyState('No monthly data yet');
    }
    return _scrollList(_monthly.asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      final name = entry['name'] as String;
      final totalSteps = entry['totalSteps'] as int;
      final daysPlayed = entry['daysPlayed'] as int;
      final isMe = name == widget.nickname;
      return _leaderRow(
        rank: i + 1,
        name: name,
        trailingText: '$totalSteps pts',
        subtitle: '$daysPlayed day${daysPlayed == 1 ? '' : 's'} played',
        highlight: isMe,
      );
    }).toList());
  }

  Widget _historyTab() {
    if (_history.isEmpty) {
      return _emptyState('No history yet');
    }
    return _scrollList(_history.map((entry) {
      final date = entry['date'] as String;
      final startWord = (entry['startWord'] as String).toUpperCase();
      final targetWord = (entry['targetWord'] as String).toUpperCase();
      final steps = entry['steps'];
      final stepsText = steps == null ? '-' : '$steps step${(steps as int) == 1 ? '' : 's'}';
      final played = steps != null;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    '$startWord → $targetWord',
                    style: TextStyle(
                      color: widget.theme.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              stepsText,
              style: TextStyle(
                color: played ? widget.theme.correct : Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }).toList());
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _emptyState(String msg) {
    return Center(child: Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 15)));
  }

  Widget _scrollList(List<Widget> children) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: children,
        ),
      ),
    );
  }

  Widget _leaderRow({
    required int rank,
    required String name,
    required String trailingText,
    String? subtitle,
    bool highlight = false,
  }) {
    final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: highlight
            ? widget.theme.correct.withValues(alpha: 0.15)
            : const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(6),
        border: highlight ? Border.all(color: widget.theme.correct.withValues(alpha: 0.4), width: 1) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 20))
                : Text(
                    '$rank',
                    style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: highlight ? widget.theme.correct : Colors.white,
                    fontSize: 15,
                    fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Text(
            trailingText,
            style: TextStyle(
              color: widget.theme.correct,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
              Text(
                'Chain.IT — Leaderboard',
                style: TextStyle(
                  fontFamily: 'Trebuchet MS',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: widget.theme.present, blurRadius: 8)],
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),

        // Tabs
        TabBar(
          controller: _tabController,
          indicatorColor: widget.theme.present,
          labelColor: widget.theme.present,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Monthly'),
            Tab(text: 'History'),
          ],
        ),

        // Content
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: widget.theme.present))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _dailyTab(),
                        _monthlyTab(),
                        _historyTab(),
                      ],
                    ),
        ),
      ],
    );
  }
}
