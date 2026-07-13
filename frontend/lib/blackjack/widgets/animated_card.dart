import 'dart:math' show pi;

import 'package:flutter/material.dart';

/// A card widget that animates into view with a slide-in + 3D flip sequence.
///
/// Animation sequence (when [startFaceDown] is true and [skipAnimation] is false):
/// 1. Card starts 60px to the left, opacity 0, showing the card back.
/// 2. After [slideDelay], slides in to position and fades to full opacity (300ms, easeOut).
/// 3. Pauses 100ms.
/// 4. Flips on the Y-axis (400ms, easeInOut). At the halfway point the face replaces the back.
/// 5. Fires [onFlipComplete].
///
/// Special cases:
/// - [skipAnimation] == true → renders face immediately, no animation.
/// - [cardData] has rank == 'hidden' → renders card back immediately, no animation.
/// - When [cardData] changes from hidden → real card (dealer hole reveal), triggers flip-only
///   animation (no slide, card is already positioned).
class AnimatedCard extends StatefulWidget {
  /// Card data map. Expected keys: 'rank' and 'suit'.
  /// Use {'rank': 'hidden', 'suit': 'hidden'} for a face-down placeholder.
  final Map<String, dynamic> cardData;

  /// Whether to animate face-down then flip. Defaults to true.
  final bool startFaceDown;

  /// When true, skips all animation and shows the card face immediately.
  /// Use this for reconnection or initial load scenarios.
  final bool skipAnimation;

  /// Delay before the slide-in animation begins. Useful for staggered deals.
  final Duration slideDelay;

  /// Called when the flip animation finishes and the card face is fully visible.
  final VoidCallback? onFlipComplete;

  /// Card width in logical pixels.
  final double width;

  /// Card height in logical pixels.
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
  // Controllers — nullable because they are only created when animation runs.
  AnimationController? _slideController;
  AnimationController? _flipController;

  Animation<Offset>? _slideAnimation;
  Animation<double>? _opacityAnimation;
  Animation<double>? _flipAnimation;

  /// True once the slide-in animation has finished (or was skipped).
  bool _slideComplete = false;

  /// True once the flip animation has finished (or was skipped).
  bool _revealed = false;

  @override
  void initState() {
    super.initState();

    if (widget.skipAnimation || _isHiddenCard()) {
      // Show immediately — no animation needed.
      _revealed = true;
      _slideComplete = true;
      return;
    }

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-60, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController!,
      curve: Curves.easeOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController!,
      curve: Curves.easeOut,
    ));

    _flipAnimation = Tween<double>(
      begin: 0.0,
      end: pi,
    ).animate(CurvedAnimation(
      parent: _flipController!,
      curve: Curves.easeInOut,
    ));

    // Start the sequential animation after slideDelay.
    Future.delayed(widget.slideDelay, () {
      if (!mounted) return;
      _slideController!.forward().then((_) {
        if (!mounted) return;
        setState(() => _slideComplete = true);
        // Pause 100ms before flip.
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          _flipController!.forward().then((_) {
            if (!mounted) return;
            setState(() => _revealed = true);
            widget.onFlipComplete?.call();
          });
        });
      });
    });
  }

  @override
  void didUpdateWidget(AnimatedCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Dealer hole card reveal: card data changed from hidden → real card.
    if (_wasHidden(oldWidget.cardData) && !_isHiddenCard()) {
      // Flip-only animation — card is already positioned, no slide needed.
      _slideComplete = true;
      _revealed = false;

      // Ensure flip controller exists (may not if widget started as hidden).
      if (_flipController == null) {
        _flipController = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 400),
        );
        _flipAnimation = Tween<double>(
          begin: 0.0,
          end: pi,
        ).animate(CurvedAnimation(
          parent: _flipController!,
          curve: Curves.easeInOut,
        ));
      } else {
        _flipController!.reset();
      }

      _flipController!.forward().then((_) {
        if (!mounted) return;
        setState(() => _revealed = true);
        widget.onFlipComplete?.call();
      });
    }
  }

  @override
  void dispose() {
    _slideController?.dispose();
    _flipController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isHiddenCard() => widget.cardData['rank'] == 'hidden';
  bool _wasHidden(Map<String, dynamic> data) => data['rank'] == 'hidden';

  // ---------------------------------------------------------------------------
  // Card renderers
  // ---------------------------------------------------------------------------

  /// Card back — matches the hidden-card style in blackjack_screen.dart.
  Widget _buildCardBack() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF2C5F8A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Card face — matches the revealed-card style in blackjack_screen._buildCard.
  Widget _buildCardFace() {
    final rank = widget.cardData['rank'] as String? ?? '';
    final suit = widget.cardData['suit'] as String? ?? '';
    final suitSymbol = _getSuitSymbol(suit);
    final isRed = suit == 'hearts' || suit == 'diamonds';
    final color = isRed ? Colors.red : Colors.black;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            rank,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            suitSymbol,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _getSuitSymbol(String suit) {
    switch (suit.toLowerCase()) {
      case 'hearts':
        return '♥';
      case 'diamonds':
        return '♦';
      case 'clubs':
        return '♣';
      case 'spades':
        return '♠';
      default:
        return suit;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Hidden card — always show the back with no animation.
    if (_isHiddenCard()) {
      return _buildCardBack();
    }

    // Skip-animation mode — show face immediately.
    if (widget.skipAnimation) {
      return _buildCardFace();
    }

    // Animation not yet initialised (before slideDelay fires the first frame).
    if (_slideController == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_slideController!, if (_flipController != null) _flipController!]),
      builder: (context, child) {
        final offset = _slideAnimation?.value ?? Offset.zero;
        final opacity = _opacityAnimation?.value ?? 1.0;

        Widget cardWidget;

        final flipCtrl = _flipController;
        if (flipCtrl != null &&
            (flipCtrl.isAnimating || flipCtrl.isCompleted)) {
          final flipValue = _flipAnimation?.value ?? 0.0;

          // During the first half of the flip show the back; during the second
          // half show the face (counter-rotated so it reads correctly).
          cardWidget = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateY(flipValue),
            child: flipValue < pi / 2
                ? _buildCardBack()
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _buildCardFace(),
                  ),
          );
        } else {
          // Slide phase — card hasn't started flipping yet.
          cardWidget = _buildCardBack();
        }

        return Transform.translate(
          offset: offset,
          child: Opacity(
            opacity: opacity,
            child: cardWidget,
          ),
        );
      },
    );
  }
}
