import 'package:flutter/material.dart';
import 'dart:math';
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
  final bool shake;

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
    this.shake = false,
  });

  @override
  State<TileGrid> createState() => _TileGridState();
}

class _TileGridState extends State<TileGrid> with TickerProviderStateMixin {
  int _revealedCount = 0;
  int _lastRevealedRow = -1;
  bool _revealing = false;

  AnimationController? _shakeController;
  Animation<double>? _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _shakeController!, curve: Curves.elasticIn));
  }

  @override
  void didUpdateWidget(TileGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.guesses.length > oldWidget.guesses.length) {
      _startReveal(widget.guesses.length - 1);
    }
    if (widget.shake && !oldWidget.shake) {
      _shakeController!.forward(from: 0);
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
      // Wait for the last tile's flip animation to finish before completing
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() => _revealing = false);
        widget.onRevealComplete?.call();
      });
      return;
    }
    Future.delayed(const Duration(milliseconds: 350), () {
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

  Widget _buildStaticTile(String letter, Color bg, Color border) {
    return Container(
      width: 52, height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(color: widget.textColor, fontSize: 28, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.maxAttempts, (row) {
        final isCurrentInputRow = row == widget.guesses.length;
        final isRevealingRow = _revealing && row == _lastRevealedRow;

        return AnimatedBuilder(
          animation: _shakeAnimation!,
          builder: (context, child) {
            double offset = 0;
            if (isCurrentInputRow && _shakeController!.isAnimating) {
              offset = sin(_shakeAnimation!.value * 3 * pi) * 10;
            }
            return Transform.translate(offset: Offset(offset, 0), child: child);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.wordLength, (col) {
                // Completed guess — not currently revealing
                if (row < widget.guesses.length && !isRevealingRow) {
                  final r = widget.guesses[row].result[col];
                  final color = _statusColor(r.status);
                  return _buildStaticTile(r.letter.toUpperCase(), color, color);
                }

                // Currently revealing row
                if (isRevealingRow) {
                  final r = widget.guesses[row].result[col];
                  if (col < _revealedCount) {
                    // Already revealed — show with color
                    final color = _statusColor(r.status);
                    return _FlipTile(
                      key: ValueKey('flip_${row}_${col}_revealed'),
                      letter: r.letter.toUpperCase(),
                      targetColor: color,
                      emptyColor: widget.emptyColor,
                      textColor: widget.textColor,
                    );
                  } else {
                    // Not yet revealed — show letter, no color
                    return _buildStaticTile(r.letter.toUpperCase(), widget.emptyColor, const Color(0xFF565656));
                  }
                }

                // Current input row
                if (isCurrentInputRow && col < widget.currentInput.length) {
                  return _buildStaticTile(widget.currentInput[col].toUpperCase(), widget.emptyColor, const Color(0xFF565656));
                }

                // Empty tile
                return _buildStaticTile('', widget.emptyColor, widget.absentColor);
              }),
            ),
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _shakeController?.dispose();
    super.dispose();
  }
}

class _FlipTile extends StatefulWidget {
  final String letter;
  final Color targetColor;
  final Color emptyColor;
  final Color textColor;

  const _FlipTile({
    super.key,
    required this.letter,
    required this.targetColor,
    required this.emptyColor,
    required this.textColor,
  });

  @override
  State<_FlipTile> createState() => _FlipTileState();
}

class _FlipTileState extends State<_FlipTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showColor = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _controller.addListener(() {
      if (_controller.value >= 0.5 && !_showColor) {
        setState(() => _showColor = true);
      }
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showColor = true);
      }
    });
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _showColor ? widget.targetColor : widget.emptyColor;
    final border = _showColor ? widget.targetColor : const Color(0xFF565656);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _controller.value * pi;
        final scaleY = cos(angle).abs().clamp(0.01, 1.0);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scale(1.0, scaleY),
          child: Container(
            width: 52, height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: border, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(widget.letter, style: TextStyle(color: widget.textColor, fontSize: 28, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
