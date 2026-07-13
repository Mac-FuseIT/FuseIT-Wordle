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
  /// Tracks list size only — used to detect growth or reset, not as a
  /// revealed-count substitute.
  int _previousLength = 0;

  /// Cards at index >= [_animateFromIndex] will animate; those below appear
  /// instantly. Updated on init and whenever the hand grows or resets.
  int _animateFromIndex = 0;

  /// How many new cards are being animated in the current cycle.
  int _totalNewCards = 0;

  /// How many of those new cards have completed their flip.
  int _flippedCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.animateNewCards) {
      // Cards before revealedCount are already visible — animate the rest.
      _animateFromIndex = widget.revealedCount;
      // Track the FULL current length so that subsequent didUpdateWidget calls
      // from unrelated screen rebuilds (e.g. _isAnimating flag clearing) do NOT
      // enter the growth branch and reset _flippedCount mid-animation.
      // Previously this was set to revealedCount (0 on new deal), which caused
      // every rebuild during the animation to re-enter the growth branch.
      _previousLength = widget.cards.length;
      // Hidden cards (rank == 'hidden') don't run a flip animation, so they
      // must NOT count toward _totalNewCards. Only visible non-hidden new
      // cards will fire onFlipComplete.
      _totalNewCards = widget.cards
          .skip(widget.revealedCount)
          .where((c) => c['rank'] != 'hidden')
          .length;
      // If every new card is hidden (e.g. dealer's initial deal), there are
      // no flips to wait for — fire the completion callback immediately.
      if (_totalNewCards == 0 && widget.cards.length > widget.revealedCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onAllFlipsComplete?.call();
        });
      }
    } else {
      // Reconnection / page-refresh — show everything instantly.
      _animateFromIndex = widget.cards.length;
      _previousLength = widget.cards.length;
      _totalNewCards = 0;
    }
  }

  @override
  void didUpdateWidget(AnimatedHand oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newLength = widget.cards.length;
    final oldLength = _previousLength;

    if (newLength > oldLength) {
      // New cards appended (hit, dealer draw) — animate from old boundary.
      // Hidden cards don't flip, so exclude them from the expected flip count.
      final newCards = widget.cards.sublist(oldLength);
      final animatableCount =
          newCards.where((c) => c['rank'] != 'hidden').length;
      setState(() {
        _animateFromIndex = oldLength;
        _totalNewCards = animatableCount;
        _flippedCount = 0;
        _previousLength = newLength;
      });
      // If all new cards are hidden, no flips will fire — complete immediately.
      if (animatableCount == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onAllFlipsComplete?.call();
        });
      }
    } else if (newLength < oldLength) {
      // Hand cleared (new round) — reset all tracking state.
      setState(() {
        _animateFromIndex = widget.revealedCount;
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.spacing,
      children: List.generate(widget.cards.length, (i) {
        final card = widget.cards[i];
        final isHidden = card['rank'] == 'hidden';
        final isOldCard = i < _animateFromIndex;
        // Hidden cards never run a flip animation — treat them like already-
        // revealed cards so AnimatedCard renders them instantly as a back.
        final shouldSkip = !widget.animateNewCards || isOldCard || isHidden;

        // For delay, count only non-hidden new cards that come before this one
        // so the stagger timing is unaffected by hidden cards in the sequence.
        int actualNewIndex = 0;
        if (!shouldSkip) {
          for (int j = _animateFromIndex; j < i; j++) {
            if (widget.cards[j]['rank'] != 'hidden') actualNewIndex++;
          }
        }
        final delay = shouldSkip
            ? Duration.zero
            : widget.delayBetweenCards * actualNewIndex;

        return AnimatedCard(
          key: ValueKey('card_$i'),
          cardData: card,
          startFaceDown: !shouldSkip,
          skipAnimation: shouldSkip,
          slideDelay: delay,
          // Hidden cards don't flip, so they get no flip callback. Their
          // later reveal (hidden→real) is handled inside AnimatedCard itself
          // via didUpdateWidget and fires onFlipComplete at that point.
          onFlipComplete: shouldSkip ? null : () => _onCardFlipped(i),
          width: widget.cardWidth,
          height: widget.cardHeight,
        );
      }),
    );
  }
}
