import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;
import 'package:material_symbols_icons/symbols.dart';
import '../models/app_theme.dart';

class ChessBoardWidget extends StatelessWidget {
  final chess.Chess game;
  final String? selectedSquare;
  final List<String> legalDestinations;
  final void Function(String square) onSquareTap;
  final AppTheme theme;

  const ChessBoardWidget({
    super.key,
    required this.game,
    required this.selectedSquare,
    required this.legalDestinations,
    required this.onSquareTap,
    required this.theme,
  });

  static const _files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  static const _ranks = ['8', '7', '6', '5', '4', '3', '2', '1'];

  // These need fill: 1
  static const _pawnIcon = Symbols.chess_pawn;
  static const _queenIcon = Symbols.chess_queen_sharp;
  static const _rookIcon = Symbols.chess_rook_rounded;
  // These need fill: 0 (outlined)
  static const _bishopIcon = Symbols.chess_bishop_rounded;
  static const _knightIcon = Symbols.chess_knight_rounded;
  // King uses the _2 variant
  static const _kingIcon = Symbols.chess_king_sharp;

  ({IconData icon, double fill}) _pieceIconData(chess.PieceType type) {
    if (type == chess.PieceType.KING) return (icon: _kingIcon, fill: 1);
    if (type == chess.PieceType.QUEEN) return (icon: _queenIcon, fill: 1);
    if (type == chess.PieceType.ROOK) return (icon: _rookIcon, fill: 1);
    if (type == chess.PieceType.BISHOP) return (icon: _bishopIcon, fill: 1);
    if (type == chess.PieceType.KNIGHT) return (icon: _knightIcon, fill: 1);
    return (icon: _pawnIcon, fill: 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = (constraints.maxWidth.clamp(0, 400)).toDouble();
      final squareSize = size / 8;
      final isWhiteTurn = game.turn == chess.Color.WHITE;

      return Stack(
        children: [
          SizedBox(
            width: size, height: size,
            child: Column(
              children: List.generate(8, (row) {
                return Row(
                  children: List.generate(8, (col) {
                final square = '${_files[col]}${_ranks[row]}';
                final isLight = (row + col) % 2 == 0;
                final isSelected = square == selectedSquare;
                final isLegal = legalDestinations.contains(square);
                final piece = game.get(square);

                Color bgColor = isLight
                    ? theme.correct.withValues(alpha: 0.15)
                    : theme.correct.withValues(alpha: 0.4);
                if (isSelected) bgColor = theme.present.withValues(alpha: 0.6);
                if (isLegal) bgColor = bgColor.withValues(alpha: 0.5);

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
                        if (piece != null)
                          Builder(builder: (_) {
                            final data = _pieceIconData(piece.type);
                            return Icon(
                              data.icon,
                              size: squareSize * 0.75,
                              fill: data.fill,
                              color: piece.color == chess.Color.WHITE ? Colors.white : const Color(0xFF2D2D2D),
                              shadows: piece.color == chess.Color.BLACK
                                  ? const [Shadow(color: Colors.white54, blurRadius: 2)]
                                  : null,
                            );
                          }),
                      ],
                    ),
                  ),
                );
              }),
            );
          }),
        ),
          ),
          // Turn indicator: thin glow on the edge of whose turn it is
          Positioned(
            left: 0, right: 0,
            top: isWhiteTurn ? null : 0,
            bottom: isWhiteTurn ? 0 : null,
            height: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: isWhiteTurn ? Alignment.bottomCenter : Alignment.topCenter,
                  end: isWhiteTurn ? Alignment.topCenter : Alignment.bottomCenter,
                  colors: [theme.correct, theme.correct.withValues(alpha: 0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.correct.withValues(alpha: 0.8),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}
