import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import 'pong_session_lobby_screen.dart';

class PongLobbyScreen extends StatefulWidget {
  final String nickname;
  final AppTheme theme;
  final VoidCallback onBack;

  const PongLobbyScreen({
    super.key,
    required this.nickname,
    required this.theme,
    required this.onBack,
  });

  @override
  State<PongLobbyScreen> createState() => _PongLobbyScreenState();
}

class _PongLobbyScreenState extends State<PongLobbyScreen> {
  List<Map<String, dynamic>> _sessions = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _loadSessions());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final response = await http.get(Uri.parse('/api/pong/sessions'));
      final data = jsonDecode(response.body);
      if (mounted) {
        setState(() => _sessions = List<Map<String, dynamic>>.from(data['sessions']));
      }
    } catch (_) {}
  }

  Future<void> _createSession() async {
    try {
      final response = await http.post(
        Uri.parse('/api/pong/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nickname': widget.nickname}),
      );
      final data = jsonDecode(response.body);
      final sessionId = data['sessionId'];
      
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PongSessionLobbyScreen(
              sessionId: sessionId,
              nickname: widget.nickname,
              theme: widget.theme,
              isCreator: true,
              onExit: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create session: $e')),
        );
      }
    }
  }

  void _joinSession(String sessionId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PongSessionLobbyScreen(
          sessionId: sessionId,
          nickname: widget.nickname,
          theme: widget.theme,
          isCreator: false,
          onExit: () => Navigator.of(context).pop(),
        ),
      ),
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
                      onPressed: widget.onBack,
                    ),
                    const Text('Pong.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF3A3A3C), height: 1),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _createSession,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.theme.correct,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Create Game', style: TextStyle(fontSize: 16, color: Colors.white)),
                            ),
                          ),
                        ),
                        const Divider(color: Color(0xFF3A3A3C), height: 1),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _sessions.length,
                            itemBuilder: (context, i) {
                              final session = _sessions[i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF121213).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: widget.theme.correct.withValues(alpha: 0.3), width: 1),
                                ),
                                child: ListTile(
                                  title: Text('Against ${session['creator_name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  trailing: ElevatedButton(
                                    onPressed: () => _joinSession(session['session_id']),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: widget.theme.present,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    child: const Text('Join', style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
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
