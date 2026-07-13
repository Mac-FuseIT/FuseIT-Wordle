import 'dart:math';
import 'package:flutter/material.dart';

/// A self-contained card widget that animates with a slide-in from the left
/// followed by a 3D Y-axis flip from face-down to face-up.
///
/// Sequence (when [skipAnimation] is false and [startFaceDown] is true):
///   1. Card starts 60px to the left, opacity 0, face-down.
///   2. After [slideDelay], it slides to position + fades in (300ms, easeOut).
///   3. Pauses 100ms.
///   4. Flips via Y-axis rotation 0→π (400ms, easeInOut). At π/2 the rendered
///      child swaps from card-back to card-face.
///   5. Fires [onFlipComplete].
///
/// Special cases:
/// - [skipAnimation] = true  → render final state immediately, no controllers.
/// - cardData rank == 'hidden' → render card back, no flip.
/// - If rank changes from 'hidden' to real in [didUpdateWidget] → flip-only.
class AnimatedCard extends StatefulWidget {
  final Map<String, dynamic> cardData;

  /// When true, the card animates in face-down then flips to reveal.
  /// When false, the card appears face-up with no animation.
  final bool startFaceDown;

  /// When true, skip all animation and render the final state immediately.
  /// Used for reconnection / initial-load scenarios.
  final bool skipAnimation;

  /// Delay before the slide-in animation begins.
  final Duration slideDelay;

  /// Called once the flip animation has fully completed.
  final VoidCallback? onFlipComplete;

  final double width;
  final double height;

  const AnimatedCard({
    super.key,
    required this.cardData,
    this.startFaceDown = true,
    this.skipAnimation = false,
    this.slideDelay = Duration.zero,
    this.onFlipComplete,
    this.width = 52,
    this.height = 72,
  });

  @override
  State<AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<AnimatedCard>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _flipController;
  late Animation<double> _slideX;
  late Animation<double> _opacity;
  late Animation<double> _flipAngle;

  bool _showFace = false;
  bool _flipOnly = false; // true when transitioning from hidden → revealed

  bool get _isHidden => widget.cardData['rank'] == 'hidden';

  @override
  void initState() {
    super.initState();

    if (widget.skipAnimation) {
      // Render final state immediately — no controllers needed.
      _showFace = !_isHidden;
      _initDummyControllers();
      return;
    }

    _initControllers();

    if (widget.startFaceDown && !_isHidden) {
      _runFullSequence();
    } else if (!widget.startFaceDown) {
      // Show face immediately, no animation.
      _showFace = true;
      _slideController.value = 1.0;
    }
  }

  void _initDummyControllers() {
    // Zero-duration controllers that never animate — just satisfy late fields.
    _slideController = AnimationController(vsync: this, duration: Duration.zero);
    _flipController = AnimationController(vsync: this, duration: Duration.zero);
    _slideX = const AlwaysStoppedAnimation(0);
    _opacity = const AlwaysStoppedAnimation(1);
    _flipAngle = const AlwaysStoppedAnimation(0);
  }

  void _initControllers() {
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideX = Tween<double>(begin: -60.0, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );
    _flipAngle = Tween<double>(begin: 0, end: pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    _flipController.addListener(() {
      if (_flipAngle.value >= pi / 2 && !_showFace) {
        setState(() => _showFace = true);
      }
    });
  }

  Future<void> _runFullSequence() async {
    await Future.delayed(widget.slideDelay);
    if (!mounted) return;
    await _slideController.forward();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await _flipController.forward();
    if (!mounted) return;
    widget.onFlipComplete?.call();
  }

  Future<void> _runFlipOnly() async {
    if (!mounted) return;
    await _flipController.forward();
    if (!mounted) return;
    widget.onFlipComplete?.call();
  }

  @override
  void didUpdateWidget(AnimatedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasHidden = oldWidget.cardData['rank'] == 'hidden';
    final isNowRevealed = widget.cardData['rank'] != 'hidden';
    if (wasHidden && isNowRevealed) {
      // Always flip on reveal, even if skipAnimation was true initially
      // (e.g. the dealer's hidden card which was rendered instantly as a back).
      // If we have dummy zero-duration controllers, replace with real ones.
      if (_flipController.duration == Duration.zero) {
        _flipController.dispose();
        _flipController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 400),
        );
        _flipAngle = Tween<double>(begin: 0, end: pi).animate(
          CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
        );
        _flipController.addListener(() {
          if (_flipAngle.value >= pi / 2 && !_showFace) {
            setState(() => _showFace = true);
          }
        });
      }
      _flipOnly = true;
      _flipController.reset();
      setState(() => _showFace = false);
      _runFlipOnly();
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If a hidden→revealed flip is in progress, we must render via the
    // AnimatedBuilder even if skipAnimation was originally true.
    if (widget.skipAnimation && !_flipOnly) {
      return _showFace ? _buildCardFace() : _buildCardBack();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_slideController, _flipController]),
      builder: (context, child) {
        final Widget cardVisual = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_flipAngle.value),
          child: _showFace
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi),
                  child: _buildCardFace(),
                )
              : _buildCardBack(),
        );

        if (_flipOnly) {
          return cardVisual;
        }

        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(_slideX.value, 0),
            child: cardVisual,
          ),
        );
      },
    );
  }

  Widget _buildCardBack() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF2C5F8A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      child: Text(
        '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.width * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCardFace() {
    final rank = widget.cardData['rank']?.toString() ?? '';
    final suit = widget.cardData['suit']?.toString() ?? '';
    final suitSymbol = _getSuitSymbol(suit);
    final isRed = suit == 'hearts' || suit == 'diamonds';

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            rank,
            style: TextStyle(
              color: isRed ? Colors.red : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            suitSymbol,
            style: TextStyle(
              color: isRed ? Colors.red : Colors.black,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _getSuitSymbol(String suit) {
    switch (suit) {
      case 'hearts':
        return '♥';
      case 'diamonds':
        return '♦';
      case 'clubs':
        return '♣';
      case 'spades':
        return '♠';
      default:
        return '';
    }
  }
}
