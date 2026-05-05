import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import '../services/ice_websocket.dart';
import '../models/game_state.dart';
import 'dart:ui' as ui;

class IceGameScreen extends StatefulWidget {
  final String sessionId;
  final AppTheme theme;
  final VoidCallback onBack;
  final String userName;
  const IceGameScreen({super.key, required this.sessionId, required this.theme, required this.onBack, required this.userName});

  @override
  State<IceGameScreen> createState() => _IceGameScreenState();
}

class _IceGameScreenState extends State<IceGameScreen> with SingleTickerProviderStateMixin {
  IceWebSocket? _ws;
  GameState? _state;
  GameState? _prevState;
  int? _myTeam;
  String? _message;
  Offset? _dragPosition;
  late Ticker _ticker;
  double _interpolation = 0;

  @override
  void initState() {
    super.initState();
    _ws = IceWebSocket(sessionId: widget.sessionId, onMessage: _handleMessage, userName: widget.userName);
    _ws!.connect();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _interpolation = (_interpolation + 0.3).clamp(0, 1);
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'joined') {
      setState(() => _myTeam = msg['team']);
    } else if (msg['type'] == 'state') {
      setState(() {
        _prevState = _state;
        _state = GameState.fromJson(msg);
        _interpolation = 0;
      });
    } else if (msg['type'] == 'goal') {
      setState(() => _message = '🏒 Team ${msg['team']} scores!');
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _message = null);
      });
    } else if (msg['type'] == 'game_over') {
      final winner = msg['winner'];
      final score = msg['score'];
      setState(() => _message = '🏆 Team $winner wins!\n\nFinal Score\n${score['team1']} - ${score['team2']}');
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) widget.onBack();
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_myTeam == null || _state == null) return;
    final x = details.localPosition.dx / size.width * 800;
    final y = details.localPosition.dy / size.height * 600;
    _ws?.sendPaddleMove(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct),
        Column(
          children: [
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back, color: widget.theme.textColor), onPressed: widget.onBack),
                  if (_state != null) ...[
                    Text('Team 1: ${_state!.score.team1}', style: TextStyle(color: widget.theme.correct, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('Round ${_state!.round}', style: TextStyle(color: widget.theme.textColor, fontSize: 14)),
                    const Spacer(),
                    Text('Team 2: ${_state!.score.team2}', style: TextStyle(color: widget.theme.absent, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
            Divider(color: widget.theme.absent, height: 1),
            Expanded(
              child: Center(
                child: _state == null
                    ? Text('Waiting for opponent...', style: TextStyle(color: widget.theme.textColor))
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: 800 / 600,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 500),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.theme.tileEmpty,
                                  border: Border.all(color: widget.theme.correct, width: 3),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: GestureDetector(
                                  onPanUpdate: (details) => _onPanUpdate(details, context.size!),
                                  child: CustomPaint(
                                    painter: IceRinkPainter(
                                      state: _state!,
                                      prevState: _prevState,
                                      interpolation: _interpolation,
                                      myTeam: _myTeam,
                                      theme: widget.theme,
                                    ),
                                    size: Size.infinite,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (_message != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: widget.theme.tileEmpty.withValues(alpha: 0.95),
                border: Border.all(color: widget.theme.correct, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: widget.theme.textColor, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ws?.dispose();
    super.dispose();
  }
}

class IceRinkPainter extends CustomPainter {
  final GameState state;
  final GameState? prevState;
  final double interpolation;
  final int? myTeam;
  final AppTheme theme;

  IceRinkPainter({required this.state, this.prevState, required this.interpolation, this.myTeam, required this.theme});

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 800;
    final scaleY = size.height / 600;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(16)),
      Paint()..color = theme.background,
    );

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      Paint()..color = theme.present..strokeWidth = 3,
    );

    final goalPaint = Paint()..color = theme.correct..style = PaintingStyle.stroke..strokeWidth = 4;
    canvas.drawRect(Rect.fromLTWH(0, size.height / 2 - 40, 10, 80), goalPaint);
    canvas.drawRect(Rect.fromLTWH(size.width - 10, size.height / 2 - 40, 10, 80), goalPaint);

    final puckX = prevState != null ? _lerp(prevState!.puck.x, state.puck.x, interpolation) : state.puck.x;
    final puckY = prevState != null ? _lerp(prevState!.puck.y, state.puck.y, interpolation) : state.puck.y;
    canvas.drawCircle(Offset(puckX * scaleX, puckY * scaleY), 8, Paint()..color = theme.textColor);

    for (int i = 0; i < state.paddles.length; i++) {
      final paddle = state.paddles[i];
      final prevPaddle = prevState != null && i < prevState!.paddles.length ? prevState!.paddles[i] : paddle;
      final x = _lerp(prevPaddle.x, paddle.x, interpolation);
      final y = _lerp(prevPaddle.y, paddle.y, interpolation);
      final isMe = paddle.team == myTeam;
      
      canvas.drawCircle(
        Offset(x * scaleX, y * scaleY),
        20,
        Paint()..color = isMe ? theme.correct : theme.absent,
      );
      if (isMe) {
        canvas.drawCircle(
          Offset(x * scaleX, y * scaleY),
          22,
          Paint()..color = theme.present..style = PaintingStyle.stroke..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant IceRinkPainter oldDelegate) => true;
}
