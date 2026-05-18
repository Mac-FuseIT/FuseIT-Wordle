import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import 'pvp_game_screen.dart';

class PvpLobbyScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final VoidCallback onBack;

  const PvpLobbyScreen({super.key, required this.nickname, required this.userId, required this.theme, required this.onBack});

  @override
  State<PvpLobbyScreen> createState() => _PvpLobbyScreenState();
}

class _PvpLobbyScreenState extends State<PvpLobbyScreen> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _challenges = [];
  List<Map<String, dynamic>> _active = [];
  bool _loading = true;
  String? _playingSessionId;

  // Challenge setup page state
  Map<String, dynamic>? _challengingOpponent;
  String _colorChoice = 'random';
  String _timeControl = 'unlimited';

  // Waiting page state
  String? _waitingChallengeId;
  String? _waitingColorChoice;
  String? _waitingTimeControl;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await ApiService.getChessPvpLobby();
      if (mounted) setState(() {
        _users = List<Map<String, dynamic>>.from(data['users'] ?? []);
        _challenges = List<Map<String, dynamic>>.from(data['challenges'] ?? []);
        _active = List<Map<String, dynamic>>.from(data['active'] ?? []);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _sendChallenge() async {
    final id = await ApiService.createChessPvpChallenge(_challengingOpponent!['id'], _colorChoice, _timeControl);
    if (id != null && mounted) {
      setState(() { _challengingOpponent = null; _waitingChallengeId = id; _waitingColorChoice = _colorChoice; _waitingTimeControl = _timeControl; });
    }
  }

  Future<void> _acceptChallenge(Map<String, dynamic> challenge) async {
    final sessionId = await ApiService.acceptChessPvpChallenge(challenge['id']);
    if (sessionId != null && mounted) {
      setState(() {
        _playingSessionId = sessionId;
        _waitingColorChoice = challenge['color_choice'] ?? 'random';
        _waitingTimeControl = challenge['time_control'] ?? 'unlimited';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Playing a game
    if (_playingSessionId != null) {
      return PvpGameScreen(
        sessionId: _playingSessionId!,
        userId: widget.userId,
        nickname: widget.nickname,
        theme: widget.theme,
        colorChoice: _waitingColorChoice,
        timeControl: _waitingTimeControl,
        onBack: () => setState(() { _playingSessionId = null; _waitingColorChoice = null; _waitingTimeControl = null; _load(); }),
      );
    }

    // Challenge setup page
    if (_challengingOpponent != null) return _buildChallengeSetup();

    // Waiting for opponent page
    if (_waitingChallengeId != null) return _buildWaitingPage();

    // Main lobby
    return _buildLobby();
  }

  Widget _buildChallengeSetup() {
    final name = _challengingOpponent!['name'] ?? '';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _challengingOpponent = null)),
          Text('Challenge $name', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
      ),
      const Divider(color: Color(0xFF3A3A3C), height: 1),
      Expanded(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.people, color: widget.theme.correct, size: 48),
            const SizedBox(height: 16),
            Text('vs $name', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            // Color selection
            const Text('Your color', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _chip('Random', _colorChoice == 'random', () => setState(() => _colorChoice = 'random')),
              const SizedBox(width: 12),
              _chip('White', _colorChoice == 'white', () => setState(() => _colorChoice = 'white')),
              const SizedBox(width: 12),
              _chip('Black', _colorChoice == 'black', () => setState(() => _colorChoice = 'black')),
            ]),
            const SizedBox(height: 32),
            // Time control
            const Text('Time control', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _chip('3 min', _timeControl == '3min', () => setState(() => _timeControl = '3min')),
              const SizedBox(width: 12),
              _chip('5 min', _timeControl == '5min', () => setState(() => _timeControl = '5min')),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _chip('10 min', _timeControl == '10min', () => setState(() => _timeControl = '10min')),
              const SizedBox(width: 12),
              _chip('Unlimited', _timeControl == 'unlimited', () => setState(() => _timeControl = 'unlimited')),
            ]),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _sendChallenge,
                style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Send Challenge', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ))),
    ]);
  }

  Widget _buildWaitingPage() {
    // Poll for acceptance
    Future.delayed(const Duration(seconds: 3), () async {
      if (_waitingChallengeId == null || !mounted) return;
      final data = await ApiService.getChessPvpLobby();
      final active = List<Map<String, dynamic>>.from(data['active'] ?? []);
      final match = active.where((g) => g['id'] == _waitingChallengeId || g['session_id'] == _waitingChallengeId).toList();
      if (match.isNotEmpty && mounted) {
        setState(() { _playingSessionId = match.first['session_id'] ?? _waitingChallengeId; _waitingChallengeId = null; });
      } else if (mounted) {
        setState(() {}); // trigger rebuild to poll again
      }
    });

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() { _waitingChallengeId = null; _load(); })),
          const Text('Waiting...', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
      ),
      const Divider(color: Color(0xFF3A3A3C), height: 1),
      Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: widget.theme.correct),
        const SizedBox(height: 24),
        const Text('Challenge sent!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Waiting for opponent to accept...', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () async {
            await ApiService.declineChessPvpChallenge(_waitingChallengeId!);
            setState(() { _waitingChallengeId = null; _load(); });
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3A3C)),
          child: const Text('Cancel Challenge', style: TextStyle(color: Colors.white)),
        ),
      ]))),
    ]);
  }

  Widget _buildLobby() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
          const Text('PvP Chess', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
      ),
      const Divider(color: Color(0xFF3A3A3C), height: 1),
      Expanded(
        child: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Incoming challenges
              if (_challenges.where((c) => c['opponent_id'] == widget.userId).isNotEmpty) ...[
                Text('Challenges for you', style: TextStyle(color: widget.theme.present, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._challenges.where((c) => c['opponent_id'] == widget.userId).map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.theme.present)),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c['challenger_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('${c['time_control']} • ${c['color_choice']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ])),
                    IconButton(icon: Icon(Icons.check, color: widget.theme.correct), onPressed: () => _acceptChallenge(c)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () async {
                      await ApiService.declineChessPvpChallenge(c['id']);
                      _load();
                    }),
                  ]),
                )),
                const SizedBox(height: 16),
              ],
              // Active games
              if (_active.isNotEmpty) ...[
                const Text('Active Games', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._active.map((g) => GestureDetector(
                  onTap: () => setState(() => _playingSessionId = g['session_id']),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.theme.correct)),
                    child: Row(children: [
                      Expanded(child: Text('vs ${g['challenger_id'] == widget.userId ? g['opponent_name'] : g['challenger_name']}', style: const TextStyle(color: Colors.white))),
                      Text(g['time_control'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(width: 8),
                      Icon(Icons.play_arrow, color: widget.theme.correct),
                    ]),
                  ),
                )),
                const SizedBox(height: 16),
              ],
              // Sent challenges
              if (_challenges.where((c) => c['challenger_id'] == widget.userId).isNotEmpty) ...[
                const Text('Sent Challenges', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._challenges.where((c) => c['challenger_id'] == widget.userId).map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF3A3A3C))),
                  child: Row(children: [
                    Expanded(child: Text('→ ${c['opponent_name']}', style: const TextStyle(color: Colors.white70))),
                    Text('waiting...', style: TextStyle(color: widget.theme.present, fontSize: 12)),
                  ]),
                )),
                const SizedBox(height: 16),
              ],
              // All players
              const Divider(color: Color(0xFF3A3A3C)),
              const SizedBox(height: 12),
              const Text('Players', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._users.map((u) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF3A3A3C))),
                child: Row(children: [
                  Expanded(child: Row(children: [
                    Text(u['name'] ?? '', style: const TextStyle(color: Colors.white)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(u['email'] ?? '', style: const TextStyle(color: Colors.white24, fontSize: 11), overflow: TextOverflow.ellipsis)),
                  ])),
                  GestureDetector(
                    onTap: () => setState(() { _challengingOpponent = u; _colorChoice = 'random'; _timeControl = 'unlimited'; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: widget.theme.correct, borderRadius: BorderRadius.circular(6)),
                      child: const Text('Challenge', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              )),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? widget.theme.correct : const Color(0xFF3A3A3C),
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: widget.theme.correct, width: 2) : null,
        ),
        child: Text(label, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}
