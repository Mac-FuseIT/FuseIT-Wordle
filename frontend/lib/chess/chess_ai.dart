import 'dart:math';
import 'package:chess/chess.dart' as chess;

class ChessAI {
  final int level; // 100-1500
  final Random _rng = Random();

  ChessAI(this.level);

  int get _depth {
    if (level < 400) return 1;
    if (level < 800) return 2;
    return 3;
  }

  // Chance of picking a suboptimal (not worst, not best) move
  double get _blunderChance {
    if (level < 200) return 0.6;
    if (level < 400) return 0.4;
    if (level < 600) return 0.25;
    if (level < 800) return 0.15;
    if (level < 1000) return 0.08;
    if (level < 1200) return 0.04;
    return 0.02;
  }

  String? getMove(chess.Chess game) {
    final moves = game.moves();
    if (moves.isEmpty) return null;

    // Pure random for very low ELO
    if (level < 150) return moves[_rng.nextInt(moves.length)];

    // Blunder: pick a random move (not necessarily the worst)
    if (_rng.nextDouble() < _blunderChance) {
      return moves[_rng.nextInt(moves.length)];
    }

    // Order moves: captures and checks first for better pruning
    moves.sort((a, b) {
      int aScore = 0, bScore = 0;
      if (a.contains('x')) aScore += 2;
      if (a.contains('+')) aScore += 1;
      if (b.contains('x')) bScore += 2;
      if (b.contains('+')) bScore += 1;
      return bScore.compareTo(aScore);
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

  int _evaluate(chess.Chess game) {
    if (game.in_checkmate) return -90000;
    if (game.in_draw || game.in_stalemate) return 0;

    int score = 0;

    for (int i = 0; i < 128; i++) {
      if (i & 0x88 != 0) continue;
      final piece = game.board[i];
      if (piece == null) continue;

      final val = _pieceValue(piece.type);
      final positional = _positionalBonus(piece, i);
      final total = val + positional;

      score += piece.color == chess.Color.WHITE ? total : -total;
    }

    // Mobility is too expensive to compute at every node
    return game.turn == chess.Color.WHITE ? score : -score;
  }

  int _pieceValue(chess.PieceType type) {
    if (type == chess.PieceType.PAWN) return 100;
    if (type == chess.PieceType.KNIGHT) return 320;
    if (type == chess.PieceType.BISHOP) return 330;
    if (type == chess.PieceType.ROOK) return 500;
    if (type == chess.PieceType.QUEEN) return 900;
    return 0;
  }

  // Simple positional bonuses: center control, development
  int _positionalBonus(chess.Piece piece, int sq) {
    final rank = sq >> 4; // 0-7 (0=rank8, 7=rank1)
    final file = sq & 7;  // 0-7 (0=a, 7=h)

    // Center bonus for knights and bishops
    if (piece.type == chess.PieceType.KNIGHT || piece.type == chess.PieceType.BISHOP) {
      final centerDist = (3.5 - file).abs() + (3.5 - rank).abs();
      return (7 - centerDist.toInt()) * 5;
    }

    // Pawns: advance bonus (especially center pawns)
    if (piece.type == chess.PieceType.PAWN) {
      final advance = piece.color == chess.Color.WHITE ? (7 - rank) : rank;
      int bonus = advance * 5;
      if (file >= 2 && file <= 5) bonus += 10; // center pawns
      return bonus;
    }

    // Rooks: bonus for open files (7th rank)
    if (piece.type == chess.PieceType.ROOK) {
      final seventhRank = piece.color == chess.Color.WHITE ? 1 : 6;
      if (rank == seventhRank) return 20;
    }

    // King: stay safe in early game (stay on back rank near corners)
    if (piece.type == chess.PieceType.KING) {
      final backRank = piece.color == chess.Color.WHITE ? 7 : 0;
      if (rank == backRank && (file <= 2 || file >= 5)) return 15;
    }

    return 0;
  }
}
