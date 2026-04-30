import 'package:flutter/material.dart';
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import '../services/ice_api.dart';
import 'ice_session_lobby_screen.dart';
import 'ice_game_screen.dart';

class IceLobbyScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String userName;
  const IceLobbyScreen({super.key, required this.theme, required this.onBack, required this.userName});

  @override
  State<IceLobbyScreen> createState() => _IceLobbyScreenState();
}

class _IceLobbyScreenState extends State<IceLobbyScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _currentSessionId;
  bool _inGame = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await IceApi.getSessions();
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _showCreateDialog() {
    int bestOf = 5;
    double puckSpeed = 1.0;
    int playersPerSide = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.theme.tileEmpty,
          title: Text('Create Ice.IT Session', style: TextStyle(color: widget.theme.textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Best of:', style: TextStyle(color: widget.theme.textColor)),
              Wrap(
                spacing: 8,
                children: [3, 5, 8, 12, 15, 18, 25].map((n) => ChoiceChip(
                  label: Text('$n'),
                  selected: bestOf == n,
                  selectedColor: widget.theme.correct,
                  onSelected: (sel) => setDialogState(() => bestOf = n),
                )).toList(),
              ),
              const SizedBox(height: 12),
              Text('Puck Speed:', style: TextStyle(color: widget.theme.textColor)),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('Slow'), selected: puckSpeed == 0.5, selectedColor: widget.theme.correct, onSelected: (sel) => setDialogState(() => puckSpeed = 0.5)),
                  ChoiceChip(label: const Text('Normal'), selected: puckSpeed == 1.0, selectedColor: widget.theme.correct, onSelected: (sel) => setDialogState(() => puckSpeed = 1.0)),
                  ChoiceChip(label: const Text('Fast'), selected: puckSpeed == 1.5, selectedColor: widget.theme.correct, onSelected: (sel) => setDialogState(() => puckSpeed = 1.5)),
                  ChoiceChip(label: const Text('Turbo'), selected: puckSpeed == 2.0, selectedColor: widget.theme.correct, onSelected: (sel) => setDialogState(() => puckSpeed = 2.0)),
                ],
              ),
              const SizedBox(height: 12),
              Text('Players per side:', style: TextStyle(color: widget.theme.textColor)),
              Wrap(
                spacing: 8,
                children: [1, 2, 3].map((n) => ChoiceChip(
                  label: Text('$n'),
                  selected: playersPerSide == n,
                  selectedColor: widget.theme.correct,
                  onSelected: (sel) => setDialogState(() => playersPerSide = n),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: widget.theme.textColor))),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final sessionId = await IceApi.createSession(bestOf, puckSpeed, playersPerSide);
                  if (mounted) {
                    setState(() => _currentSessionId = sessionId);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create session')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_inGame && _currentSessionId != null) {
      return IceGameScreen(
        sessionId: _currentSessionId!,
        theme: widget.theme,
        userName: widget.userName,
        onBack: () => setState(() {
          _inGame = false;
          _currentSessionId = null;
          _loadSessions();
        }),
      );
    }

    if (_currentSessionId != null) {
      return IceSessionLobbyScreen(
        sessionId: _currentSessionId!,
        theme: widget.theme,
        userName: widget.userName,
        onBack: () => setState(() {
          _currentSessionId = null;
          _loadSessions();
        }),
        onStartGame: (sessionId) => setState(() => _inGame = true),
      );
    }

    return Stack(
      children: [
        WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct),
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.arrow_back, color: widget.theme.textColor), onPressed: widget.onBack),
                  Text('Ice.IT', style: TextStyle(
                    fontFamily: 'Trebuchet MS',
                    color: widget.theme.textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: widget.theme.correct, blurRadius: 8)],
                  )),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 600),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _showCreateDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Create Session'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.theme.correct,
                                foregroundColor: widget.theme.background,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text('Open Sessions', style: TextStyle(color: widget.theme.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            _loading
                                ? CircularProgressIndicator(color: widget.theme.correct)
                                : Column(
                                    children: _sessions.map((s) {
                                      final settings = s['settings'];
                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: widget.theme.tileEmpty,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: widget.theme.correct, width: 2),
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(16),
                                          title: Text('Session ${s['session_id']}', style: TextStyle(color: widget.theme.textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              'Best of ${settings['bestOf']} • ${settings['puckSpeed']}x Speed • ${settings['playersPerSide']}v${settings['playersPerSide']}',
                                              style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.7)),
                                            ),
                                          ),
                                          trailing: ElevatedButton(
                                            onPressed: () => setState(() => _currentSessionId = s['session_id']),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: widget.theme.correct,
                                              foregroundColor: widget.theme.background,
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            ),
                                            child: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ],
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
    );
  }
}
