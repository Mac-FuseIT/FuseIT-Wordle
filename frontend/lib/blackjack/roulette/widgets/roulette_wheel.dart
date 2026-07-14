import 'dart:math';
import 'package:flutter/material.dart';
import '../models/roulette_state.dart';

/// Animated European roulette wheel widget.
///
/// The wheel is drawn with [_WheelPainter] and rotates via an
/// [AnimationController] + [CurvedAnimation].  When [winningNumber] changes
/// while [phase] == 'spinning', the wheel spins several full rotations and
/// decelerates so the winning pocket lands under the fixed ball indicator at
/// the top of the widget.
class RouletteWheel extends StatefulWidget {
  /// The number the ball should land on.  Null during 'idle'/'betting'.
  final int? winningNumber;

  /// Current game phase: 'idle', 'betting', 'spinning', 'result'.
  final String phase;

  /// Called once when the spin animation finishes.
  final VoidCallback? onSpinComplete;

  const RouletteWheel({
    super.key,
    required this.winningNumber,
    required this.phase,
    this.onSpinComplete,
  });

  @override
  State<RouletteWheel> createState() => _RouletteWheelState();
}

class _RouletteWheelState extends State<RouletteWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curvedAnimation;

  /// Wheel angle (radians) at the start of the current spin.
  double _startAngle = 0;

  /// Wheel angle (radians) at the end of the current spin.
  double _endAngle = 0;

  /// Latest rendered angle — updated by [AnimatedBuilder].
  double _currentAngle = 0;

  /// Tracks last winning number so we don't re-trigger the same spin.
  int? _lastWinningNumber;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(RouletteWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.winningNumber != null &&
        widget.phase == 'spinning' &&
        widget.winningNumber != _lastWinningNumber) {
      _startSpin(widget.winningNumber!);
      _lastWinningNumber = widget.winningNumber;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Animation logic
  // -------------------------------------------------------------------------

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onSpinComplete?.call();
    }
  }

  /// Compute target angle and kick off the animation.
  void _startSpin(int number) {
    final pocketIndex = wheelOrder.indexOf(number);
    if (pocketIndex == -1) return; // unknown number — bail out

    // Angular width of one pocket (radians).
    const pocketSpan = 2 * pi / 37;

    // The pocket's centre angle in the wheel's local frame (starting from top
    // because the painter starts drawing from -π/2).
    final pocketCentre = -pi / 2 + pocketSpan * pocketIndex + pocketSpan / 2;

    // The ball indicator is fixed at the top of the widget (angle 0 in screen
    // space, equivalent to -π/2 in canvas coords).
    // We want: _currentAngle + offset ≡ -pocketCentre (mod 2π)
    // so that after rotating by offset the pocket centre sits at the top.
    final currentNorm = _currentAngle % (2 * pi);
    final targetNorm = ((-pocketCentre) % (2 * pi) + 2 * pi) % (2 * pi);
    final delta = (targetNorm - currentNorm + 2 * pi) % (2 * pi); // always ≥ 0

    // At least 5 full rotations for visual effect.
    const minFullRotations = 5;
    _startAngle = _currentAngle;
    _endAngle = _currentAngle + minFullRotations * 2 * pi + delta;

    _controller.reset();
    _controller.forward();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _curvedAnimation,
        builder: (context, _) {
          // Interpolate angle.
          _currentAngle =
              _startAngle + (_endAngle - _startAngle) * _curvedAnimation.value;

          return SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating wheel.
                Transform.rotate(
                  angle: _currentAngle,
                  child: CustomPaint(
                    size: const Size(200, 200),
                    painter: _WheelPainter(
                      highlightNumber: widget.phase == 'result'
                          ? widget.winningNumber
                          : null,
                    ),
                  ),
                ),

                // Fixed ball indicator (triangle pointing down at top).
                const Positioned(
                  top: 0,
                  child: Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white,
                    size: 32,
                  ),
                ),

                // Dark centre circle with winning-number display.
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A1A1B),
                    border: Border.all(color: Colors.white24),
                    boxShadow:
                        widget.phase == 'result' && widget.winningNumber != null
                        ? [
                            BoxShadow(
                              color: _resultGlowColor(
                                widget.winningNumber!,
                              ).withValues(alpha: 0.6),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      widget.winningNumber != null
                          ? '${widget.winningNumber}'
                          : '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _resultGlowColor(int number) {
    final color = getNumberColor(number);
    if (color == 'red') return Colors.red;
    if (color == 'green') return Colors.green;
    return Colors.white;
  }
}

// ---------------------------------------------------------------------------
// Wheel painter
// ---------------------------------------------------------------------------

class _WheelPainter extends CustomPainter {
  /// If non-null, this pocket is drawn with a highlight ring for the result
  /// phase.
  final int? highlightNumber;

  const _WheelPainter({this.highlightNumber});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const sweepAngle = 2 * pi / 37;
    // Pockets start at the top of the circle.
    const startOffset = -pi / 2;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final highlightPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < 37; i++) {
      final number = wheelOrder[i];
      final arcStart = startOffset + sweepAngle * i;

      // Pocket fill colour.
      if (number == 0) {
        fillPaint.color = const Color(0xFF1B7F3A); // green
      } else if (redNumbers.contains(number)) {
        fillPaint.color = const Color(0xFFB71C1C); // red
      } else {
        fillPaint.color = const Color(0xFF1A1A1A); // black
      }

      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, arcStart, sweepAngle, true, fillPaint);
      canvas.drawArc(rect, arcStart, sweepAngle, true, borderPaint);

      // Highlight ring for winning pocket in result phase.
      if (number == highlightNumber) {
        canvas.drawArc(rect, arcStart, sweepAngle, true, highlightPaint);
      }

      // Number text — positioned along the mid-radius arc.
      final textAngle = arcStart + sweepAngle / 2;
      final textRadius = radius * 0.75;
      final textX = center.dx + textRadius * cos(textAngle);
      final textY = center.dy + textRadius * sin(textAngle);

      final tp = TextPainter(
        text: TextSpan(
          text: '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(textX, textY);
      // Rotate text so it reads outward from the centre.
      canvas.rotate(textAngle + pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Outer rim ring.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Dark inner circle (hub).
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()
        ..color = const Color(0xFF1A1A1B)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.highlightNumber != highlightNumber;
}
