import 'package:flutter/material.dart';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import '../services/ice_websocket.dart';
import 'dart:convert';

class IceSessionLobbyScreen extends StatefulWidget {
  final String sessionId;
  final AppTheme theme;
  final VoidCallback onBack;
  final Function(String) onStartGame;
  final String userName;

  const IceSessionLobbyScreen({
    super.key,
    required this.sessionId,
    required this.theme,
    required this.onBack,
    required this.onStartGame,
    required this.userName,
  });

  @override
  State<IceSessionLobbyScreen> createState() => _IceSessionLobbyScreenState();
}

class _IceSessionLobbyScreenState extends State<IceSessionLobbyScreen> {
  IceWebSocket? _ws;
  List<Map<String, dynamic>> _players = [];
  int? _myTeam;
  String? _myId;
  Map<String, dynamic>? _settings;

  @override
  void initState() {
    super.initState();
    _ws = IceWebSocket(sessionId: widget.sessionId, onMessage: _handleMessage, userName: widget.userName);
    _ws!.connect();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'joined') {
      setState(() {
        _myTeam = msg['team'];
        _myId = msg['playerId'];
      });
    } else if (msg['type'] == 'lobby_state') {
      setState(() {
        _players = List<Map<String, dynamic>>.from(msg['players']);
        _settings = msg['settings'];
      });
    } else if (msg['type'] == 'game_start') {
      widget.onStartGame(widget.sessionId);
    }
  }

  void _switchTeam() {
    _ws?.sendMessage({'type': 'switch_team'});
  }

  void _startGame() {
    _ws?.sendMessage({'type': 'start_game'});
  }

  @override
  Widget build(BuildContext context) {
    final team1 = _players.where((p) => p['team'] == 1).toList();
    final team2 = _players.where((p) => p['team'] == 2).toList();
    final maxPerSide = _settings?['playersPerSide'] ?? 1;

    return Stack(
      children: [
        WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct),
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: widget.theme.textColor),
                    onPressed: widget.onBack,
                  ),
                  Text(
                    'Session ${widget.sessionId}',
                    style: TextStyle(color: widget.theme.textColor, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: widget.theme.tileEmpty,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: widget.theme.correct, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_settings != null) ...[
                        Text(
                          'Best of ${_settings!['bestOf']} • ${_settings!['puckSpeed']}x Speed',
                          style: TextStyle(color: widget.theme.textColor, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Team 1',
                                  style: TextStyle(color: widget.theme.correct, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                ...team1.map((p) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    p['name'] + (p['id'] == _myId ? ' (You)' : ''),
                                    style: TextStyle(color: widget.theme.textColor),
                                  ),
                                )),
                                if (team1.length < maxPerSide)
                                  Text('Waiting...', style: TextStyle(color: widget.theme.absent)),
                              ],
                            ),
                          ),
                          Container(width: 2, height: 150, color: widget.theme.present),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Team 2',
                                  style: TextStyle(color: widget.theme.absent, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                ...team2.map((p) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    p['name'] + (p['id'] == _myId ? ' (You)' : ''),
                                    style: TextStyle(color: widget.theme.textColor),
                                  ),
                                )),
                                if (team2.length < maxPerSide)
                                  Text('Waiting...', style: TextStyle(color: widget.theme.absent)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _switchTeam,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.theme.present,
                          foregroundColor: widget.theme.background,
                        ),
                        child: const Text('Switch Team'),
                      ),
                      const SizedBox(height: 12),
                      if (_players.length >= 2)
                        ElevatedButton(
                          onPressed: _startGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.theme.correct,
                            foregroundColor: widget.theme.background,
                            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                          ),
                          child: const Text('Start Game', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ws?.dispose();
    super.dispose();
  }
}
