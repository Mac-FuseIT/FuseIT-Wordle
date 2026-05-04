import 'package:flutter/material.dart';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import '../services/pong_websocket.dart';
import 'pong_game_screen.dart';

class PongSessionLobbyScreen extends StatefulWidget {
  final String sessionId;
  final String nickname;
  final AppTheme theme;
  final bool isCreator;
  final VoidCallback onExit;

  const PongSessionLobbyScreen({
    super.key,
    required this.sessionId,
    required this.nickname,
    required this.theme,
    required this.isCreator,
    required this.onExit,
  });

  @override
  State<PongSessionLobbyScreen> createState() => _PongSessionLobbyScreenState();
}

class _PongSessionLobbyScreenState extends State<PongSessionLobbyScreen> {
  final PongWebSocket _ws = PongWebSocket();
  List<Map<String, dynamic>> _players = [];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ws.onMessage = _handleMessage;
    _ws.connect(widget.sessionId, widget.nickname);
  }

  @override
  void dispose() {
    // Only close if we're not starting the game
    if (!_started) {
      _ws.close();
    }
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    print('[Session Lobby] Received message: $msg');
    if (msg['type'] == 'lobby') {
      setState(() => _players = List<Map<String, dynamic>>.from(msg['players']));
    } else if (msg['type'] == 'start') {
      setState(() => _started = true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PongGameScreen(
            sessionId: widget.sessionId,
            nickname: widget.nickname,
            theme: widget.theme,
            ws: _ws,
            onExit: widget.onExit,
          ),
        ),
      );
    }
  }

  void _startGame() {
    print('[Session Lobby] Starting game');
    _ws.send({'type': 'start'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.theme.background,
      body: Stack(
        children: [
          Positioned.fill(child: WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct)),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: widget.onExit,
                    ),
                    const Text('Session Lobby', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF3A3A3C), height: 1),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Players', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      ..._players.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(p['name'], style: const TextStyle(color: Colors.white70, fontSize: 16)),
                      )),
                      const SizedBox(height: 40),
                      if (widget.isCreator && _players.length == 2)
                        ElevatedButton(
                          onPressed: _startGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.theme.correct,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Start Game', style: TextStyle(fontSize: 18, color: Colors.white)),
                        )
                      else if (_players.length < 2)
                        const Text('Waiting for opponent...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
