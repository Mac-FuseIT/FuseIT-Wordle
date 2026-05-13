import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:material_symbols_icons/symbols.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import 'chess_ai.dart';
import 'chess_board_widget.dart';

class ChessGameScreen extends StatefulWidget {
  final int botLevel;
  final AppTheme theme;
  final Map<String, dynamic>? session;
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

  // History viewing: null means viewing current (latest) position
  int? _viewingIndex;

  @override
  void initState() {
    super.initState();
    _ai = ChessAI(widget.botLevel);

    if (widget.session != null) {
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

  bool get _isViewingHistory => _viewingIndex != null;

  // Build a chess position at a given move index for display
  chess.Chess _boardAtIndex(int index) {
    final temp = chess.Chess();
    for (int i = 0; i <= index; i++) {
      temp.move(_moveHistory[i]);
    }
    return temp;
  }

  chess.Chess get _displayGame => _isViewingHistory ? _boardAtIndex(_viewingIndex!) : _game;

  void _onMoveTap(int index) {
    setState(() {
      if (index == _moveHistory.length - 1) {
        _viewingIndex = null; // back to current
      } else {
        _viewingIndex = index;
      }
      _selectedSquare = null;
      _legalDestinations = [];
    });
  }

  void _onSquareTap(String square) {
    if (_gameOver || _game.turn != chess.Color.WHITE) return;

    // If viewing history with redos available, allow playing from that point
    if (_isViewingHistory) {
      if (_redosLeft <= 0) return; // can't play from history without redos
      // Select piece at the viewed position
      final viewGame = _displayGame;
      if (viewGame.turn != chess.Color.WHITE) return;

      if (_selectedSquare == null) {
        final piece = viewGame.get(square);
        if (piece != null && piece.color == chess.Color.WHITE) {
          final moves = viewGame.moves({'square': square, 'verbose': true});
          setState(() {
            _selectedSquare = square;
            _legalDestinations = moves.map<String>((m) => m['to'] as String).toList();
          });
        }
      } else if (square == _selectedSquare) {
        setState(() { _selectedSquare = null; _legalDestinations = []; });
      } else if (_legalDestinations.contains(square)) {
        _playFromHistory(_selectedSquare!, square);
      } else {
        final piece = viewGame.get(square);
        if (piece != null && piece.color == chess.Color.WHITE) {
          final moves = viewGame.moves({'square': square, 'verbose': true});
          setState(() {
            _selectedSquare = square;
            _legalDestinations = moves.map<String>((m) => m['to'] as String).toList();
          });
        } else {
          setState(() { _selectedSquare = null; _legalDestinations = []; });
        }
      }
      return;
    }

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

  void _playFromHistory(String from, String to) {
    // Rewind game to the viewed point, use an undo, then make the new move
    final rewindTo = _viewingIndex!;

    // Rebuild game to that point
    _game = chess.Chess();
    for (int i = 0; i <= rewindTo; i++) {
      _game.move(_moveHistory[i]);
    }

    // Count how many player moves were after this point
    final removedMoves = _moveHistory.sublist(rewindTo + 1);
    final removedPlayerMoves = removedMoves.where((_, ) => true).toList();
    // Player moves in removed section: every even-indexed move from rewindTo+1
    int playerMovesRemoved = 0;
    for (int i = rewindTo + 1; i < _moveHistory.length; i++) {
      if (i % 2 == 0) playerMovesRemoved++;
    }

    _moveHistory = _moveHistory.sublist(0, rewindTo + 1);
    _moveCount -= playerMovesRemoved;
    _redosLeft--;
    _redosUsed++;
    _viewingIndex = null;

    // Now make the new move
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
    _game.undo();
    _game.undo();
    if (_moveHistory.length >= 2) {
      _moveHistory.removeRange(_moveHistory.length - 2, _moveHistory.length);
    }
    setState(() {
      _moveCount--;
      _redosLeft--;
      _redosUsed++;
      _selectedSquare = null;
      _legalDestinations = [];
      _viewingIndex = null;
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
    final displayGame = _displayGame;

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
                        if (displayGame.in_check && !_gameOver) ...[
                          const SizedBox(width: 24),
                          const Text('CHECK!', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                        if (_isViewingHistory) ...[
                          const SizedBox(width: 24),
                          Text(
                            _redosLeft > 0 ? 'REVIEWING' : 'REVIEWING (no undos)',
                            style: TextStyle(color: widget.theme.present, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Builder(builder: (context) {
                      final captured = _getCapturedPieces(displayGame);
                      return Column(
                        children: [
                          // Black pieces captured by bot (shown on bot's side, top)
                          _CapturedRow(pieces: captured.whiteCaptured, theme: widget.theme, isWhite: true),
                          ChessBoardWidget(
                          game: displayGame,
                          selectedSquare: _selectedSquare,
                          legalDestinations: _isViewingHistory && _redosLeft > 0 ? _legalDestinations : (_isViewingHistory ? [] : _legalDestinations),
                          onSquareTap: _onSquareTap,
                          theme: widget.theme,
                        ),
                        // White pieces captured by player (shown on player's side, bottom)
                        _CapturedRow(pieces: captured.blackCaptured, theme: widget.theme, isWhite: false),
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
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isWhiteMove)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('$moveNum.', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ),
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
                                    child: Text(
                                      _moveHistory[i],
                                      style: TextStyle(
                                        color: isViewing ? Colors.white : (isWhiteMove ? Colors.white : Colors.white70),
                                        fontSize: 12,
                                        fontWeight: isViewing ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                      ],
                    );
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (!_gameOver)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _redosLeft > 0 && _moveCount > 0 && !_isViewingHistory ? _undo : null,
                          icon: const Icon(Icons.undo, size: 18),
                          label: Text('Undo ($_redosLeft)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3A3A3C),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        if (_isViewingHistory) ...[
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => setState(() { _viewingIndex = null; _selectedSquare = null; _legalDestinations = []; }),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.theme.correct,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Back to current'),
                          ),
                        ],
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

  ({List<chess.PieceType> whiteCaptured, List<chess.PieceType> blackCaptured}) _getCapturedPieces(chess.Chess board) {
    // Starting counts for each piece type
    final startCounts = {
      chess.PieceType.PAWN: 8,
      chess.PieceType.KNIGHT: 2,
      chess.PieceType.BISHOP: 2,
      chess.PieceType.ROOK: 2,
      chess.PieceType.QUEEN: 1,
    };

    final whiteOnBoard = <chess.PieceType, int>{};
    final blackOnBoard = <chess.PieceType, int>{};

    for (int i = 0; i < 128; i++) {
      if (i & 0x88 != 0) continue;
      final piece = board.board[i];
      if (piece == null || piece.type == chess.PieceType.KING) continue;
      final map = piece.color == chess.Color.WHITE ? whiteOnBoard : blackOnBoard;
      map[piece.type] = (map[piece.type] ?? 0) + 1;
    }

    final whiteCaptured = <chess.PieceType>[]; // white pieces taken by black (bot)
    final blackCaptured = <chess.PieceType>[]; // black pieces taken by white (player)

    for (final entry in startCounts.entries) {
      final wMissing = entry.value - (whiteOnBoard[entry.key] ?? 0);
      final bMissing = entry.value - (blackOnBoard[entry.key] ?? 0);
      for (int i = 0; i < wMissing; i++) whiteCaptured.add(entry.key);
      for (int i = 0; i < bMissing; i++) blackCaptured.add(entry.key);
    }

    return (whiteCaptured: whiteCaptured, blackCaptured: blackCaptured);
  }
}

class _CapturedRow extends StatelessWidget {
  final List<chess.PieceType> pieces;
  final AppTheme theme;
  final bool isWhite; // color of the captured pieces

  const _CapturedRow({required this.pieces, required this.theme, required this.isWhite});

  static final _icons = {
    chess.PieceType.QUEEN: Symbols.chess_queen_sharp,
    chess.PieceType.ROOK: Symbols.chess_rook_rounded,
    chess.PieceType.BISHOP: Symbols.chess_bishop_rounded,
    chess.PieceType.KNIGHT: Symbols.chess_knight_rounded,
    chess.PieceType.PAWN: Symbols.chess_pawn,
  };

  @override
  Widget build(BuildContext context) {
    if (pieces.isEmpty) return const SizedBox(height: 20);
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: pieces.map((type) => Icon(
          _icons[type] ?? Symbols.chess_pawn,
          size: 16,
          fill: 1,
          color: isWhite ? Colors.white70 : const Color(0xFF4A4A4A),
        )).toList(),
      ),
    );
  }
}
