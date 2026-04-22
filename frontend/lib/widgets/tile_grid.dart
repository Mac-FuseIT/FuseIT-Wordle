import 'package:flutter/material.dart';
import '../models/game_state.dart';

class TileGrid extends StatefulWidget {
  final int wordLength;
  final int maxAttempts;
  final List<GuessResult> guesses;
  final String currentInput;
  final VoidCallback? onRevealComplete;
  final Color correctColor;
  final Color presentColor;
  final Color absentColor;
  final Color emptyColor;
  final Color textColor;

  const TileGrid({
    super.key,
    required this.wordLength,
    required this.maxAttempts,
    required this.guesses,
    required this.currentInput,
    this.onRevealComplete,
    this.correctColor = const Color(0xFF6AAA64),
    this.presentColor = const Color(0xFFC9B458),
    this.absentColor = const Color(0xFF3A3A3C),
    this.emptyColor = const Color(0xFF121213),
    this.textColor = const Color(0xFFFFFFFF),
  });

  @override
  State<TileGrid> createState() => _TileGridState();
}

class _TileGridState extends State<TileGrid> {
  int _revealedCount = 0;
  int _lastRevealedRow = -1;
  bool _revealing = false;

  @override
  void didUpdateWidget(TileGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.guesses.length > oldWidget.guesses.length) {
      _startReveal(widget.guesses.length - 1);
    }
  }

  void _startReveal(int row) {
    _lastRevealedRow = row;
    _revealedCount = 0;
    _revealing = true;
    _revealNext();
  }

  void _revealNext() {
    if (!mounted) return;
    if (_revealedCount >= widget.wordLength) {
      setState(() => _revealing = false);
      widget.onRevealComplete?.call();
      return;
    }
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _revealedCount++);
      _revealNext();
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'correct': return widget.correctColor;
      case 'present': return widget.presentColor;
      default: return widget.absentColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.maxAttempts, (row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.wordLength, (col) {
              String letter = '';
              Color bgColor = widget.emptyColor;
              Color borderColor = widget.absentColor;

              if (row < widget.guesses.length) {
                final r = widget.guesses[row].result[col];
                letter = r.letter.toUpperCase();
                if (_revealing && row == _lastRevealedRow) {
                  if (col < _revealedCount) {
                    bgColor = _statusColor(r.status);
                    borderColor = bgColor;
                  } else {
                    borderColor = const Color(0xFF565656);
                  }
                } else {
                  bgColor = _statusColor(r.status);
                  borderColor = bgColor;
                }
              } else if (row == widget.guesses.length && col < widget.currentInput.length) {
                letter = widget.currentInput[col].toUpperCase();
                borderColor = const Color(0xFF565656);
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 52,
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border.all(color: borderColor, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(color: widget.textColor, fontSize: 28, fontWeight: FontWeight.bold),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}
