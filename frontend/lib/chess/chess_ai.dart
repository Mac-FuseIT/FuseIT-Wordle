import 'dart:math';
import 'package:chess/chess.dart' as chess;

class ChessAI {
  final int level; // 100-1500
  final Random _rng = Random();

  ChessAI(this.level);

  int get _depth {
    if (level < 300) return 1;
    if (level < 600) return 2;
    return 3;
  }

  double get _blunderChance {
    if (level < 200) return 0.5;
    if (level < 400) return 0.35;
    if (level < 700) return 0.2;
    if (level < 1000) return 0.1;
    if (level < 1300) return 0.05;
    return 0.02;
  }

  String? getMove(chess.Chess game) {
    final moves = game.moves();
    if (moves.isEmpty) return null;

    if (_rng.nextDouble() < _blunderChance) {
      return moves[_rng.nextInt(moves.length)];
    }

    // Order moves: captures first for better pruning
    moves.sort((a, b) {
      final aCapture = a.contains('x') ? 0 : 1;
      final bCapture = b.contains('x') ? 0 : 1;
      return aCapture.compareTo(bCapture);
    });

    String? bestMove;
    int bestScore = -999999;

    for (final move in moves) {
      game.move(move);
      final score = -_negamax(game, _depth - 1, -999999, 999999);
      game.undo();
      if (score > bestScore) {
        bestScore = score;
        bestMove = move;
      }
    }
    return bestMove;
  }

  // Negamax: always evaluates from the perspective of the side to move
  int _negamax(chess.Chess game, int depth, int alpha, int beta) {
    if (depth == 0 || game.game_over) return _evaluate(game);

    final moves = game.moves();
    for (final move in moves) {
      game.move(move);
      final score = -_negamax(game, depth - 1, -beta, -alpha);
      game.undo();
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }

  // Evaluate from the perspective of the side to move
  int _evaluate(chess.Chess game) {
    if (game.in_checkmate) return -90000; // side to move is checkmated
    if (game.in_draw || game.in_stalemate) return 0;

    int white = 0, black = 0;
    for (int i = 0; i < 128; i++) {
      if (i & 0x88 != 0) continue;
      final piece = game.board[i];
      if (piece == null) continue;
      final val = _pieceValue(piece.type);
      if (piece.color == chess.Color.WHITE) {
        white += val;
      } else {
        black += val;
      }
    }

    final material = white - black;
    return game.turn == chess.Color.WHITE ? material : -material;
  }

  int _pieceValue(chess.PieceType type) {
    if (type == chess.PieceType.PAWN) return 100;
    if (type == chess.PieceType.KNIGHT) return 320;
    if (type == chess.PieceType.BISHOP) return 330;
    if (type == chess.PieceType.ROOK) return 500;
    if (type == chess.PieceType.QUEEN) return 900;
    return 0;
  }
}
