import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/pong_websocket.dart';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';

class PongGameScreen extends StatefulWidget {
  final String sessionId;
  final String nickname;
  final AppTheme theme;
  final PongWebSocket ws;
  final VoidCallback onExit;
  final List<Map<String, dynamic>> initialPlayers;

  const PongGameScreen({
    super.key,
    required this.sessionId,
    required this.nickname,
    required this.theme,
    required this.ws,
    required this.onExit,
    this.initialPlayers = const [],
  });

  @override
  State<PongGameScreen> createState() => _PongGameScreenState();
}

class _PongGameScreenState extends State<PongGameScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _players = [];
  bool _finished = false;
  String? _myId;
  String? _winner;

  // Server state (last received)
  double _serverBallX = 400, _serverBallY = 300;
  double _serverBallVx = -3, _serverBallVy = 2;
  double _serverP1Y = 250, _serverP2Y = 250;
  int _scoreP1 = 0, _scoreP2 = 0;

  // Client-predicted state
  double _ballX = 400, _ballY = 300;
  double _myPaddleY = 250; // local prediction for own paddle

  late Ticker _ticker;
  DateTime _lastServerUpdate = DateTime.now();
  DateTime _lastTick = DateTime.now();

  bool _upPressed = false;
  bool _downPressed = false;
  Timer? _moveTimer;

  @override
  void initState() {
    super.initState();
    _players = List<Map<String, dynamic>>.from(widget.initialPlayers);
    _myId = _players.firstWhere((p) => p['name'] == widget.nickname, orElse: () => {})['id'];
    print('[Game] Initialized with myId: $_myId');
    widget.ws.onMessage = _handleMessage;
    _ticker = createTicker(_onTick)..start();
    // HardwareKeyboard works globally without needing widget focus
    HardwareKeyboard.instance.addHandler(_handleKey);
    // Send paddle updates at fixed 20/sec rate while key held - avoids flooding WS
    _moveTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_myId == null || _finished) return;
      if (_upPressed) {
        _myPaddleY = (_myPaddleY - 20).clamp(0.0, 500.0);
        setState(() {});
        widget.ws.send({'type': 'move', 'y': _myPaddleY});
      } else if (_downPressed) {
        _myPaddleY = (_myPaddleY + 20).clamp(0.0, 500.0);
        setState(() {});
        widget.ws.send({'type': 'move', 'y': _myPaddleY});
      }
    });
  }

  bool _handleKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _upPressed = event is KeyDownEvent || event is KeyRepeatEvent;
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _downPressed = event is KeyDownEvent || event is KeyRepeatEvent;
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _moveTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    widget.ws.close();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (_finished) return;
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMicroseconds / 16667.0;
    _lastTick = now;

    setState(() {
      _ballX += _serverBallVx * dt;
      _ballY += _serverBallVy * dt;

      if (_ballY <= 10 || _ballY >= 590) _serverBallVy *= -1;

      // Smoothly lerp toward server position instead of hard snap
      _ballX += (_serverBallX - _ballX) * 0.2;
      _ballY += (_serverBallY - _ballY) * 0.2;
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    if (msg['type'] == 'lobby') {
      setState(() {
        _players = List<Map<String, dynamic>>.from(msg['players']);
        _myId = _players.firstWhere((p) => p['name'] == widget.nickname, orElse: () => {})['id'];
      });
    } else if (msg['type'] == 'state') {
      final ball = msg['ball'] as Map<String, dynamic>;
      final paddles = msg['paddles'] as Map<String, dynamic>;
      final scores = msg['scores'] as Map<String, dynamic>;
      setState(() {
        _serverBallX = (ball['x'] as num).toDouble();
        _serverBallY = (ball['y'] as num).toDouble();
        _serverBallVx = (ball['vx'] as num).toDouble();
        _serverBallVy = (ball['vy'] as num).toDouble();
        _serverP1Y = (paddles['p1'] as num).toDouble();
        _serverP2Y = (paddles['p2'] as num).toDouble();
        _scoreP1 = (scores['p1'] as num).toInt();
        _scoreP2 = (scores['p2'] as num).toInt();
        _lastServerUpdate = DateTime.now();
        // Sync ball to server on score reset (ball near center)
        if (_serverBallX > 350 && _serverBallX < 450) {
          _ballX = _serverBallX;
          _ballY = _serverBallY;
        }
      });
    } else if (msg['type'] == 'game_over') {
      setState(() { _finished = true; _winner = msg['winner']; });
      Future.delayed(const Duration(seconds: 5), widget.onExit);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_myId == null || _finished) return;
    final y = (details.localPosition.dy / size.height * 600).clamp(0.0, 500.0);
    // Instantly update local paddle (client-side prediction)
    setState(() => _myPaddleY = y);
    widget.ws.send({'type': 'move', 'y': y});
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildGameOver();

    final p1Name = _players.firstWhere((p) => p['id'] == 'p1', orElse: () => {'name': 'P1'})['name'];
    final p2Name = _players.firstWhere((p) => p['id'] == 'p2', orElse: () => {'name': 'P2'})['name'];

    // Use predicted paddle for own side, server paddle for opponent
    final displayP1Y = _myId == 'p1' ? _myPaddleY : _serverP1Y;
    final displayP2Y = _myId == 'p2' ? _myPaddleY : _serverP2Y;

    return Stack(
      children: [
        WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onExit),
                  Text('$p1Name: $_scoreP1', style: TextStyle(color: widget.theme.correct, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('$p2Name: $_scoreP2', style: TextStyle(color: widget.theme.present, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AspectRatio(
                    aspectRatio: 800 / 600,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 500),
                      child: _PongCanvas(
                        ballX: _ballX,
                        ballY: _ballY,
                        p1Y: displayP1Y,
                        p2Y: displayP2Y,
                        p1Color: widget.theme.correct,
                        p2Color: widget.theme.present,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGameOver() {
    final winnerName = _players.firstWhere((p) => p['id'] == _winner, orElse: () => {'name': 'Unknown'})['name'];
    return Scaffold(
      backgroundColor: widget.theme.background,
      body: Stack(
        children: [
          Positioned.fill(child: WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct)),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$winnerName wins!', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text('$_scoreP1 - $_scoreP2', style: const TextStyle(color: Colors.white70, fontSize: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PongCanvas extends StatefulWidget {
  final double ballX, ballY, p1Y, p2Y;
  final Color p1Color, p2Color;

  const _PongCanvas({
    required this.ballX, required this.ballY,
    required this.p1Y, required this.p2Y,
    required this.p1Color, required this.p2Color,
  });

  @override
  State<_PongCanvas> createState() => _PongCanvasState();
}

class _PongCanvasState extends State<_PongCanvas> {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121213),
          border: Border.all(color: widget.p1Color.withValues(alpha: 0.3), width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(
          painter: _PongPainter(
            ballX: widget.ballX, ballY: widget.ballY,
            p1Y: widget.p1Y, p2Y: widget.p2Y,
            p1Color: widget.p1Color, p2Color: widget.p2Color,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _PongPainter extends CustomPainter {
  final double ballX, ballY, p1Y, p2Y;
  final Color p1Color, p2Color;

  _PongPainter({required this.ballX, required this.ballY, required this.p1Y, required this.p2Y, required this.p1Color, required this.p2Color});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 800;
    final sy = size.height / 600;

    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height),
        Paint()..color = Colors.white24..strokeWidth = 2);
    canvas.drawRect(Rect.fromLTWH(10 * sx, (p1Y - 50) * sy, 10 * sx, 100 * sy), Paint()..color = p1Color);
    canvas.drawRect(Rect.fromLTWH(780 * sx, (p2Y - 50) * sy, 10 * sx, 100 * sy), Paint()..color = p2Color);
    canvas.drawCircle(Offset(ballX * sx, ballY * sy), 10 * sx, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
