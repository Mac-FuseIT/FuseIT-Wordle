import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  String? _myId;

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
      setState(() {
        _players = List<Map<String, dynamic>>.from(msg['players']);
        _myId = _players.firstWhere((p) => p['name'] == widget.nickname, orElse: () => {})['id'];
      });
    } else if (msg['type'] == 'start') {
      setState(() => _started = true);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PongGameScreen(
            sessionId: widget.sessionId,
            nickname: widget.nickname,
            theme: widget.theme,
            ws: _ws,
            initialPlayers: _players,
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

  Future<void> _deleteSession() async {
    try {
      final response = await http.delete(
        Uri.parse('${_ws.getBaseUrl()}/api/pong/delete/${widget.sessionId}'),
      );
      if (response.statusCode == 200) {
        _ws.close();
        widget.onExit();
      }
    } catch (e) {
      print('[Session Lobby] Error deleting session: $e');
    }
  }

  Widget _playerSlot(String id) {
    final player = _players.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
    final color = id == 'p1' ? widget.theme.correct : widget.theme.present;
    final hasPlayer = player.isNotEmpty;
    return Column(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: hasPlayer ? color : const Color(0xFF3A3A3C),
          child: hasPlayer
              ? Text(player['name'].toString().substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))
              : const Icon(Icons.person_outline, color: Colors.grey, size: 32),
        ),
        const SizedBox(height: 8),
        Text(
          hasPlayer ? player['name'] : '...',
          style: TextStyle(color: hasPlayer ? Colors.white : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
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
                      const Text('Players', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _playerSlot('p1'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text('VS', style: TextStyle(color: widget.theme.correct, fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                          _playerSlot('p2'),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Text('Use ↑ ↓ arrow keys to move your paddle', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 24),
                      if (_myId == 'p1' && _players.length == 2)
                        SizedBox(                          
                          width: 200,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: _startGame,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.theme.correct,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Start Game', style: TextStyle(fontSize: 16, color: Colors.white)),
                          ),
                        )
                      else if (_players.length < 2)
                        const Text('Waiting for opponent...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      if (_players.length == 1 && _myId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SizedBox(
                            width: 200,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _deleteSession,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3A3A3C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Delete Session', style: TextStyle(fontSize: 16, color: Colors.white)),
                            ),
                          ),
                        ),
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
