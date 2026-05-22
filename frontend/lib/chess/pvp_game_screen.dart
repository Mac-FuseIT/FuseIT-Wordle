import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:material_symbols_icons/symbols.dart';
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
  List<String> _moveHistory = [];
  bool _started = false;
  bool _gameOver = false;
  bool _ready = false;
  int _countdown = 0;
  String? _myColor;
  String? _winner;
  String? _reason;
  String? _selectedSquare;
  List<String> _legalDestinations = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;
  Map<String, int> _timers = {'white': 0, 'black': 0};
  String _timeControl = 'unlimited';
  Timer? _clockTimer;
  int? _viewingIndex;

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
        final serverMoves = List<String>.from(data['moves'] ?? []);
        // Skip if we already have this move applied (we sent it)
        if (serverMoves.length <= _moveHistory.length) break;
        // Get from/to before applying
        final verbose = _game.moves({'verbose': true});
        for (final m in verbose) {
          if (m['san'] == move) { _lastMoveFrom = m['from']; _lastMoveTo = m['to']; break; }
        }
        _game.move(move);
        _moveHistory.add(move);
        if (data['timers'] != null) {
          _timers = Map<String, int>.from((data['timers'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
        }
        _lastTickMs = DateTime.now().millisecondsSinceEpoch;
        setState(() { _selectedSquare = null; _legalDestinations = []; _viewingIndex = null; });
        break;
      case 'sync':
        _game = chess.Chess();
        final moves = List<String>.from(data['moves'] ?? []);
        _moveHistory = [];
        for (final m in moves) { _game.move(m); _moveHistory.add(m); }
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
    if (!_isMyTurn || _isViewingHistory) return;

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

    setState(() { _selectedSquare = null; _legalDestinations = []; _lastMoveFrom = from; _lastMoveTo = to; });

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

  bool get _isViewingHistory => _viewingIndex != null;

  chess.Chess get _displayGame {
    if (!_isViewingHistory) return _game;
    final temp = chess.Chess();
    for (int i = 0; i <= _viewingIndex!; i++) {
      temp.move(_moveHistory[i]);
    }
    return temp;
  }

  void _onMoveTap(int index) {
    setState(() {
      _viewingIndex = index == _moveHistory.length - 1 ? null : index;
      _selectedSquare = null;
      _legalDestinations = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFlipped = _myColor == 'black';
    final displayGame = _displayGame;

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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Builder(builder: (context) {
              final captured = _getCapturedPieces(displayGame);
              return Column(children: [
                // Top: opponent's captured pieces
                _buildCapturedRow(isFlipped ? captured.blackCaptured : captured.whiteCaptured),
                ChessBoardWidget(
                  game: displayGame,
                  selectedSquare: _selectedSquare,
                  legalDestinations: _isViewingHistory ? [] : _legalDestinations,
                  onSquareTap: _onSquareTap,
                  theme: widget.theme,
                  flipped: isFlipped,
                  lastMoveFrom: _lastMoveFrom,
                  lastMoveTo: _lastMoveTo,
                ),
                // Bottom: my captured pieces
                _buildCapturedRow(isFlipped ? captured.whiteCaptured : captured.blackCaptured),
                const SizedBox(height: 8),
                // Move history bar
                if (_moveHistory.isNotEmpty)
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A3A3C)),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _moveHistory.length,
                      itemBuilder: (context, i) {
                        final isWhiteMove = i % 2 == 0;
                        final moveNum = (i ~/ 2) + 1;
                        final isViewing = _viewingIndex == i || (!_isViewingHistory && i == _moveHistory.length - 1);
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isWhiteMove)
                            Padding(padding: const EdgeInsets.only(left: 6), child: Text('$moveNum.', style: const TextStyle(color: Colors.grey, fontSize: 12))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () => _onMoveTap(i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isViewing ? widget.theme.correct.withValues(alpha: 0.4) : (isWhiteMove ? Colors.white12 : Colors.white.withValues(alpha: 0.05)),
                                  borderRadius: BorderRadius.circular(4),
                                  border: isViewing ? Border.all(color: widget.theme.correct, width: 1.5) : null,
                                ),
                                child: Text(_moveHistory[i], style: TextStyle(
                                  color: isViewing ? Colors.white : (isWhiteMove ? Colors.white : Colors.white70),
                                  fontSize: 12, fontWeight: isViewing ? FontWeight.bold : FontWeight.normal,
                                )),
                              ),
                            ),
                          ),
                        ]);
                      },
                    ),
                  ),
              ]);
            }),
          ),
          const SizedBox(height: 8),
          // My timer (bottom)
          if (_timeControl != 'unlimited')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_formatTime(_timers[_myColor ?? 'white'] ?? 0),
                style: TextStyle(color: widget.theme.correct, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          if (_isViewingHistory) ...[
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => setState(() { _viewingIndex = null; _selectedSquare = null; _legalDestinations = []; }),
              style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct, foregroundColor: Colors.white),
              child: const Text('Back to current'),
            ),
          ],
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

  ({List<chess.PieceType> whiteCaptured, List<chess.PieceType> blackCaptured}) _getCapturedPieces(chess.Chess board) {
    final startCounts = {chess.PieceType.PAWN: 8, chess.PieceType.KNIGHT: 2, chess.PieceType.BISHOP: 2, chess.PieceType.ROOK: 2, chess.PieceType.QUEEN: 1};
    final whiteOnBoard = <chess.PieceType, int>{};
    final blackOnBoard = <chess.PieceType, int>{};
    for (int i = 0; i < 128; i++) {
      if (i & 0x88 != 0) continue;
      final piece = board.board[i];
      if (piece == null || piece.type == chess.PieceType.KING) continue;
      final map = piece.color == chess.Color.WHITE ? whiteOnBoard : blackOnBoard;
      map[piece.type] = (map[piece.type] ?? 0) + 1;
    }
    final whiteCaptured = <chess.PieceType>[];
    final blackCaptured = <chess.PieceType>[];
    for (final entry in startCounts.entries) {
      for (int i = 0; i < entry.value - (whiteOnBoard[entry.key] ?? 0); i++) whiteCaptured.add(entry.key);
      for (int i = 0; i < entry.value - (blackOnBoard[entry.key] ?? 0); i++) blackCaptured.add(entry.key);
    }
    return (whiteCaptured: whiteCaptured, blackCaptured: blackCaptured);
  }

  static final _capturedIcons = {
    chess.PieceType.QUEEN: Symbols.chess_queen_sharp,
    chess.PieceType.ROOK: Symbols.chess_rook_rounded,
    chess.PieceType.BISHOP: Symbols.chess_bishop_rounded,
    chess.PieceType.KNIGHT: Symbols.chess_knight_rounded,
    chess.PieceType.PAWN: Symbols.chess_pawn,
  };

  Widget _buildCapturedRow(List<chess.PieceType> pieces) {
    if (pieces.isEmpty) return const SizedBox(height: 20);
    return SizedBox(
      height: 20,
      child: Row(children: pieces.map((type) => Icon(
        _capturedIcons[type] ?? Symbols.chess_pawn,
        size: 16, fill: 1,
        color: widget.theme.present,
        shadows: [Shadow(color: widget.theme.present, blurRadius: 3)],
      )).toList()),
    );
  }
}
