import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_theme.dart';
import '../models/game_state.dart';
import '../services/api_service.dart';
import '../widgets/tile_grid.dart';
import '../widgets/keyboard.dart';

class GameScreen extends StatefulWidget {
  final int userId;
  final String name;
  final AppTheme theme;
  final VoidCallback onShowLeaderboard;
  final VoidCallback onShowProfile;
  final VoidCallback onLogout;

  const GameScreen({
    super.key,
    required this.userId,
    required this.name,
    required this.theme,
    required this.onShowLeaderboard,
    required this.onShowProfile,
    required this.onLogout,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int _wordLength = 5;
  int _maxAttempts = 6;
  String _date = '';
  List<GuessResult> _guesses = [];
  String _currentInput = '';
  bool _completed = false;
  bool _solved = false;
  String? _answer;
  String? _errorMessage;
  String? _successMessage;
  bool _loading = true;
  bool _submitting = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  Future<void> _loadGame() async {
    try {
      final today = await ApiService.getToday();
      _date = today['date'];
      _wordLength = today['wordLength'];
      _maxAttempts = today['maxAttempts'];

      final state = await ApiService.getGameState(widget.userId);
      _guesses = ApiService.parseGuesses(state['guesses'] ?? []);
      _completed = state['completed'] ?? false;
      _solved = state['solved'] ?? false;
      if (_completed) {
        if (_solved) {
          _successMessage = 'Got it in ${_guesses.length}!';
        } else {
          // Extract answer from last guess's context — or just show generic message
          _successMessage = 'Better luck tomorrow!';
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load game';
    }
    setState(() => _loading = false);
    _focusNode.requestFocus();
  }

  Future<void> _submitGuess() async {
    if (_submitting) return;
    if (_currentInput.length != _wordLength) {
      setState(() => _errorMessage = 'Not enough letters');
      return;
    }
    setState(() { _errorMessage = null; _successMessage = null; _submitting = true; });

    try {
      final res = await ApiService.submitGuess(widget.userId, _currentInput);
      if (res['error'] != null) {
        setState(() { _errorMessage = res['error']; _submitting = false; });
        return;
      }
      setState(() {
        _guesses = ApiService.parseGuesses(res['guesses'] ?? []);
        _solved = res['solved'] ?? false;
        _completed = _solved || (_guesses.length >= _maxAttempts);
        _answer = res['answer'];
        _currentInput = '';
        _errorMessage = null;
        // Don't show success message yet — wait for reveal animation
      });
    } catch (e) {
      setState(() { _errorMessage = 'Error submitting guess'; _submitting = false; });
    }
  }

  void _onRevealComplete() {
    setState(() {
      _submitting = false;
      if (_solved) {
        _successMessage = 'Excellent! Got it in ${_guesses.length}!';
      } else if (_completed) {
        _successMessage = 'The word was: ${_answer?.toUpperCase()}';
      }
    });
  }

  void _onKey(String key) {
    if (_completed || _submitting) return;
    if (_currentInput.length < _wordLength) {
      setState(() { _currentInput += key; _errorMessage = null; });
    }
  }

  void _onBackspace() {
    if (_completed || _submitting) return;
    if (_currentInput.isNotEmpty) {
      setState(() => _currentInput = _currentInput.substring(0, _currentInput.length - 1));
    }
  }

  void _handlePhysicalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_completed || _submitting) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter) {
      _submitGuess();
    } else if (key == LogicalKeyboardKey.backspace) {
      _onBackspace();
    } else {
      final label = event.character;
      if (label != null && RegExp(r'^[a-zA-Z]$').hasMatch(label)) {
        _onKey(label.toLowerCase());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: widget.theme.correct));
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handlePhysicalKey,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text('Guess.IT', style: TextStyle(
                  fontFamily: 'Trebuchet MS',
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: widget.theme.correct, blurRadius: 8),
                    Shadow(color: widget.theme.correct, blurRadius: 16),
                  ],
                )),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onShowProfile,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.name, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, color: Colors.grey, size: 14),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.leaderboard, color: Colors.white, size: 22),
                  onPressed: widget.onShowLeaderboard,
                  tooltip: 'Leaderboard',
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.grey, size: 20),
                  onPressed: widget.onLogout,
                  tooltip: 'Logout',
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF3A3A3C), height: 1),

          // Grid area
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tile grid
                          TileGrid(
                            wordLength: _wordLength,
                            maxAttempts: _maxAttempts,
                            guesses: _guesses,
                            currentInput: _currentInput,
                            onRevealComplete: _onRevealComplete,
                            correctColor: widget.theme.correct,
                            presentColor: widget.theme.present,
                            absentColor: widget.theme.absent,
                            emptyColor: widget.theme.tileEmpty,
                            textColor: widget.theme.textColor,
                          ),

                      // Status below grid
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '$_wordLength letters · Attempt ${_guesses.length + (_completed ? 0 : 1)} of $_maxAttempts',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),

                      // Success/completion message below status
                      if (_successMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_successMessage!, style: TextStyle(
                            color: _solved ? widget.theme.correct : widget.theme.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          )),
                        ),

                      // Leaderboard button when completed
                      if (_completed && _successMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ElevatedButton(
                            onPressed: widget.onShowLeaderboard,
                            style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
                            child: const Text('View Leaderboard', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                  // Overlays — float on top without pushing grid
                  if (_errorMessage != null)
                    Positioned(
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (_submitting)
                    Positioned(
                      top: 0,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.theme.correct),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),

          // Keyboard with more bottom padding
          if (!_completed)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: GameKeyboard(
                onKey: _onKey,
                onEnter: _submitGuess,
                onBackspace: _onBackspace,
                guesses: _guesses,
                correctColor: widget.theme.correct,
                presentColor: widget.theme.present,
                absentColor: widget.theme.absent,
                keyDefault: widget.theme.keyDefault,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
}
