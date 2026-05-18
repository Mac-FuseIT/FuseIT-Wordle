import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import '../models/app_theme.dart';
import 'chess_board_widget.dart';
import 'pvp_websocket.dart';

class PvpGameScreen extends StatefulWidget {
  final String sessionId;
  final int userId;
  final String nickname;
  final AppTheme theme;
  final String? colorChoice;
  final String? timeControl;
  final VoidCallback onBack;

  const PvpGameScreen({super.key, required this.sessionId, required this.userId, required this.nickname, required this.theme, this.colorChoice, this.timeControl, required this.onBack});

  @override
  State<PvpGameScreen> createState() => _PvpGameScreenState();
}

class _PvpGameScreenState extends State<PvpGameScreen> {
  final ChessPvpWebSocket _ws = ChessPvpWebSocket();
  chess.Chess _game = chess.Chess();
  List<Map<String, dynamic>> _players = [];
  bool _started = false;
  bool _gameOver = false;
  bool _ready = false;
  int _countdown = 0;
  String? _myColor;
  String? _winner;
  String? _reason;
  String? _selectedSquare;
  List<String> _legalDestinations = [];
  Map<String, int> _timers = {'white': 0, 'black': 0};
  String _timeControl = 'unlimited';
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _ws.onMessage = _handleMessage;
    _ws.connect(widget.sessionId, widget.userId, widget.nickname, colorChoice: widget.colorChoice, timeControl: widget.timeControl);
  }

  @override
  void dispose() {
    _ws.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'players':
        setState(() {
          _players = List<Map<String, dynamic>>.from(data['players'] ?? []);
          final me = _players.where((p) => p['id'] == widget.userId).toList();
          if (me.isNotEmpty) _myColor = me.first['color'];
        });
        break;
      case 'ready_status':
        setState(() {});
        break;
      case 'countdown':
        setState(() => _countdown = data['seconds'] ?? 10);
        _startCountdownTimer();
        break;
      case 'start':
        setState(() {
          _started = true;
          _countdown = 0;
          _timeControl = data['timeControl'] ?? 'unlimited';
          if (data['timers'] != null) {
            _timers = Map<String, int>.from((data['timers'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
          }
          _players = List<Map<String, dynamic>>.from(data['colors'] ?? []);
          final me = _players.where((p) => p['id'] == widget.userId).toList();
          if (me.isNotEmpty) _myColor = me.first['color'];
        });
        _startClock();
        break;
      case 'move':
        final move = data['move'] as String;
        _game.move(move);
        if (data['timers'] != null) {
          _timers = Map<String, int>.from((data['timers'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
        }
        _lastTickMs = DateTime.now().millisecondsSinceEpoch;
        setState(() { _selectedSquare = null; _legalDestinations = []; });
        break;
      case 'sync':
        // Reconnect: replay all moves to catch up
        _game = chess.Chess();
        final moves = List<String>.from(data['moves'] ?? []);
        for (final m in moves) { _game.move(m); }
        if (data['timers'] != null) {
          _timers = Map<String, int>.from((data['timers'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
        }
        _lastTickMs = DateTime.now().millisecondsSinceEpoch;
        setState(() {});
        break;
      case 'opponent_disconnected':
        setState(() {}); // could show a "reconnecting" indicator
        break;
      case 'opponent_reconnected':
        setState(() {});
        break;
      case 'connection_lost':
        // Don't end game — auto-reconnect is happening
        break;
      case 'game_over':
        _clockTimer?.cancel();
        setState(() { _gameOver = true; _winner = data['winner']; _reason = data['reason']; });
        break;
      case 'disconnected':
        // Legacy — handled by connection_lost + auto-reconnect
        break;
    }
  }

  void _startCountdownTimer() {
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 0 || _started) { t.cancel(); return; }
      setState(() => _countdown--);
    });
  }

  int _lastTickMs = 0;

  void _startClock() {
    if (_timeControl == 'unlimited') return;
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;
    _clockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_started || _gameOver) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - _lastTickMs;
      _lastTickMs = now;
      // Decrement the active player's clock
      final whiteToMove = _game.turn == chess.Color.WHITE;
      final activeKey = whiteToMove ? 'white' : 'black';
      setState(() {
        _timers[activeKey] = (_timers[activeKey] ?? 0) - elapsed;
      });
    });
  }

  bool get _isMyTurn {
    if (!_started || _gameOver || _myColor == null) return false;
    final whiteToMove = _game.turn == chess.Color.WHITE;
    return (whiteToMove && _myColor == 'white') || (!whiteToMove && _myColor == 'black');
  }

  void _onSquareTap(String square) {
    if (!_isMyTurn) return;

    final myChessColor = _myColor == 'white' ? chess.Color.WHITE : chess.Color.BLACK;

    if (_selectedSquare == null) {
      final piece = _game.get(square);
      if (piece != null && piece.color == myChessColor) {
        final moves = _game.moves({'square': square, 'verbose': true});
        setState(() {
          _selectedSquare = square;
          _legalDestinations = moves.map<String>((m) => m['to'] as String).toList();
        });
      }
    } else if (square == _selectedSquare) {
      setState(() { _selectedSquare = null; _legalDestinations = []; });
    } else if (_legalDestinations.contains(square)) {
      _makeMove(_selectedSquare!, square);
    } else {
      final piece = _game.get(square);
      if (piece != null && piece.color == myChessColor) {
        final moves = _game.moves({'square': square, 'verbose': true});
        setState(() {
          _selectedSquare = square;
          _legalDestinations = moves.map<String>((m) => m['to'] as String).toList();
        });
      } else {
        setState(() { _selectedSquare = null; _legalDestinations = []; });
      }
    }
  }

  void _makeMove(String from, String to) {
    final piece = _game.get(from);
    String? promotion;
    if (piece?.type == chess.PieceType.PAWN && (to[1] == '8' || to[1] == '1')) promotion = 'q';

    // Get SAN
    final moves = _game.moves({'verbose': true});
    String? san;
    for (final m in moves) {
      if (m['from'] == from && m['to'] == to) { san = m['san']; break; }
    }

    final success = _game.move({'from': from, 'to': to, if (promotion != null) 'promotion': promotion});
    if (!success) return;

    setState(() { _selectedSquare = null; _legalDestinations = []; });

    final isGameOver = _game.game_over;
    String? winner;
    String? reason;
    if (_game.in_checkmate) { winner = _myColor; reason = 'checkmate'; }
    else if (_game.in_stalemate || _game.in_draw) { reason = 'draw'; }

    _ws.makeMove(san ?? '$from$to', gameOver: isGameOver, winner: winner, reason: reason);
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '0:00';
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isFlipped = _myColor == 'black';

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
          const Text('PvP Chess', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
      ),
      const Divider(color: Color(0xFF3A3A3C), height: 1),
      Expanded(child: Center(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Waiting / countdown
        if (!_started && !_gameOver) ...[
          const SizedBox(height: 32),
          if (_players.length < 2)
            const Text('Waiting for opponent...', style: TextStyle(color: Colors.white70, fontSize: 16))
          else if (_countdown > 0)
            Text('Starting in $_countdown...', style: TextStyle(color: widget.theme.correct, fontSize: 20, fontWeight: FontWeight.bold))
          else ...[
            Text('Players: ${_players.map((p) => p['name']).join(' vs ')}', style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            if (!_ready)
              ElevatedButton(
                onPressed: () { _ws.ready(); setState(() => _ready = true); },
                style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
                child: const Text('Ready!', style: TextStyle(color: Colors.white, fontSize: 16)),
              )
            else
              Text('Waiting for opponent to ready up...', style: TextStyle(color: widget.theme.present)),
          ],
        ],
        // Game
        if (_started || _gameOver) ...[
          const SizedBox(height: 8),
          // Opponent timer (top)
          if (_timeControl != 'unlimited')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_formatTime(_timers[_myColor == 'white' ? 'black' : 'white'] ?? 0),
                style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 8),
          ChessBoardWidget(
            game: _game,
            selectedSquare: _selectedSquare,
            legalDestinations: _legalDestinations,
            onSquareTap: _onSquareTap,
            theme: widget.theme,
            flipped: isFlipped,
          ),
          const SizedBox(height: 8),
          // My timer (bottom)
          if (_timeControl != 'unlimited')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_formatTime(_timers[_myColor ?? 'white'] ?? 0),
                style: TextStyle(color: widget.theme.correct, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          if (_gameOver) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (_winner != null && _winner == _myColor ? widget.theme.correct : Colors.redAccent).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _winner == _myColor ? 'You won! ✓' : (_reason == 'draw' ? 'Draw' : (_reason == 'disconnected' ? 'Opponent disconnected' : 'You lost ✗')),
                style: TextStyle(color: _winner != null && _winner == _myColor ? widget.theme.correct : Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
      ])))),
    ]);
  }
}
