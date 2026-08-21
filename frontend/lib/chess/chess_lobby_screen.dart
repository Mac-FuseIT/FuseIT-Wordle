import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/help_dialog.dart';
import 'chess_game_screen.dart';
import 'phantom_game_screen.dart';
import 'pvp_lobby_screen.dart';

class ChessLobbyScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final VoidCallback onBack;

  const ChessLobbyScreen({super.key, required this.nickname, required this.userId, required this.theme, required this.onBack});

  @override
  State<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends State<ChessLobbyScreen> {
  bool _loading = true;
  bool _playing = false;
  String _playingMode = 'expert'; // which mode is currently being played
  bool _playingPhantom = false;
  bool _playingPvp = false;

  // Expert mode state
  bool _expertPlayed = false;
  bool? _expertWon;
  int? _expertMoves;
  int _expertBotLevel = 800;
  Map<String, dynamic>? _expertSession;
  String _expertPlayerColor = 'white';

  // Amateur mode state
  bool _amateurPlayed = false;
  bool? _amateurWon;
  int? _amateurMoves;
  int _amateurBotLevel = 400;
  Map<String, dynamic>? _amateurSession;
  String _amateurPlayerColor = 'white';

  // Phantom mode state
  bool _phantomPlayed = false;
  bool? _phantomWon;
  int? _phantomMoves;
  int _phantomBotLevel = 400;
  Map<String, dynamic>? _phantomSession;
  String _phantomPlayerColor = 'white';

  // Leaderboard
  int _lbTab = 0; // 0=expert, 1=amateur, 2=phantom, 3=pvp
  List<Map<String, dynamic>> _expertDaily = [];
  List<Map<String, dynamic>> _expertHistory = [];
  List<Map<String, dynamic>> _amateurDaily = [];
  List<Map<String, dynamic>> _amateurHistory = [];
  List<Map<String, dynamic>> _phantomDaily = [];
  List<Map<String, dynamic>> _phantomHistory = [];
  List<Map<String, dynamic>> _pvpLeaderboard = [];
  Map<String, dynamic>? _pvpRecord;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final expertToday = await ApiService.getChessToday(mode: 'expert');
      final amateurToday = await ApiService.getChessToday(mode: 'amateur');
      final expertLb = await ApiService.getChessLeaderboard(mode: 'expert');
      final amateurLb = await ApiService.getChessLeaderboard(mode: 'amateur');
      Map<String, dynamic> pToday = {};
      Map<String, dynamic> pLb = {};
      try { pToday = await ApiService.getPhantomChessToday(); } catch (_) {}
      try { pLb = await ApiService.getPhantomChessLeaderboard(); } catch (_) {}
      Map<String, dynamic> pvpLb = {};
      try { pvpLb = await ApiService.getChessPvpLeaderboard(); } catch (_) {}
      if (mounted) setState(() {
        // Expert
        _expertBotLevel = expertToday['botLevel'] ?? 800;
        _expertPlayed = expertToday['played'] ?? false;
        _expertWon = expertToday['won'] == null ? null : (expertToday['won'] == 1 || expertToday['won'] == true);
        _expertMoves = expertToday['moves'];
        _expertSession = expertToday['session'];
        _expertPlayerColor = expertToday['playerColor'] ?? 'white';
        _expertDaily = List<Map<String, dynamic>>.from(expertLb['daily'] ?? []);
        _expertHistory = List<Map<String, dynamic>>.from(expertLb['history'] ?? []);

        // Amateur
        _amateurBotLevel = amateurToday['botLevel'] ?? 400;
        _amateurPlayed = amateurToday['played'] ?? false;
        _amateurWon = amateurToday['won'] == null ? null : (amateurToday['won'] == 1 || amateurToday['won'] == true);
        _amateurMoves = amateurToday['moves'];
        _amateurSession = amateurToday['session'];
        _amateurPlayerColor = amateurToday['playerColor'] ?? 'white';
        _amateurDaily = List<Map<String, dynamic>>.from(amateurLb['daily'] ?? []);
        _amateurHistory = List<Map<String, dynamic>>.from(amateurLb['history'] ?? []);

        // Phantom
        _phantomBotLevel = pToday['botLevel'] ?? (_expertBotLevel ~/ 2);
        _phantomPlayed = pToday['played'] ?? false;
        _phantomWon = pToday['won'] == null ? null : (pToday['won'] == 1 || pToday['won'] == true);
        _phantomMoves = pToday['moves'];
        _phantomSession = pToday['session'];
        _phantomPlayerColor = pToday['playerColor'] ?? 'white';
        _phantomDaily = List<Map<String, dynamic>>.from(pLb['daily'] ?? []);
        _phantomHistory = List<Map<String, dynamic>>.from(pLb['history'] ?? []);

        // PvP
        _pvpLeaderboard = List<Map<String, dynamic>>.from(pvpLb['leaderboard'] ?? []);
        _pvpRecord = pvpLb['myRecord'];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_playingPvp) {
      return PvpLobbyScreen(
        nickname: widget.nickname,
        userId: widget.userId,
        theme: widget.theme,
        onBack: () => setState(() { _playingPvp = false; _load(); }),
      );
    }

    if (_playingPhantom) {
      return PhantomGameScreen(
        botLevel: _phantomBotLevel,
        theme: widget.theme,
        session: _phantomSession,
        playerColor: _phantomPlayerColor,
        onFinish: (won, moves, redos, moveHistory) async {
          await ApiService.submitPhantomChessResult(won, moves, redos, moveHistory);
          setState(() { _playingPhantom = false; });
          _load();
        },
        onBack: () => setState(() { _playingPhantom = false; _load(); }),
      );
    }

    if (_playing) {
      final isAmateur = _playingMode == 'amateur';
      return ChessGameScreen(
        botLevel: isAmateur ? _amateurBotLevel : _expertBotLevel,
        theme: widget.theme,
        session: isAmateur ? _amateurSession : _expertSession,
        playerColor: isAmateur ? _amateurPlayerColor : _expertPlayerColor,
        mode: _playingMode,
        onFinish: (won, moves, redos, moveHistory, fen) async {
          await ApiService.submitChessResult(won, moves, redos, moveHistory, fen, mode: _playingMode);
          setState(() { _playing = false; });
          _load();
        },
        onBack: () => setState(() { _playing = false; _load(); }),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
            const Text('Chess.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _loading
                  ? const CircularProgressIndicator()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Game cards side by side
                          Row(
                            children: [
                              // Normal card with Amateur/Expert sub-buttons
                              Expanded(flex: 2, child: _buildNormalCard()),
                              const SizedBox(width: 12),
                              Expanded(child: _buildGameCard(
                                title: 'Phantom',
                                elo: _phantomBotLevel,
                                played: _phantomPlayed,
                                won: _phantomWon,
                                moves: _phantomMoves,
                                hasSession: _phantomSession != null,
                                color: widget.theme.present,
                                onPlay: () => setState(() => _playingPhantom = true),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: GestureDetector(
                                onTap: () => setState(() => _playingPvp = true),
                                child: Column(children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: widget.theme.correct.withValues(alpha: 0.2),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                    ),
                                    child: Text('PvP', textAlign: TextAlign.center, style: TextStyle(color: widget.theme.correct, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  Container(
                                    width: double.infinity, height: 120,
                                    decoration: BoxDecoration(
                                      color: widget.theme.correct.withValues(alpha: 0.1),
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                      border: Border.all(color: widget.theme.correct.withValues(alpha: 0.4), width: 1.5),
                                    ),
                                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Icon(Icons.people, color: widget.theme.correct, size: 30),
                                      const SizedBox(height: 8),
                                      const Text('Challenge', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Text('Play', style: TextStyle(color: widget.theme.correct, fontSize: 13, fontWeight: FontWeight.bold)),
                                    ]),
                                  ),
                                ]),
                              )),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity, height: 44,
                            child: ElevatedButton(
                              onPressed: () => showHelpDialog(context, widget.theme, 'How to Play Chess.IT', const [
                                HelpSection(body: 'Play chess against a daily bot. The bot level changes every day.'),
                                HelpSection(heading: '🎯 Two Modes', body: 'Amateur (100-900 ELO) for casual play, Expert (Skill 0-20) for a challenge. Both can be played daily!'),
                                HelpSection(heading: '♟️ One Chance Per Mode', body: 'You get one game per mode per day. Win or lose, your result goes on the leaderboard.'),
                                HelpSection(heading: '↩️ Redo Moves', body: 'You get 2 redo moves per game if you make a mistake. Use them wisely!'),
                                HelpSection(heading: '🏆 Scoring', body: 'Win with fewer moves to rank higher. Losses show ✗ on the leaderboard.'),
                              ]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3A3A3C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('How to Play', style: TextStyle(fontSize: 16, color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Divider(color: Color(0xFF3A3A3C)),
                          const SizedBox(height: 16),
                          // Leaderboard toggle buttons
                          Row(children: [
                            Expanded(child: _lbTabBtn('Expert', 0)),
                            const SizedBox(width: 6),
                            Expanded(child: _lbTabBtn('Amateur', 1)),
                            const SizedBox(width: 6),
                            Expanded(child: _lbTabBtn('Phantom', 2)),
                            const SizedBox(width: 6),
                            Expanded(child: _lbTabBtn('PvP', 3)),
                          ]),
                          const SizedBox(height: 16),
                          if (_lbTab < 3) ...[
                            const Text("Today's Leaderboard", style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final daily = _lbTab == 0 ? _expertDaily : _lbTab == 1 ? _amateurDaily : _phantomDaily;
                              if (daily.isEmpty) {
                                return const Text('No games yet today.', style: TextStyle(color: Colors.grey, fontSize: 14));
                              }
                              return Column(children: daily.asMap().entries.map((entry) {
                                final i = entry.key;
                                final row = entry.value;
                                final won = row['won'] == true;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF3A3A3C)),
                                  ),
                                  child: Row(children: [
                                    SizedBox(width: 28, child: Text('#${i + 1}', style: TextStyle(
                                      color: i == 0 ? widget.theme.correct : Colors.grey, fontWeight: FontWeight.bold,
                                    ))),
                                    Expanded(child: Text(row['nickname'] ?? '', style: const TextStyle(color: Colors.white))),
                                    Text(
                                      won ? '${row['moves']} moves ✓' : '✗',
                                      style: TextStyle(color: won ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ]),
                                );
                              }).toList());
                            }),
                            Builder(builder: (context) {
                              final history = _lbTab == 0 ? _expertHistory : _lbTab == 1 ? _amateurHistory : _phantomHistory;
                              if (history.isEmpty) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 24),
                                  const Divider(color: Color(0xFF3A3A3C)),
                                  const SizedBox(height: 16),
                                  const Text('Your History', style: TextStyle(color: Colors.grey, fontSize: 14)),
                                  const SizedBox(height: 12),
                                  ...history.map((row) {
                                    final won = row['won'] == 1 || row['won'] == true;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1A1A1B),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF3A3A3C)),
                                      ),
                                      child: Row(children: [
                                        SizedBox(width: 90, child: Text(row['date'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                                        Text('Bot ${row['bot_level']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        const Spacer(),
                                        Text(
                                          won ? '${row['moves']} moves ✓' : '✗',
                                          style: TextStyle(color: won ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold),
                                        ),
                                      ]),
                                    );
                                  }),
                                ],
                              );
                            }),
                          ] else ...[
                            // PvP Leaderboard
                            if (_pvpRecord != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF3A3A3C))),
                                child: Text('Your record: ${_pvpRecord!['wins']}W - ${_pvpRecord!['losses']}L', style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const Text('PvP Wins Leaderboard', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 12),
                            if (_pvpLeaderboard.isEmpty)
                              const Text('No PvP games yet.', style: TextStyle(color: Colors.grey, fontSize: 14))
                            else
                              ..._pvpLeaderboard.asMap().entries.map((entry) {
                                final i = entry.key;
                                final row = entry.value;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(color: const Color(0xFF1A1A1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF3A3A3C))),
                                  child: Row(children: [
                                    SizedBox(width: 28, child: Text('#${i + 1}', style: TextStyle(color: i == 0 ? widget.theme.correct : Colors.grey, fontWeight: FontWeight.bold))),
                                    Expanded(child: Text(row['name'] ?? '', style: const TextStyle(color: Colors.white))),
                                    Text('${row['wins']} wins', style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold)),
                                  ]),
                                );
                              }),
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

  /// Builds the "Normal" card with Amateur/Expert sub-buttons
  Widget _buildNormalCard() {
    final color = widget.theme.correct;

    return Column(
      children: [
        // Header bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Text('Normal', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        // Card body with two sub-buttons
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            children: [
              // Amateur sub-button
              Expanded(child: _buildSubButton(
                label: 'Amateur',
                subtitle: '${_amateurBotLevel} ELO',
                played: _amateurPlayed,
                won: _amateurWon,
                moves: _amateurMoves,
                hasSession: _amateurSession != null,
                color: Colors.orangeAccent,
                onTap: () => setState(() { _playing = true; _playingMode = 'amateur'; }),
              )),
              // Divider
              Container(width: 1, height: 80, color: color.withValues(alpha: 0.3)),
              // Expert sub-button
              Expanded(child: _buildSubButton(
                label: 'Expert',
                subtitle: 'Skill $_expertBotLevel',
                played: _expertPlayed,
                won: _expertWon,
                moves: _expertMoves,
                hasSession: _expertSession != null,
                color: color,
                onTap: () => setState(() { _playing = true; _playingMode = 'expert'; }),
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubButton({
    required String label,
    required String subtitle,
    required bool played,
    required bool? won,
    required int? moves,
    required bool hasSession,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: played ? null : onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
          const SizedBox(height: 8),
          if (played)
            Text(
              won == true ? '$moves moves ✓' : '✗',
              style: TextStyle(color: won == true ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hasSession ? 'Continue' : 'Play',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lbTabBtn(String label, int tab) {
    final selected = _lbTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _lbTab = tab),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? widget.theme.present : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.theme.present.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : widget.theme.present,
          fontWeight: FontWeight.bold, fontSize: 12,
        )),
      ),
    );
  }

  Widget _buildGameCard({
    required String title,
    required int elo,
    required bool played,
    required bool? won,
    required int? moves,
    required bool hasSession,
    required Color color,
    required VoidCallback onPlay,
  }) {
    return Column(
      children: [
        // Skill level bar above card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Text('$elo ELO', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        // Card
        GestureDetector(
          onTap: played ? null : onPlay,
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_off, color: color, size: 30),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (played)
                  Text(
                    won == true ? '$moves moves ✓' : '✗',
                    style: TextStyle(color: won == true ? widget.theme.correct : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  )
                else
                  Text(
                    hasSession ? 'Continue' : 'Play',
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
