import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_theme.dart';
import '../models/game_state.dart';
import '../services/api_service.dart';
import '../widgets/tile_grid.dart';
import '../widgets/keyboard.dart';
import '../widgets/help_dialog.dart';

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
  List<GuessResult> _keyboardGuesses = []; // Updated after reveal completes
  String _currentInput = '';
  bool _completed = false;
  bool _solved = false;
  String? _answer;
  String? _errorMessage;
  String? _successMessage;
  bool _loading = true;
  bool _submitting = false;
  bool _shake = false;
  bool _hideKeyboard = false;
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
      _keyboardGuesses = List.from(_guesses); // Already revealed on load
      _completed = state['completed'] ?? false;
      _solved = state['solved'] ?? false;
      if (_completed) {
        if (_solved) {
          _successMessage = 'Excellent!! Got it in ${_guesses.length}!';
        } else {
          // Extract answer from last guess's context — or just show generic message
          _successMessage = 'Better luck tomorrow!';
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load game';
    }
    setState(() { _loading = false; _hideKeyboard = _completed; });
    _focusNode.requestFocus();
  }

  Future<void> _submitGuess() async {
    if (_submitting) return;
    if (_currentInput.length != _wordLength) {
      _triggerShake();
      setState(() => _errorMessage = 'Not enough letters');
      return;
    }
    setState(() { _errorMessage = null; _successMessage = null; _submitting = true; });

    try {
      final res = await ApiService.submitGuess(widget.userId, _currentInput);
      if (res['error'] != null) {
        _triggerShake();
        setState(() { _errorMessage = res['error']; _submitting = false; });
        return;
      }
      setState(() {
        _guesses = ApiService.parseGuesses(res['guesses'] ?? []);
        // Don't update _keyboardGuesses yet — wait for reveal
        _solved = res['solved'] ?? false;
        _completed = _solved || (_guesses.length >= _maxAttempts);
        _answer = res['answer'];
        _currentInput = '';
        _errorMessage = null;
      });
    } catch (e) {
      setState(() { _errorMessage = 'Error submitting guess'; _submitting = false; });
    }
  }

  void _triggerShake() {
    setState(() => _shake = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _shake = false);
    });
  }

  void _onRevealComplete() {
    setState(() {
      _submitting = false;
      _keyboardGuesses = List.from(_guesses);
      if (_solved) {
        _successMessage = 'Excellent!! Got it in ${_guesses.length}!';
      } else if (_completed) {
        _successMessage = 'FAILED';
        _hideKeyboard = true;
      }
      if (_solved) {
        _hideKeyboard = true;
      }
    });
  }

  String _buildShareText() {
    final attempt = _solved ? '${_guesses.length}/$_maxAttempts' : 'X/$_maxAttempts';
    final lines = _guesses.map((g) {
      return g.result.map((t) {
        if (t.status == 'correct') return '🟩';
        if (t.status == 'present') return '🟨';
        return '⬛';
      }).join();
    }).join('\n');
    return 'Guess.IT $_date $attempt\n\n$lines';
  }

  void _shareResults() {
    final text = _buildShareText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Results copied to clipboard!'), duration: Duration(seconds: 2)),
    );
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

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
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
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: widget.onLogout,
                ),
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
                if (_completed)
                  IconButton(
                    icon: const Icon(Icons.leaderboard, color: Colors.white, size: 22),
                    onPressed: widget.onShowLeaderboard,
                    tooltip: 'Leaderboard',
                  ),
                IconButton(
                  icon: Icon(Icons.help_outline, color: widget.theme.correct, size: 22),
                  onPressed: () => showHelpDialog(context, widget.theme, 'How to Play Guess.IT', const [
                    HelpSection(body: 'Guess the hidden word! Each day has a different word length (4–8 letters). You get one extra attempt beyond the word length.'),
                    HelpSection(heading: '🟩 Correct', body: 'The letter is in the word AND in the correct position.'),
                    HelpSection(heading: '🟨 Wrong Spot', body: 'The letter is in the word but in the wrong position.'),
                    HelpSection(heading: '⬛ Not in Word', body: 'The letter is not in the word at all.'),
                    HelpSection(heading: 'Keyboard', body: 'The on-screen keyboard updates after each guess to show which letters you\'ve tried and their status.'),
                    HelpSection(heading: 'Leaderboard', body: 'After completing the word, view the daily and monthly leaderboards. Fewer guesses = better rank!'),
                  ]),
                  tooltip: 'Help',
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
                    clipBehavior: Clip.none,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Column(
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
                            shake: _shake,
                          ),

                      // Status / success area — fixed height to prevent layout shift
                      SizedBox(
                        height: 120,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: _successMessage != null
                              ? Column(
                                  key: const ValueKey('success'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 4),
                                    if (_solved)
                                      Text(_successMessage!, style: TextStyle(
                                        color: widget.theme.correct,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ))
                                    else if (_answer != null) ...[
                                      Text('The correct word was:', style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      )),
                                      const SizedBox(height: 2),
                                      Text(_answer!.toUpperCase(), style: TextStyle(
                                        color: widget.theme.textColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      )),
                                    ] else
                                      Text(_successMessage!, style: TextStyle(
                                        color: widget.theme.textColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      )),
                                    const SizedBox(height: 6),
                                    ElevatedButton(
                                      onPressed: widget.onShowLeaderboard,
                                      style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
                                      child: const Text('View Leaderboard', style: TextStyle(color: Colors.white)),
                                    ),
                                    const SizedBox(height: 6),
                                    ElevatedButton.icon(
                                      onPressed: _shareResults,
                                      icon: const Icon(Icons.share, size: 16, color: Colors.white),
                                      label: const Text('Share Results', style: TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3A3C)),
                                    ),
                                  ],
                                )
                              : Padding(
                                  key: const ValueKey('status'),
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    '$_wordLength letters · Attempt ${_guesses.length + (_completed ? 0 : 1)} of $_maxAttempts',
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
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

          // Keyboard — collapses when game is complete
          AnimatedSize(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOut,
            child: _hideKeyboard ? const SizedBox.shrink() : Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _legendItem(widget.theme.correct, 'Correct'),
                        const SizedBox(width: 16),
                        _legendItem(widget.theme.present, 'Wrong spot'),
                        const SizedBox(width: 16),
                        _legendItem(widget.theme.absent, 'Not in word'),
                      ],
                    ),
                  ),
                  GameKeyboard(
                    onKey: _onKey,
                    onEnter: _submitGuess,
                    onBackspace: _onBackspace,
                    guesses: _keyboardGuesses,
                    correctColor: widget.theme.correct,
                    presentColor: widget.theme.present,
                    absentColor: widget.theme.absent,
                    keyDefault: widget.theme.keyDefault,
                  ),
                ],
              ),
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
