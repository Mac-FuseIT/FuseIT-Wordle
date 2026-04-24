import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../models/app_theme.dart';
import '../services/crossword_api.dart';
import '../widgets/crossword_grid.dart';
import '../widgets/clue_list.dart';

class CrosswordScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final VoidCallback onLeaderboard;

  const CrosswordScreen({super.key, required this.theme, required this.onBack, required this.onLeaderboard});

  @override
  State<CrosswordScreen> createState() => _CrosswordScreenState();
}

class _CrosswordScreenState extends State<CrosswordScreen> {
  List<List<String?>> _grid = [];
  List<List<String?>> _answerGrid = []; // Stored answer for hints/give-up
  List<Map<String, dynamic>> _acrossClues = [];
  List<Map<String, dynamic>> _downClues = [];
  int? _selRow, _selCol;
  bool _isAcross = true;
  bool _loading = true;
  bool _completed = false;
  bool _failed = false;
  int _elapsed = 0;
  Timer? _timer;
  String? _message;
  int _hintsLeft = 3;
  int _checksLeft = 3;
  Set<String> _correctCells = {};
  bool _shakeWord = false;
  bool _hideClues = false;
  int? _completedTime;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await CrosswordApi.getToday();
      final answerData = await CrosswordApi.getAnswer();
      _grid = (data['grid'] as List).map((r) => (r as List).map((c) => c as String?).toList()).toList();
      _answerGrid = (answerData['grid'] as List).map((r) => (r as List).map((c) => c as String?).toList()).toList();
      _acrossClues = (data['cluesAcross'] as List).map((c) => Map<String, dynamic>.from(c)).toList();
      _downClues = (data['cluesDown'] as List).map((c) => Map<String, dynamic>.from(c)).toList();
      _elapsed = data['elapsed'] ?? 0;
      _completed = data['completed'] ?? false;
      _completedTime = data['timeSeconds'];
      if (_completed) {
        _hideClues = true;
        _failed = (_completedTime ?? 0) >= 600;
        _message = _failed ? 'Failed — Better luck tomorrow!' : 'Completed in ${_formatTime(_completedTime ?? _elapsed)}!';
      } else {
        _startTimer();
      }
    } catch (e) {
      _message = 'Failed to load puzzle';
    }
    setState(() => _loading = false);
    _focusNode.requestFocus();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  void _onCellTap(int row, int col) {
    if (_completed) return;
    if (_grid[row][col] == null) return;
    if (row == _selRow && col == _selCol) {
      setState(() => _isAcross = !_isAcross);
    } else {
      setState(() { _selRow = row; _selCol = col; });
    }
    _focusNode.requestFocus();
  }

  void _onClueTap(Map<String, dynamic> clue, bool across) {
    if (_completed) return;
    setState(() {
      _selRow = clue['row'];
      _selCol = clue['col'];
      _isAcross = across;
    });
    _focusNode.requestFocus();
  }

  int? get _activeClueNumber {
    if (_selRow == null || _selCol == null) return null;
    final clues = _isAcross ? _acrossClues : _downClues;
    for (final c in clues) {
      final r = c['row'] as int, col = c['col'] as int, len = c['length'] as int;
      if (_isAcross && r == _selRow && _selCol! >= col && _selCol! < col + len) return c['number'];
      if (!_isAcross && col == _selCol && _selRow! >= r && _selRow! < r + len) return c['number'];
    }
    return null;
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent || _completed || _selRow == null) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _clearAndMoveBack();
    } else if (key == LogicalKeyboardKey.tab) {
      setState(() => _isAcross = !_isAcross);
    } else {
      final ch = event.character;
      if (ch != null && RegExp(r'^[a-zA-Z]$').hasMatch(ch)) {
        _enterLetter(ch.toUpperCase());
      }
    }
  }

  void _enterLetter(String letter) {
    setState(() {
      _grid[_selRow!][_selCol!] = letter;
    });
    _advance();
    _checkCompletion();
    _autoSave();
  }

  void _clearAndMoveBack() {
    if (_grid[_selRow!][_selCol!]?.isNotEmpty == true) {
      setState(() => _grid[_selRow!][_selCol!] = '');
    } else {
      _moveBack();
      setState(() => _grid[_selRow!][_selCol!] = '');
    }
    _autoSave();
  }

  void _advance() {
    if (_isAcross) {
      for (int c = _selCol! + 1; c < (_grid.isNotEmpty ? _grid[0].length : 0); c++) {
        if (_grid[_selRow!][c] != null) { setState(() => _selCol = c); return; }
      }
    } else {
      for (int r = _selRow! + 1; r < _grid.length; r++) {
        if (_grid[r][_selCol!] != null) { setState(() => _selRow = r); return; }
      }
    }
  }

  void _moveBack() {
    if (_isAcross) {
      for (int c = _selCol! - 1; c >= 0; c--) {
        if (_grid[_selRow!][c] != null) { setState(() => _selCol = c); return; }
      }
    } else {
      for (int r = _selRow! - 1; r >= 0; r--) {
        if (_grid[r][_selCol!] != null) { setState(() => _selRow = r); return; }
      }
    }
  }

  bool get _allFilled {
    for (int r = 0; r < _grid.length; r++) {
      for (int c = 0; c < _grid[r].length; c++) {
        if (_grid[r][c] != null && (_grid[r][c]?.isEmpty ?? true)) return false;
      }
    }
    return true;
  }

  Future<void> _checkCompletion() async {
    if (!_allFilled) return;
    try {
      final res = await CrosswordApi.complete(_grid, _elapsed);
      if (res['correct'] == true) {
        _timer?.cancel();
        setState(() {
          _completed = true;
          _completedTime = res['timeSeconds'] ?? _elapsed;
          _message = 'Completed in ${_formatTime(_completedTime!)}!';
          _hideClues = true;
        });
      }
    } catch (_) {}
  }

  Timer? _saveDebounce;
  void _autoSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      if (!_completed) CrosswordApi.save(_grid, _elapsed);
    });
  }

  void _useHint() {
    if (_hintsLeft <= 0 || _completed || _selRow == null || _selCol == null) return;
    if (_answerGrid.isEmpty) return;
    final answer = _answerGrid[_selRow!][_selCol!];
    if (answer == null) return;
    setState(() {
      _grid[_selRow!][_selCol!] = answer;
      _hintsLeft--;
    });
    _autoSave();
    _checkCompletion();
  }

  void _checkWord() {
    if (_checksLeft <= 0 || _completed || _selRow == null || _selCol == null) return;
    final clues = _isAcross ? _acrossClues : _downClues;
    Map<String, dynamic>? activeClue;
    for (final c in clues) {
      final r = c['row'] as int, col = c['col'] as int, len = c['length'] as int;
      if (_isAcross && r == _selRow && _selCol! >= col && _selCol! < col + len) { activeClue = c; break; }
      if (!_isAcross && col == _selCol && _selRow! >= r && _selRow! < r + len) { activeClue = c; break; }
    }
    if (activeClue == null) return;

    setState(() => _checksLeft--);

    final r = activeClue['row'] as int;
    final c = activeClue['col'] as int;
    final len = activeClue['length'] as int;
    final dr = _isAcross ? 0 : 1;
    final dc = _isAcross ? 1 : 0;

    bool allCorrect = true;
    for (int i = 0; i < len; i++) {
      final cr = r + dr * i, cc = c + dc * i;
      final userLetter = (_grid[cr][cc] ?? '').toUpperCase();
      final answerLetter = (_answerGrid[cr][cc] ?? '').toUpperCase();
      if (userLetter != answerLetter) { allCorrect = false; break; }
    }

    if (allCorrect) {
      setState(() {
        for (int i = 0; i < len; i++) {
          _correctCells.add('${r + dr * i}:${c + dc * i}');
        }
      });
    } else {
      setState(() => _shakeWord = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _shakeWord = false);
      });
    }
  }

  Future<void> _giveUp() async {
    if (_completed) return;
    _timer?.cancel();
    try {
      await CrosswordApi.giveUp();
    } catch (_) {}
    setState(() {
      // Reveal all answers
      for (int r = 0; r < _answerGrid.length; r++) {
        for (int c = 0; c < _answerGrid[r].length; c++) {
          if (_answerGrid[r][c] != null) _grid[r][c] = _answerGrid[r][c];
        }
      }
      _completed = true;
      _failed = true;
      _message = 'Failed — Better luck tomorrow!';
      _hideClues = true;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onTap, Color color) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.15) : const Color(0xFF1A1A1B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? color.withValues(alpha: 0.4) : const Color(0xFF3A3A3C)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: enabled ? color : Colors.grey, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: enabled ? color : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: widget.theme.correct));

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
                Text('Cross.IT', style: TextStyle(
                  fontFamily: 'Trebuchet MS', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: widget.theme.correct, blurRadius: 8), Shadow(color: widget.theme.correct, blurRadius: 16)],
                )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: widget.theme.absent, borderRadius: BorderRadius.circular(6)),
                  child: Text('⏱ ${_formatTime(_elapsed)}', style: TextStyle(color: widget.theme.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF3A3A3C), height: 1),

          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 32, bottom: 16),
                  child: Column(
                    children: [
                      // Grid
                      CrosswordGrid(
                        grid: _grid,
                        cluesAcross: _acrossClues,
                        cluesDown: _downClues,
                        selectedRow: _selRow,
                        selectedCol: _selCol,
                        isAcross: _isAcross,
                        onCellTap: _onCellTap,
                        theme: widget.theme,
                        completed: _completed,
                        correctCells: _correctCells,
                        shakeWord: _shakeWord,
                      ),

                      // Action buttons
                      if (!_completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _actionButton(Icons.lightbulb_outline, 'Hint ($_hintsLeft)', _hintsLeft > 0 ? _useHint : null, widget.theme.present),
                              const SizedBox(width: 12),
                              _actionButton(Icons.check_circle_outline, 'Check ($_checksLeft)', _checksLeft > 0 ? _checkWord : null, widget.theme.correct),
                              const SizedBox(width: 12),
                              _actionButton(Icons.flag_outlined, 'Give Up', _giveUp, Colors.redAccent),
                            ],
                          ),
                        ),

                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_message!, style: TextStyle(color: _failed ? Colors.redAccent : widget.theme.correct, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),

                      if (_completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ElevatedButton(
                            onPressed: widget.onLeaderboard,
                            style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
                            child: const Text('View Leaderboard', style: TextStyle(color: Colors.white)),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Clues — fade and collapse when completed
                      AnimatedSize(
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          opacity: _hideClues ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 1000),
                          curve: Curves.easeOut,
                          child: _hideClues
                              ? const SizedBox(width: double.infinity)
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: ClueList(title: 'ACROSS', clues: _acrossClues, activeNumber: _isAcross ? _activeClueNumber : null, onClueTap: (c) => _onClueTap(c, true), theme: widget.theme)),
                                    const SizedBox(width: 16),
                                    Expanded(child: ClueList(title: 'DOWN', clues: _downClues, activeNumber: !_isAcross ? _activeClueNumber : null, onClueTap: (c) => _onClueTap(c, false), theme: widget.theme)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saveDebounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }
}
