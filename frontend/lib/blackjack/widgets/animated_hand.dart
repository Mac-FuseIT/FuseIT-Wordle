import 'package:flutter/material.dart';
import 'animated_card.dart';

/// Orchestrates a list of [AnimatedCard] widgets with staggered timing.
///
/// Cards that were already visible before the current rebuild (index <
/// [revealedCount]) are rendered with [skipAnimation] = true so they appear
/// instantly. Newly-added cards (index >= [revealedCount]) slide in and flip
/// one-by-one with [delayBetweenCards] stagger between them.
///
/// When [animateNewCards] is false every card gets [skipAnimation] = true —
/// use this for reconnection / initial-load scenarios where the full hand
/// should appear without animation.
///
/// Callbacks:
/// - [onCardFlipped] fires with the card's index each time a flip completes.
/// - [onAllFlipsComplete] fires once the last new card has finished flipping.
class AnimatedHand extends StatefulWidget {
  /// Full card list from game state. Each entry is a `{rank, suit}` map.
  final List<Map<String, dynamic>> cards;

  /// Cards at index < this value are already visible; render them instantly.
  final int revealedCount;

  /// When false, all cards are shown instantly (reconnection mode).
  final bool animateNewCards;

  /// Time between the start of consecutive new-card animations.
  final Duration delayBetweenCards;

  /// Fires with the card index each time a card's flip animation completes.
  final ValueChanged<int>? onCardFlipped;

  /// Fires once the last new card's flip animation has completed.
  final VoidCallback? onAllFlipsComplete;

  final double cardWidth;
  final double cardHeight;

  /// Horizontal and vertical gap between cards.
  final double spacing;

  const AnimatedHand({
    super.key,
    required this.cards,
    this.revealedCount = 0,
    this.animateNewCards = true,
    this.delayBetweenCards = const Duration(milliseconds: 550),
    this.onCardFlipped,
    this.onAllFlipsComplete,
    this.cardWidth = 52,
    this.cardHeight = 72,
    this.spacing = 6,
  });

  @override
  State<AnimatedHand> createState() => _AnimatedHandState();
}

class _AnimatedHandState extends State<AnimatedHand> {
  /// How many cards were in the list the last time we committed an update.
  /// Used to detect whether new cards have been appended or the hand was reset.
  int _previousLength = 0;

  /// How many new cards are being animated in the current cycle.
  int _totalNewCards = 0;

  /// How many of those new cards have completed their flip.
  int _flippedCount = 0;

  @override
  void initState() {
    super.initState();
    _previousLength = widget.cards.length;
    // On first build there are no "new" cards to animate — everything visible
    // is either already-revealed (revealedCount) or animates normally.
    final newCards = widget.cards.length - widget.revealedCount;
    _totalNewCards = (widget.animateNewCards && newCards > 0) ? newCards : 0;
  }

  @override
  void didUpdateWidget(AnimatedHand oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newLength = widget.cards.length;
    final oldLength = _previousLength;

    if (newLength > oldLength) {
      // New cards were appended — start a fresh animation cycle.
      final added = newLength - oldLength;
      setState(() {
        _totalNewCards = added;
        _flippedCount = 0;
        _previousLength = newLength;
      });
    } else if (newLength < oldLength) {
      // Hand was cleared (new round) — reset all tracking state.
      setState(() {
        _totalNewCards = 0;
        _flippedCount = 0;
        _previousLength = newLength;
      });
    }
    // Equal length: no structural change — nothing to update.
  }

  /// Called by each new card's [AnimatedCard.onFlipComplete].
  void _onCardFlipped(int cardIndex) {
    widget.onCardFlipped?.call(cardIndex);
    _flippedCount++;
    if (_flippedCount >= _totalNewCards) {
      widget.onAllFlipsComplete?.call();
    }
  }

  /// The effective number of already-revealed cards.
  ///
  /// We take the maximum of [widget.revealedCount] and [_previousLength] so
  /// that cards which have already been through an animation cycle in a
  /// previous rebuild are never re-animated.
  int get _effectiveRevealedCount =>
      _previousLength > widget.revealedCount
          ? _previousLength
          : widget.revealedCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.spacing,
      children: List.generate(widget.cards.length, (i) {
        final card = widget.cards[i];
        final isOldCard = i < _effectiveRevealedCount;
        final shouldSkip = !widget.animateNewCards || isOldCard;

        final newCardIndex = shouldSkip ? 0 : (i - _effectiveRevealedCount);
        final delay = shouldSkip
            ? Duration.zero
            : widget.delayBetweenCards * newCardIndex;

        return AnimatedCard(
          key: ValueKey('card_$i'),
          cardData: card,
          startFaceDown: !shouldSkip,
          skipAnimation: shouldSkip,
          slideDelay: delay,
          onFlipComplete: shouldSkip ? null : () => _onCardFlipped(i),
          width: widget.cardWidth,
          height: widget.cardHeight,
        );
      }),
    );
  }
}
