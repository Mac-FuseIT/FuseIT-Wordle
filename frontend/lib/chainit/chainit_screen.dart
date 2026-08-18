import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_theme.dart';
import '../models/game_state.dart';
import '../services/api_service.dart';
import '../widgets/keyboard.dart';
import '../widgets/help_dialog.dart';

class ChainItScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;
  final VoidCallback? onLeaderboard;

  const ChainItScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
    this.onLeaderboard,
  });

  @override
  State<ChainItScreen> createState() => _ChainItScreenState();
}

class _ChainItScreenState extends State<ChainItScreen> with TickerProviderStateMixin {
  // Puzzle data
  String _startWord = '';
  String _targetWord = '';
  int _wordLength = 4;
  int _puzzleNumber = 1;

  // Game state
  List<GuessResult> _chain = []; // guesses submitted (not incl. start word)
  String _currentInput = '';
  bool _completed = false;
  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  // Animations
  bool _shake = false;
  bool _flashRed = false;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  // Scroll
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _loadPuzzle();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadPuzzle() async {
    try {
      final data = await ApiService.getChainItToday();
      final guessesRaw = (data['guesses'] as List<dynamic>? ?? []);

      // Rebuild GuessResult list from word list: each guess coloured vs target
      final target = (data['targetWord'] as String).toLowerCase();
      final List<GuessResult> chain = guessesRaw.map<GuessResult>((word) {
        final w = (word as String).toLowerCase();
        return GuessResult(
          guess: w,
          result: _colorGuess(w, target),
        );
      }).toList();

      setState(() {
        _startWord = (data['startWord'] as String).toLowerCase();
        _targetWord = target;
        _wordLength = data['length'] as int;
        _puzzleNumber = data['puzzleNumber'] as int;
        _chain = chain;
        _completed = data['completed'] as bool? ?? false;
        _loading = false;
      });

      if (_completed) {
        // Don't auto-scroll when loading a completed game — show from top
      } else {
        _scheduleScrollToBottom();
      }

      // Show help on first visit (no guesses yet and game not completed)
      if (chain.isEmpty && !(data['completed'] as bool? ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showHelp();
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load puzzle';
        _loading = false;
      });
    }
    _focusNode.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Colour a word relative to the target — identical algorithm to Guess.IT
  List<LetterResult> _colorGuess(String guess, String target) {
    final result = List<LetterResult?>.filled(target.length, null);
    final targetChars = target.split('');
    final guessChars = guess.split('');

    // Pass 1: greens
    for (int i = 0; i < guessChars.length; i++) {
      if (guessChars[i] == targetChars[i]) {
        result[i] = LetterResult(letter: guessChars[i], status: 'correct');
        targetChars[i] = '\x00';
        guessChars[i] = '\x00';
      }
    }
    // Pass 2: yellows / greys
    for (int i = 0; i < guessChars.length; i++) {
      if (guessChars[i] == '\x00') continue;
      final idx = targetChars.indexOf(guessChars[i]);
      if (idx != -1) {
        result[i] = LetterResult(letter: guess[i], status: 'present');
        targetChars[idx] = '\x00';
      } else {
        result[i] = LetterResult(letter: guess[i], status: 'absent');
      }
    }
    return result.map((r) => r!).toList();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _triggerShake() {
    setState(() {
      _shake = true;
      _flashRed = true;
    });
    _shakeController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _shake = false; _flashRed = false; });
    });
  }

  void _showError(String msg) {
    setState(() => _errorMessage = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  void _showHelp() {
    showHelpDialog(context, widget.theme, 'Chain.IT', [
      const HelpSection(body: 'Transform the starting word into the target word by changing one letter at a time!'),
      const HelpSection(heading: '🔗 Rules', body: '\u2022 Change 1 or 2 letters per step\n\u2022 Each step must be a valid English word\n\u2022 Keep going until you reach the target word\n\u2022 Fewest steps wins!'),
      const HelpSection(heading: '🎨 Letter Colors', body: '\u2022 Green: letter is in the target word, correct position\n\u2022 Yellow: letter is in the target word, wrong position\n\u2022 Grey: letter is not in the target word'),
      const HelpSection(heading: '⚡ Tips', body: '\u2022 Look at which letters need to change (grey letters)\n\u2022 Try to change one grey letter to a green/yellow one each step\n\u2022 Common word patterns help: -ING, -ATE, -OOK, etc.'),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Input handling
  // ---------------------------------------------------------------------------

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
      final ch = event.character;
      if (ch != null && RegExp(r'^[a-zA-Z]$').hasMatch(ch)) {
        _onKey(ch.toLowerCase());
      }
    }
  }

  Future<void> _submitGuess() async {
    if (_submitting || _completed) return;
    if (_currentInput.length != _wordLength) {
      _triggerShake();
      _showError('Word must be $_wordLength letters');
      return;
    }
    setState(() { _submitting = true; _errorMessage = null; });

    try {
      final res = await ApiService.submitChainItGuess(_currentInput);
      if (res['error'] != null) {
        _triggerShake();
        _showError(res['error'] as String);
        setState(() => _submitting = false);
        return;
      }

      // Parse the result from API — it returns coloured result array
      final resultList = (res['result'] as List<dynamic>)
          .map((r) => LetterResult.fromJson(r as Map<String, dynamic>))
          .toList();

      final newGuess = GuessResult(guess: _currentInput, result: resultList);
      final solved = res['solved'] as bool? ?? false;

      setState(() {
        _chain = [..._chain, newGuess];
        _currentInput = '';
        _submitting = false;
        _completed = solved;
      });

      _scheduleScrollToBottom();
    } catch (e) {
      _triggerShake();
      _showError('Connection error, try again');
      setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Tile rendering (reuses same 52×52 style as TileGrid)
  // ---------------------------------------------------------------------------

  Color _statusColor(String status) {
    switch (status) {
      case 'correct':
        return widget.theme.correct;
      case 'present':
        return widget.theme.present;
      default:
        return widget.theme.absent;
    }
  }

  Widget _tile(String letter, Color bg, Color border) {
    return Container(
      width: 52,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(color: widget.theme.textColor, fontSize: 28, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _guessRow(GuessResult g) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: g.result.map((r) {
          final c = _statusColor(r.status);
          return _tile(r.letter, c, c);
        }).toList(),
      ),
    );
  }

  Widget _startWordRow() {
    final result = _colorGuess(_startWord, _targetWord);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...result.map((r) {
            final c = _statusColor(r.status);
            return _tile(r.letter, c, c);
          }),
          const SizedBox(width: 8),
          Text('START', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.4), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _targetRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...List.generate(_wordLength, (i) {
            return _tile(_targetWord[i], widget.theme.correct, widget.theme.correct);
          }),
          const SizedBox(width: 8),
          Text('TARGET', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.4), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _inputRow() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final offset = _shake ? sin(_shakeAnimation.value * 3 * pi) * 10.0 : 0.0;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_wordLength, (i) {
            final hasLetter = i < _currentInput.length;
            final bg = _flashRed
                ? Colors.red.withValues(alpha: 0.3)
                : const Color(0xFF121213);
            final border = _flashRed
                ? Colors.redAccent
                : (hasLetter ? const Color(0xFF565656) : widget.theme.absent);
            final letter = hasLetter ? _currentInput[i] : '';
            return _tile(letter, bg, border);
          }),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: widget.theme.correct));
    }

    // Build keyboard guesses: start word result + all chain guesses
    final startResult = GuessResult(guess: _startWord, result: _colorGuess(_startWord, _targetWord));
    final keyboardGuesses = [startResult, ..._chain];

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handlePhysicalKey,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: widget.onBack,
                ),
                Text(
                  'Chain.IT',
                  style: TextStyle(
                    fontFamily: 'Trebuchet MS',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: widget.theme.present, blurRadius: 8),
                      Shadow(color: widget.theme.present, blurRadius: 16),
                    ],
                  ),
                ),
                const Spacer(),
                if (widget.onLeaderboard != null)
                  IconButton(
                    icon: const Icon(Icons.leaderboard, color: Colors.white, size: 22),
                    onPressed: widget.onLeaderboard,
                    tooltip: 'Leaderboard',
                  ),
                Text(
                  'Puzzle #$_puzzleNumber',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: Colors.white70, size: 20),
                  onPressed: _showHelp,
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF3A3A3C), height: 1),

          // ── Target word (fixed, always visible) ─────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: _targetRow(),
          ),
          Divider(color: widget.theme.absent.withValues(alpha: 0.5), height: 1, indent: 40, endIndent: 40),

          // ── Error / success overlay ──────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _errorMessage != null
                ? Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── Scrollable chain area ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _startWordRow(),
                  ..._chain.map(_guessRow),
                  if (!_completed) _inputRow(),
                  if (_submitting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: widget.theme.present),
                      ),
                    ),
                  if (_completed)
                    Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 16),
                      child: Column(
                        children: [
                          Text(
                            '🎉 Solved in ${_chain.length} step${_chain.length == 1 ? '' : 's'}!',
                            style: TextStyle(
                              color: widget.theme.correct,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.onLeaderboard != null) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: widget.onLeaderboard,
                              icon: const Icon(Icons.leaderboard, size: 16, color: Colors.white),
                              label: const Text('View Leaderboard', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
                            ),
                          ],
                        ],
                      ),
                    ),
                  // Extra padding at bottom so keyboard doesn't overlap content
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Keyboard ────────────────────────────────────────────────────────
          if (!_completed)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: GameKeyboard(
                onKey: _onKey,
                onEnter: _submitGuess,
                onBackspace: _onBackspace,
                guesses: keyboardGuesses,
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
}
