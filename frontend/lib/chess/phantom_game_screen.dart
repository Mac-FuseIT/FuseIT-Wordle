import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:material_symbols_icons/symbols.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/help_dialog.dart';
import 'chess_ai.dart';
import 'chess_board_widget.dart';

/// Determines which player pieces are "phantom" (invisible) for today.
/// Same selection for all users on the same day.
List<String> _getDailyPhantomSquares(String dateStr) {
  int h = 0xdeadbeef;
  final s = 'phantom:$dateStr';
  for (int i = 0; i < s.length; i++) {
    h = (h ^ s.codeUnitAt(i)) * 2654435761;
    h = ((h << 13) | (h >> 19)) & 0xFFFFFFFF;
  }
  h = ((h ^ (h >> 16)) * 2246822507) & 0xFFFFFFFF;
  h = (h ^ (h >> 16)) & 0xFFFFFFFF;

  // Pick 2-4 piece types to be phantom
  final count = 2 + (h % 3); // 2, 3, or 4
  final pieceTypes = ['q', 'r', 'r', 'n', 'n', 'b', 'b']; // excludable types (not king/pawns)
  pieceTypes.shuffle(Random(h));
  return pieceTypes.sublist(0, count);
}

class PhantomGameScreen extends StatefulWidget {
  final int botLevel;
  final AppTheme theme;
  final Map<String, dynamic>? session;
  final String playerColor;
  final Future<void> Function(bool won, int moves, int redosUsed, List<String> moveHistory) onFinish;
  final VoidCallback onBack;

  const PhantomGameScreen({super.key, required this.botLevel, required this.theme, this.session, this.playerColor = 'white', required this.onFinish, required this.onBack});

  @override
  State<PhantomGameScreen> createState() => _PhantomGameScreenState();
}

class _PhantomGameScreenState extends State<PhantomGameScreen> {
  late chess.Chess _game;
  late ChessAI _ai;
  List<String> _moveHistory = [];
  int _moveCount = 0;
  int _redosLeft = 0;
  int _redosUsed = 0;
  bool _gameOver = false;
  String? _selectedSquare;
  List<String> _legalDestinations = [];
  int? _viewingIndex;

  // Phantom tracking
  late List<String> _phantomTypes; // piece type names that are phantom
  final Set<int> _phantomSquares = {}; // board indices (0x88) of currently invisible pieces

  // Flash animation: shows piece briefly at the FROM square when a phantom moves
  // Ghost: only show the LAST from-square for each side's phantom move
  int? _whiteGhostSquare;
  chess.PieceType? _whiteGhostType;
  int? _blackGhostSquare;
  chess.PieceType? _blackGhostType;

  late chess.Color _playerSide;

  @override
  void initState() {
    super.initState();
    _ai = ChessAI(widget.botLevel);
    _playerSide = widget.playerColor == 'black' ? chess.Color.BLACK : chess.Color.WHITE;

    // Determine today's phantom pieces
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _phantomTypes = _getDailyPhantomSquares(dateStr);

    if (widget.session != null) {
      final fen = widget.session!['fen'] as String;
      _game = chess.Chess.fromFEN(fen);
      _moveHistory = List<String>.from(widget.session!['moveHistory'] ?? []);
      _moveCount = widget.session!['moveCount'] ?? 0;
      _redosUsed = widget.session!['redosUsed'] ?? 0;
      _redosLeft = _calculateRedosFromHistory();
      _rebuildPhantomState();
    } else {
      _game = chess.Chess();
      if (_playerSide == chess.Color.BLACK) {
        Future.delayed(const Duration(milliseconds: 300), _makeBotMove);
      }
    }
    _checkGameEnd();

    // Show help on first frame only for new games
    if (widget.session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPhantomHelp());
    }
  }

  void _showPhantomHelp() {
    showHelpDialog(context, widget.theme, 'Phantom Chess', [
      const HelpSection(body: 'Some of your pieces are PHANTOM — they turn invisible after you move them!'),
      HelpSection(heading: '👻 Phantom Pieces', body: 'Today\'s phantom types: ${_phantomTypes.map(_typeName).join(", ")}. These pieces have a glowing border on the board. When you move one, it becomes invisible to your opponent!'),
      const HelpSection(heading: '👁️ Revealing', body: 'A phantom piece becomes visible again when:\n• You move it a second time\n• It captures an opponent\'s piece\n• An opponent\'s piece lands on its square'),
      const HelpSection(heading: '↩️ Earn Undos', body: 'You start with 0 undos. Capture a Queen, Rook, Bishop, or Knight to earn 1 undo (max 7).'),
      const HelpSection(heading: '🤖 Easier Bot', body: 'The bot is half the ELO of the normal daily game.'),
    ]);
  }

  String _typeName(String t) {
    switch (t) {
      case 'q': return 'Queen';
      case 'r': return 'Rook';
      case 'n': return 'Knight';
      case 'b': return 'Bishop';
      default: return t;
    }
  }

  bool _isPiecePhantom(int squareIndex) {
    return _phantomSquares.contains(squareIndex);
  }

  int? _squareToIndex(String square) {
    const files = {'a': 0, 'b': 1, 'c': 2, 'd': 3, 'e': 4, 'f': 5, 'g': 6, 'h': 7};
    final file = files[square[0]];
    final rank = int.tryParse(square[1]);
    if (file == null || rank == null) return null;
    return (8 - rank) * 16 + file;
  }

  void _triggerFlash(int squareIdx, chess.PieceType type, {bool isBot = false}) {
    setState(() {
      if (isBot) {
        _blackGhostSquare = squareIdx;
        _blackGhostType = type;
      } else {
        _whiteGhostSquare = squareIdx;
        _whiteGhostType = type;
      }
    });
  }

  void _clearGhostForCapture(int capturedSquare) {
    // If a phantom was captured, clear its ghost trail
    if (_whiteGhostSquare != null) {
      _whiteGhostSquare = null;
      _whiteGhostType = null;
    }
    if (_blackGhostSquare != null) {
      _blackGhostSquare = null;
      _blackGhostType = null;
    }
  }

  bool get _isViewingHistory => _viewingIndex != null;

  int _calculateRedosFromHistory() {
    int earned = 0;
    final tempGame = chess.Chess();
    for (int i = 0; i < _moveHistory.length; i++) {
      final isPlayerMove = (_playerSide == chess.Color.WHITE) ? (i % 2 == 0) : (i % 2 == 1);
      if (isPlayerMove && _moveHistory[i].contains('x')) {
        // Check what was captured by looking at destination before move
        final verboseMoves = tempGame.moves({'verbose': true});
        for (final m in verboseMoves) {
          if (m['san'] == _moveHistory[i]) {
            final captured = tempGame.get(m['to'] as String);
            if (captured != null && captured.type != chess.PieceType.PAWN && captured.type != chess.PieceType.KING) {
              earned++;
            }
            break;
          }
        }
      }
      tempGame.move(_moveHistory[i]);
    }
    return earned - _redosUsed;
  }

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
      _viewingIndex = index == _moveHistory.length - 1 ? null : index;
      _selectedSquare = null;
      _legalDestinations = [];
    });
  }

  void _onSquareTap(String square) {
    if (_gameOver || _game.turn != _playerSide) return;

    // If viewing history, allow playing from that point if undos available
    if (_isViewingHistory) {
      if (_redosLeft <= 0) return;
      final viewGame = _displayGame;
      if (viewGame.turn != _playerSide) return;

      if (_selectedSquare == null) {
        final piece = viewGame.get(square);
        if (piece != null && piece.color == _playerSide) {
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
        if (piece != null && piece.color == _playerSide) {
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
      if (piece != null && piece.color == _playerSide) {
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
      if (piece != null && piece.color == _playerSide) {
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
    final rewindTo = _viewingIndex!;

    // Rebuild game to that point
    _game = chess.Chess();
    for (int i = 0; i <= rewindTo; i++) {
      _game.move(_moveHistory[i]);
    }

    // Count player moves removed
    int playerMovesRemoved = 0;
    for (int i = rewindTo + 1; i < _moveHistory.length; i++) {
      if (i % 2 == 0) playerMovesRemoved++;
    }

    // Clear phantom squares for removed moves
    _phantomSquares.clear();
    // Rebuild phantom state up to rewindTo
    final tempGame = chess.Chess();
    for (int i = 0; i <= rewindTo; i++) {
      final verboseMoves = tempGame.moves({'verbose': true});
      String? movFrom;
      chess.PieceType? movType;
      for (final m in verboseMoves) {
        if (m['san'] == _moveHistory[i]) {
          movFrom = m['from'] as String?;
          final p = tempGame.get(movFrom!);
          movType = p?.type;
          break;
        }
      }
      final isCapture = _moveHistory[i].contains('x');
      if (movFrom != null && movType != null && _phantomTypes.contains(movType.name) && !isCapture) {
        // Find where this piece ended up
        tempGame.move(_moveHistory[i]);
        // We'd need to track destination — simplified: just rebuild from scratch
      } else {
        tempGame.move(_moveHistory[i]);
      }
    }

    _moveHistory = _moveHistory.sublist(0, rewindTo + 1);
    _moveCount -= playerMovesRemoved;
    _redosLeft--;
    _redosUsed++;
    _viewingIndex = null;

    // Now make the new move
    final piece = _game.get(from);
    final capturedPiece = _game.get(to);
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

    // Grant undo for capturing Q/R/B/N
    if (capturedPiece != null && capturedPiece.type != chess.PieceType.PAWN && capturedPiece.type != chess.PieceType.KING) {
      _redosLeft++;
    }

    // Apply phantom logic
    final fromIdx = _squareToIndex(from);
    final toIdx = _squareToIndex(to);
    if (fromIdx != null && toIdx != null && piece != null) {
      final isCapture = san?.contains('x') == true;
      if (isCapture) { _phantomSquares.remove(toIdx); _clearGhostForCapture(toIdx); }

      if (_phantomTypes.contains(piece.type.name)) {
        _triggerFlash(fromIdx, piece.type);
        if (!isCapture) {
          _phantomSquares.add(toIdx);
        }
      }
    }

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
    final capturedPiece = _game.get(to); // piece on destination before move
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

    // Grant undo for capturing Q/R/B/N
    if (capturedPiece != null && capturedPiece.type != chess.PieceType.PAWN && capturedPiece.type != chess.PieceType.KING) {
      _redosLeft++;
    }

    // Handle phantom logic for player's piece
    final fromIdx = _squareToIndex(from);
    final toIdx = _squareToIndex(to);
    if (fromIdx != null && toIdx != null && piece != null) {
      final isCapture = san?.contains('x') == true;

      // If capturing on a phantom square, clear it
      if (isCapture) { _phantomSquares.remove(toIdx); _clearGhostForCapture(toIdx); }

      if (_phantomTypes.contains(piece.type.name)) {
        _phantomSquares.remove(fromIdx);
        _triggerFlash(fromIdx, piece.type);

        if (!isCapture) {
          _phantomSquares.add(toIdx);
        }
      }
    }

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
      // Get from/to before making the move
      final verboseMoves = _game.moves({'verbose': true});
      String? fromSq, toSq;
      chess.PieceType? pieceType;
      bool isCapture = false;
      for (final m in verboseMoves) {
        if (m['san'] == move) {
          fromSq = m['from'] as String?;
          toSq = m['to'] as String?;
          isCapture = m['flags']?.contains('c') == true || m['flags']?.contains('e') == true;
          // Get piece type from the board before move
          final p = _game.get(fromSq!);
          pieceType = p?.type;
          break;
        }
      }

      _moveHistory.add(move);
      _game.move(move);

      // Apply phantom logic to bot's piece
      if (fromSq != null && toSq != null && pieceType != null) {
        final fromIdx = _squareToIndex(fromSq);
        final toIdx = _squareToIndex(toSq);
        if (fromIdx != null && toIdx != null) {
          // If capturing on a phantom square, clear it
          if (isCapture) { _phantomSquares.remove(toIdx); _clearGhostForCapture(toIdx); }

          if (_phantomTypes.contains(pieceType.name)) {
            _phantomSquares.remove(fromIdx);
            _triggerFlash(fromIdx, pieceType, isBot: true);
            if (!isCapture) {
              _phantomSquares.add(toIdx);
            }
          }
        }
      }

      setState(() {});
      _checkGameEnd();
      _saveSession();
    }
  }

  void _checkGameEnd() {
    if (_game.game_over) setState(() => _gameOver = true);
  }

  void _undo() {
    if (_redosLeft <= 0 || _moveCount == 0 || _gameOver) return;
    _game.undo();
    _game.undo();
    if (_moveHistory.length >= 2) {
      _moveHistory.removeRange(_moveHistory.length - 2, _moveHistory.length);
    }
    _rebuildPhantomState();
    setState(() {
      _moveCount--;
      _redosLeft--;
      _redosUsed++;
      _selectedSquare = null;
      _legalDestinations = [];
      _viewingIndex = null;
      _whiteGhostSquare = null;
      _whiteGhostType = null;
      _blackGhostSquare = null;
      _blackGhostType = null;
    });
  }

  void _rebuildPhantomState() {
    _phantomSquares.clear();
    final tempGame = chess.Chess();
    for (int i = 0; i < _moveHistory.length; i++) {
      final verboseMoves = tempGame.moves({'verbose': true});
      String? fromSq, toSq;
      chess.PieceType? pieceType;
      bool isCapture = false;
      for (final m in verboseMoves) {
        if (m['san'] == _moveHistory[i]) {
          fromSq = m['from'] as String?;
          toSq = m['to'] as String?;
          isCapture = m['flags']?.contains('c') == true || m['flags']?.contains('e') == true;
          final p = tempGame.get(fromSq!);
          pieceType = p?.type;
          break;
        }
      }
      tempGame.move(_moveHistory[i]);
      if (fromSq != null && toSq != null && pieceType != null) {
        final fromIdx = _squareToIndex(fromSq);
        final toIdx = _squareToIndex(toSq);
        if (fromIdx != null && toIdx != null) {
          if (isCapture) _phantomSquares.remove(toIdx);
          if (_phantomTypes.contains(pieceType.name)) {
            _phantomSquares.remove(fromIdx);
            if (!isCapture) _phantomSquares.add(toIdx);
          }
        }
      }
    }
  }

  ({List<chess.PieceType> whiteCaptured, List<chess.PieceType> blackCaptured}) _getCapturedPieces(chess.Chess board) {
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

  Widget _buildCapturedRow(List<chess.PieceType> pieces, bool isWhite) {
    if (pieces.isEmpty) return const SizedBox(height: 20);
    return SizedBox(
      height: 20,
      child: Row(
        children: pieces.map((type) => Icon(
          _capturedIcons[type] ?? Symbols.chess_pawn,
          size: 16, fill: 1,
          color: widget.theme.present,
          shadows: [Shadow(color: widget.theme.present, blurRadius: 3)],
        )).toList(),
      ),
    );
  }

  bool get _playerWon {
    if (_game.in_checkmate) return _game.turn != _playerSide;
    return false;
  }

  bool _submitting = false;

  Future<void> _saveSession() async {
    if (_gameOver) return;
    await ApiService.savePhantomChessSession(_game.fen, _moveHistory, _moveCount, _redosUsed);
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await widget.onFinish(_playerWon, _moveCount, _redosUsed, _moveHistory);
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
            const Text('Phantom Chess', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.help_outline, color: Colors.white70), onPressed: _showPhantomHelp),
            Text('${widget.botLevel} ELO', style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
                        Text('Undos: $_redosLeft', style: TextStyle(
                          color: _redosLeft > 0 ? widget.theme.correct : Colors.redAccent, fontSize: 14,
                        )),
                        const SizedBox(width: 24),
                        const Icon(Icons.visibility_off, color: Colors.white38, size: 16),
                        const SizedBox(width: 4),
                        Text('${_phantomSquares.length} hidden', style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
                          _buildCapturedRow(captured.whiteCaptured, true),
                          _PhantomBoardWidget(
                          game: displayGame,
                          selectedSquare: _selectedSquare,
                          legalDestinations: _isViewingHistory && _redosLeft > 0 ? _legalDestinations : (_isViewingHistory ? [] : _legalDestinations),
                          onSquareTap: _onSquareTap,
                          theme: widget.theme,
                          phantomSquares: _phantomSquares,
                          phantomTypes: _phantomTypes,
                          isViewingHistory: _isViewingHistory,
                          ghostSquares: {
                            if (_whiteGhostSquare != null) _whiteGhostSquare!: _whiteGhostType!,
                            if (_blackGhostSquare != null) _blackGhostSquare!: _blackGhostType!,
                          },
                          flipped: _playerSide == chess.Color.BLACK,
                          playerSide: _playerSide,
                        ),
                        _buildCapturedRow(captured.blackCaptured, false),
                        const SizedBox(height: 8),
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
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3A3C), foregroundColor: Colors.white),
                        ),
                        if (_isViewingHistory) ...[
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => setState(() { _viewingIndex = null; _selectedSquare = null; _legalDestinations = []; }),
                            style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct, foregroundColor: Colors.white),
                            child: const Text('Back to current'),
                          ),
                        ],
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _playerWon ? widget.theme.correct.withValues(alpha: 0.2) : Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _playerWon ? 'You won in $_moveCount moves! ✓' : 'You lost ✗',
                        style: TextStyle(color: _playerWon ? widget.theme.correct : Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
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

/// Board widget that hides phantom pieces
class _PhantomBoardWidget extends StatelessWidget {
  final chess.Chess game;
  final String? selectedSquare;
  final List<String> legalDestinations;
  final void Function(String square) onSquareTap;
  final AppTheme theme;
  final Set<int> phantomSquares;
  final List<String> phantomTypes;
  final bool isViewingHistory;
  final Map<int, chess.PieceType> ghostSquares;
  final bool flipped;
  final chess.Color playerSide;

  const _PhantomBoardWidget({
    required this.game,
    required this.selectedSquare,
    required this.legalDestinations,
    required this.onSquareTap,
    required this.theme,
    required this.phantomSquares,
    required this.phantomTypes,
    required this.isViewingHistory,
    required this.ghostSquares,
    this.flipped = false,
    required this.playerSide,
  });

  static const _files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  static const _ranks = ['8', '7', '6', '5', '4', '3', '2', '1'];
  static const _filesFlipped = ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'];
  static const _ranksFlipped = ['1', '2', '3', '4', '5', '6', '7', '8'];

  static final _pieceIcons = {
    chess.PieceType.KING: Symbols.chess_king_sharp,
    chess.PieceType.QUEEN: Symbols.chess_queen_sharp,
    chess.PieceType.ROOK: Symbols.chess_rook_rounded,
    chess.PieceType.BISHOP: Symbols.chess_bishop_rounded,
    chess.PieceType.KNIGHT: Symbols.chess_knight_rounded,
    chess.PieceType.PAWN: Symbols.chess_pawn,
  };

  int _squareToIndex(String square) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]);
    return (8 - rank) * 16 + file;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = (constraints.maxWidth.clamp(0, 400)).toDouble();
      final squareSize = size / 8;
      final isWhiteTurn = game.turn == chess.Color.WHITE;
      final isBottomTurn = flipped ? !isWhiteTurn : isWhiteTurn;

      return Stack(
        children: [
          SizedBox(
            width: size, height: size,
            child: Column(
              children: List.generate(8, (row) {
                return Row(
                  children: List.generate(8, (col) {
                    final files = flipped ? _filesFlipped : _files;
                    final ranks = flipped ? _ranksFlipped : _ranks;
                    final square = '${files[col]}${ranks[row]}';
                    final sqIdx = _squareToIndex(square);
                    final isLight = (row + col) % 2 == 0;
                    final isSelected = square == selectedSquare;
                    final isLegal = legalDestinations.contains(square);
                    final piece = game.get(square);
                    final isPhantom = phantomSquares.contains(sqIdx);

                    Color bgColor = isLight
                        ? theme.correct.withValues(alpha: 0.15)
                        : theme.correct.withValues(alpha: 0.4);
                    if (isSelected) bgColor = theme.present.withValues(alpha: 0.6);
                    if (isLegal) bgColor = bgColor.withValues(alpha: 0.5);

                    // Phantom squares get a subtle shimmer
                    if (isPhantom && !isViewingHistory) {
                      bgColor = bgColor; // keep normal — piece just won't show
                    }

                    final showPiece = piece != null && !isPhantom;

                    // Is this a phantom-type piece that's still visible on the board?
                    final isPhantomType = piece != null && !isPhantom &&
                        piece.color == playerSide &&
                        phantomTypes.contains(piece.type.name);

                    return GestureDetector(
                      onTap: () => onSquareTap(square),
                      child: Container(
                        width: squareSize, height: squareSize,
                        color: bgColor,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (isLegal)
                              Container(
                                width: squareSize * 0.35, height: squareSize * 0.35,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                              ),
                            if (showPiece)
                              Container(
                                decoration: isPhantomType ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.correct, width: 2),
                                  boxShadow: [BoxShadow(color: theme.correct.withValues(alpha: 0.5), blurRadius: 4)],
                                ) : null,
                                padding: isPhantomType ? const EdgeInsets.all(2) : null,
                              child: piece.color == chess.Color.BLACK
                                ? Icon(
                                    _pieceIcons[piece.type] ?? Symbols.chess_pawn,
                                    size: squareSize * (isPhantomType ? 0.6 : 0.75),
                                    fill: 1,
                                    color: const Color(0xFF2D2D2D),
                                    shadows: [Shadow(color: theme.present, blurRadius: 3), Shadow(color: theme.present, blurRadius: 1)],
                                  )
                                : Icon(
                                    _pieceIcons[piece.type] ?? Symbols.chess_pawn,
                                    size: squareSize * (isPhantomType ? 0.6 : 0.75),
                                    fill: 1,
                                    color: Colors.white,
                                  ),
                              ),
                            // Ghost: show faded piece where a phantom moved from
                            if (ghostSquares.containsKey(sqIdx))
                              Icon(
                                _pieceIcons[ghostSquares[sqIdx]] ?? Symbols.chess_pawn,
                                size: squareSize * 0.6,
                                fill: 1,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
          Positioned(
            left: 0, right: 0,
            top: isBottomTurn ? null : 0,
            bottom: isBottomTurn ? 0 : null,
            height: 3,
            child: Builder(builder: (_) {
              final glowColor = game.in_check ? Colors.redAccent : theme.correct;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: isBottomTurn ? Alignment.bottomCenter : Alignment.topCenter,
                    end: isBottomTurn ? Alignment.topCenter : Alignment.bottomCenter,
                    colors: [glowColor, glowColor.withValues(alpha: 0)],
                  ),
                  boxShadow: [
                    BoxShadow(color: glowColor.withValues(alpha: 0.8), blurRadius: 6, spreadRadius: 1),
                  ],
                ),
              );
            }),
          ),
        ],
      );
    });
  }
}
