import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pong_websocket.dart';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import 'dart:html' as html;

class PongGameScreen extends StatefulWidget {
  final String sessionId;
  final String nickname;
  final AppTheme theme;
  final PongWebSocket ws;
  final VoidCallback onExit;

  const PongGameScreen({
    super.key,
    required this.sessionId,
    required this.nickname,
    required this.theme,
    required this.ws,
    required this.onExit,
  });

  @override
  State<PongGameScreen> createState() => _PongGameScreenState();
}

class _PongGameScreenState extends State<PongGameScreen> {
  List<Map<String, dynamic>> _players = [];
  bool _finished = false;
  String? _myId;
  double _myPaddleY = 250.0;
  Map<String, dynamic> _gameState = {
    'ball': {'x': 400.0, 'y': 300.0},
    'paddles': {'p1': 250.0, 'p2': 250.0},
    'scores': {'p1': 0, 'p2': 0},
  };
  String? _winner;

  @override
  void initState() {
    super.initState();
    widget.ws.onMessage = _handleMessage;
    _setupKeyboardListener();
  }

  void _setupKeyboardListener() {
    html.window.onKeyDown.listen((event) {
      if (_finished || _myId == null) return;
      print('[Game] Key pressed: ${event.key}');
      
      if (event.key == 'w' || event.key == 'W' || event.key == 'ArrowUp') {
        _myPaddleY = (_myPaddleY - 15).clamp(0.0, 500.0);
        print('[Game] Moving up to $_myPaddleY');
        widget.ws.send({'type': 'move', 'y': _myPaddleY});
      } else if (event.key == 's' || event.key == 'S' || event.key == 'ArrowDown') {
        _myPaddleY = (_myPaddleY + 15).clamp(0.0, 500.0);
        print('[Game] Moving down to $_myPaddleY');
        widget.ws.send({'type': 'move', 'y': _myPaddleY});
      }
    });
  }

  @override
  void dispose() {
    widget.ws.close();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    print('[Game] Received message: $msg');
    if (msg['type'] == 'lobby') {
      setState(() {
        _players = List<Map<String, dynamic>>.from(msg['players']);
        _myId = _players.firstWhere((p) => p['name'] == widget.nickname, orElse: () => {})['id'];
      });
    } else if (msg['type'] == 'state') {
      setState(() {
        _gameState = {
          'ball': msg['ball'],
          'paddles': msg['paddles'],
          'scores': msg['scores'],
        };
      });
    } else if (msg['type'] == 'game_over') {
      setState(() {
        _finished = true;
        _winner = msg['winner'];
      });
      Future.delayed(const Duration(seconds: 5), widget.onExit);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return _buildGameOver();
    }
    return _buildGame();
  }

  Widget _buildGame() {
    final ball = _gameState['ball'] as Map<String, dynamic>;
    final paddles = _gameState['paddles'] as Map<String, dynamic>;
    final scores = _gameState['scores'] as Map<String, dynamic>;
    
    final p1Name = _players.firstWhere((p) => p['id'] == 'p1', orElse: () => {'name': 'P1'})['name'];
    final p2Name = _players.firstWhere((p) => p['id'] == 'p2', orElse: () => {'name': 'P2'})['name'];

    return Scaffold(
      backgroundColor: widget.theme.background,
      body: Stack(
        children: [
          Positioned.fill(child: WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct)),
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('$p1Name: ${scores['p1']}',
                    style: TextStyle(color: widget.theme.correct, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('$p2Name: ${scores['p2']}',
                    style: TextStyle(color: widget.theme.present, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 800,
              height: 600,
              decoration: BoxDecoration(
                color: const Color(0xFF121213).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.theme.correct.withValues(alpha: 0.3), width: 2),
              ),
              child: CustomPaint(
                painter: PongPainter(
                  ballX: ball['x'],
                  ballY: ball['y'],
                  p1Y: paddles['p1'],
                  p2Y: paddles['p2'],
                  p1Color: widget.theme.correct,
                  p2Color: widget.theme.present,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOver() {
    final winnerName = _players.firstWhere((p) => p['id'] == _winner, orElse: () => {'name': 'Unknown'})['name'];
    final scores = _gameState['scores'] as Map<String, dynamic>;
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
                Text('${scores['p1']} - ${scores['p2']}', style: const TextStyle(color: Colors.white70, fontSize: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PongPainter extends CustomPainter {
  final double ballX, ballY, p1Y, p2Y;
  final Color p1Color, p2Color;

  PongPainter({
    required this.ballX,
    required this.ballY,
    required this.p1Y,
    required this.p2Y,
    required this.p1Color,
    required this.p2Color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p1Paint = Paint()..color = p1Color;
    final p2Paint = Paint()..color = p2Color;
    final ballPaint = Paint()..color = Colors.white;
    
    canvas.drawRect(Rect.fromLTWH(10, p1Y - 50, 10, 100), p1Paint);
    canvas.drawRect(Rect.fromLTWH(780, p2Y - 50, 10, 100), p2Paint);
    canvas.drawCircle(Offset(ballX, ballY), 10, ballPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
