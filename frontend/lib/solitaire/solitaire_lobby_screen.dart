import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import 'solitaire_game_screen.dart';
import 'solitaire_service.dart';
import 'widgets/solitaire_help_dialog.dart';

class SolitaireLobbyScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const SolitaireLobbyScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  State<SolitaireLobbyScreen> createState() => _SolitaireLobbyScreenState();
}

class _SolitaireLobbyScreenState extends State<SolitaireLobbyScreen> {
  bool _loading = true;
  bool _playing = false;

  // Today's status
  String _status = 'not_started'; // "not_started" | "in_progress" | "won" | "gave_up"
  int _points = 0;
  int _moves = 0;
  int _timeSeconds = 0;
  bool _completed = false;

  // Leaderboard
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _monthly = [];
  int _lbTab = 0; // 0 = daily, 1 = monthly

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SolitaireService.getToday(),
        SolitaireService.getLeaderboard(),
      ]);

      final today = results[0];
      final lb = results[1];

      if (today != null) {
        final status = today['status'] as String? ?? 'not_started';
        setState(() {
          _status = status;
          _points = (today['points'] as num?)?.toInt() ?? 0;
          _moves = (today['moves'] as num?)?.toInt() ?? 0;
          _timeSeconds = (today['time_seconds'] as num?)?.toInt() ?? 0;
          _completed = today['completed'] == true || status == 'won';
        });
      }

      if (lb != null) {
        setState(() {
          _daily = List<Map<String, dynamic>>.from(lb['daily'] ?? []);
          _monthly = List<Map<String, dynamic>>.from(lb['monthly'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => const SolitaireHelpDialog(),
    );
  }

  bool get _canPlay => _status != 'won' && _status != 'gave_up';

  @override
  Widget build(BuildContext context) {
    if (_playing) {
      return SolitaireGameScreen(
        theme: widget.theme,
        onBack: () => setState(() {
          _playing = false;
          _load();
        }),
        nickname: widget.nickname,
        userId: widget.userId,
      );
    }

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
              const Expanded(
                child: Text(
                  'Klond.IT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.white),
                tooltip: 'How to play',
                onPressed: _showHelp,
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusCard(),
                          const SizedBox(height: 16),
                          _buildPlayButton(),
                          const SizedBox(height: 32),
                          const Divider(color: Color(0xFF3A3A3C)),
                          const SizedBox(height: 16),
                          _buildLeaderboardTabs(),
                          const SizedBox(height: 12),
                          _buildLeaderboard(),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final IconData icon;
    final Color iconColor;
    final String title;
    final String? subtitle;

    switch (_status) {
      case 'won':
        icon = Icons.check_circle;
        iconColor = widget.theme.correct;
        title = 'Completed! $_points pts';
        subtitle =
            '$_moves moves · ${_formatTime(_timeSeconds)}';
      case 'gave_up':
        icon = Icons.flag;
        iconColor = Colors.orange;
        title = 'Gave up (1 pt)';
        subtitle = '$_moves moves · ${_formatTime(_timeSeconds)}';
      case 'in_progress':
        icon = Icons.play_circle_outline;
        iconColor = widget.theme.present;
        title = 'In progress ($_moves moves)';
        subtitle = _timeSeconds > 0 ? _formatTime(_timeSeconds) : null;
      default:
        icon = Icons.casino;
        iconColor = Colors.grey;
        title = 'Not started';
        subtitle = 'Same deck for everyone today';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayButton() {
    final String label;
    if (_status == 'won') {
      label = 'Completed — come back tomorrow!';
    } else if (_status == 'gave_up') {
      label = 'Gave up — come back tomorrow!';
    } else if (_status == 'in_progress') {
      label = 'Continue Game';
    } else {
      label = 'Play — Deal the Cards';
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _canPlay ? () => setState(() => _playing = true) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _canPlay ? widget.theme.correct : const Color(0xFF3A3A3C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _canPlay ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardTabs() {
    return Row(
      children: [
        _buildTab('Daily', 0),
        const SizedBox(width: 8),
        _buildTab('Monthly', 1),
      ],
    );
  }

  Widget _buildTab(String label, int index) {
    final selected = _lbTab == index;
    return GestureDetector(
      onTap: () => setState(() => _lbTab = index),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? widget.theme.correct.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? widget.theme.correct : const Color(0xFF3A3A3C),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? widget.theme.correct : Colors.grey,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard() {
    final data = _lbTab == 0 ? _daily : _monthly;
    final isMonthly = _lbTab == 1;

    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'No results yet. Be the first!',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    return Column(
      children: data.asMap().entries.map((entry) {
        final rank = entry.key + 1;
        final row = entry.value;
        final nickname =
            (row['nickname'] ?? row['name'] ?? '').toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: isMonthly
              ? _buildMonthlyRow(rank, nickname, row)
              : _buildDailyRow(rank, nickname, row),
        );
      }).toList(),
    );
  }

  Widget _buildDailyRow(
    int rank,
    String nickname,
    Map<String, dynamic> row,
  ) {
    final points = (row['points'] as num?)?.toInt() ?? 0;
    final moves = (row['moves'] as num?)?.toInt() ?? 0;
    final time = (row['time_seconds'] as num?)?.toInt() ?? 0;
    final completed = row['completed'] == true || row['completed'] == 1;

    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '#$rank',
            style: TextStyle(
              color: rank == 1 ? widget.theme.correct : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            nickname,
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$points pts',
          style: TextStyle(
            color: widget.theme.correct,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          completed ? '$moves moves · ${_formatTime(time)}' : 'gave up',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMonthlyRow(
    int rank,
    String nickname,
    Map<String, dynamic> row,
  ) {
    final totalPoints = (row['total_points'] as num?)?.toInt() ?? 0;
    final gamesPlayed = (row['games_played'] as num?)?.toInt() ?? 0;
    final gamesWon = (row['games_won'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '#$rank',
            style: TextStyle(
              color: rank == 1 ? widget.theme.correct : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            nickname,
            style: const TextStyle(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$totalPoints pts',
          style: TextStyle(
            color: widget.theme.correct,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$gamesWon/$gamesPlayed won',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
