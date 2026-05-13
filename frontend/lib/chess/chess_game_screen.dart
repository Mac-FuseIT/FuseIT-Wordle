import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import '../models/app_theme.dart';
import '../services/api_service.dart';
import 'chess_ai.dart';
import 'chess_board_widget.dart';

class ChessGameScreen extends StatefulWidget {
  final int botLevel;
  final AppTheme theme;
  final Map<String, dynamic>? session; // existing session to restore
  final Future<void> Function(bool won, int moves, int redosUsed) onFinish;
  final VoidCallback onBack;

  const ChessGameScreen({super.key, required this.botLevel, required this.theme, this.session, required this.onFinish, required this.onBack});

  @override
  State<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen> {
  late chess.Chess _game;
  late ChessAI _ai;
  List<String> _moveHistory = [];
  int _moveCount = 0;
  int _redosLeft = 2;
  int _redosUsed = 0;
  bool _gameOver = false;
  bool _submitting = false;
  String? _selectedSquare;
  List<String> _legalDestinations = [];

  @override
  void initState() {
    super.initState();
    _ai = ChessAI(widget.botLevel);

    if (widget.session != null) {
      // Restore from saved session
      final fen = widget.session!['fen'] as String;
      _game = chess.Chess.fromFEN(fen);
      _moveHistory = List<String>.from(widget.session!['moveHistory'] ?? []);
      _moveCount = widget.session!['moveCount'] ?? 0;
      _redosUsed = widget.session!['redosUsed'] ?? 0;
      _redosLeft = 2 - _redosUsed;
    } else {
      _game = chess.Chess();
    }
    _checkGameEnd();
  }

  void _onSquareTap(String square) {
    if (_gameOver || _game.turn != chess.Color.WHITE) return;

    if (_selectedSquare == null) {
      final piece = _game.get(square);
      if (piece != null && piece.color == chess.Color.WHITE) {
        final moves = _game.moves({'square': square, 'verbose': true});
        setState(() {
          _selectedSquare = square;
          _legalDestinations = moves.map<String>((m) => m['to'] as String).toList();
        });
      }
    } else if (square == _selectedSquare) {
      setState(() { _selectedSquare = null; _legalDestinations = []; });
    } else if (_legalDestinations.contains(square)) {
      _makePlayerMove(_selectedSquare!, square);
    } else {
      final piece = _game.get(square);
      if (piece != null && piece.color == chess.Color.WHITE) {
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

  void _makePlayerMove(String from, String to) {
    final piece = _game.get(from);
    String? promotion;
    if (piece?.type == chess.PieceType.PAWN) {
      final rank = to[1];
      if (rank == '8' || rank == '1') promotion = 'q';
    }

    final san = _getMoveAsSan(from, to, promotion);
    final success = _game.move({'from': from, 'to': to, if (promotion != null) 'promotion': promotion});
    if (!success) return;

    _moveCount++;
    if (san != null) _moveHistory.add(san);
    setState(() { _selectedSquare = null; _legalDestinations = []; });

    _checkGameEnd();
    if (!_gameOver) {
      Future.delayed(const Duration(milliseconds: 300), _makeBotMove);
    } else {
      _saveSession();
    }
  }

  String? _getMoveAsSan(String from, String to, String? promotion) {
    // Get SAN before making the move by finding it in legal moves
    final moves = _game.moves({'verbose': true});
    for (final m in moves) {
      if (m['from'] == from && m['to'] == to) {
        if (promotion != null && m['promotion'] != promotion) continue;
        return m['san'] as String?;
      }
    }
    return '$from$to';
  }

  void _makeBotMove() async {
    if (_gameOver) return;
    await Future.delayed(const Duration(milliseconds: 50));
    final move = _ai.getMove(_game);
    if (move != null) {
      _moveHistory.add(move);
      _game.move(move);
      setState(() {});
      _checkGameEnd();
      _saveSession();
    }
  }

  void _checkGameEnd() {
    if (_game.game_over) {
      setState(() => _gameOver = true);
    }
  }

  void _undo() {
    if (_redosLeft <= 0 || _moveCount == 0 || _gameOver) return;
    _game.undo(); // bot
    _game.undo(); // player
    // Remove last 2 moves from history
    if (_moveHistory.length >= 2) {
      _moveHistory.removeRange(_moveHistory.length - 2, _moveHistory.length);
    }
    setState(() {
      _moveCount--;
      _redosLeft--;
      _redosUsed++;
      _selectedSquare = null;
      _legalDestinations = [];
    });
    _saveSession();
  }

  Future<void> _saveSession() async {
    if (_gameOver) return;
    await ApiService.saveChessSession(_game.fen, _moveHistory, _moveCount, _redosUsed);
  }

  bool get _playerWon {
    if (_game.in_checkmate) return _game.turn == chess.Color.BLACK;
    return false;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await widget.onFinish(_playerWon, _moveCount, _redosUsed);
  }

  void _handleBack() {
    if (!_gameOver) _saveSession();
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: _handleBack),
            const Text('Chess.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('Bot: ${widget.botLevel} ELO', style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Moves: $_moveCount', style: const TextStyle(color: Colors.white, fontSize: 14)),
                        const SizedBox(width: 24),
                        Text('Redos: $_redosLeft', style: TextStyle(
                          color: _redosLeft > 0 ? widget.theme.correct : Colors.redAccent, fontSize: 14,
                        )),
                        if (_game.in_check && !_gameOver) ...[
                          const SizedBox(width: 24),
                          const Text('CHECK!', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ChessBoardWidget(
                    game: _game,
                    selectedSquare: _selectedSquare,
                    legalDestinations: _legalDestinations,
                    onSquareTap: _onSquareTap,
                    theme: widget.theme,
                  ),
                  const SizedBox(height: 16),
                  if (!_gameOver)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _redosLeft > 0 && _moveCount > 0 ? _undo : null,
                          icon: const Icon(Icons.undo, size: 18),
                          label: Text('Undo ($_redosLeft)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _playerWon ? widget.theme.correct.withValues(alpha: 0.2) : Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _playerWon ? 'You won in $_moveCount moves! ✓' : (_game.in_stalemate || _game.in_draw ? 'Draw — counts as loss ✗' : 'You lost ✗'),
                        style: TextStyle(
                          color: _playerWon ? widget.theme.correct : Colors.redAccent,
                          fontSize: 18, fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.theme.correct,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit Result', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
