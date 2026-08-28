// Main screen for Sudo.IT — the Fuse Arcade daily Sudoku game.
//
// Composes the grid, number pad, header, and difficulty tabs. All puzzle
// generation and persistence is fully client-side (no backend involvement).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_theme.dart';
import 'sudoku_generator.dart';
import 'sudoku_state.dart';
import 'widgets/sudoku_grid.dart';
import 'widgets/sudoku_numpad.dart';

// ---------------------------------------------------------------------------
// SudokuScreen
// ---------------------------------------------------------------------------

/// The top-level Sudo.IT screen.
///
/// Props:
/// - [theme]    — app-wide colour theme.
/// - [onBack]   — invoked when the user presses the back button.
/// - [nickname] — player's display name (reserved for future leaderboard).
/// - [userId]   — player's ID (reserved for future leaderboard).
class SudokuScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const SudokuScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

// ---------------------------------------------------------------------------
// _SudokuScreenState
// ---------------------------------------------------------------------------

class _SudokuScreenState extends State<SudokuScreen>
    with WidgetsBindingObserver {
  // ── Core state ─────────────────────────────────────────────────────────

  SudokuDifficulty _difficulty = SudokuDifficulty.easy;

  /// Game state keyed by difficulty — lazily initialised on first access.
  final Map<SudokuDifficulty, SudokuGameState> _states = {};

  late int _puzzleNum;

  /// Whether we are still loading the initial state from SharedPreferences.
  bool _loading = true;

  // ── Keyboard focus ──────────────────────────────────────────────────────

  final FocusNode _focusNode = FocusNode();

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _puzzleNum = puzzleNumber(now);
    _initAllDifficulties(now);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    super.dispose();
  }

  /// Called when the app resumes from background — detect date change.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDateChange();
    }
  }

  // ── Initialisation ──────────────────────────────────────────────────────

  /// Generates puzzles for all three difficulties and restores any saved state.
  Future<void> _initAllDifficulties(DateTime date) async {
    // Check if the saved date still matches today — clear stale state first.
    final saved = await SudokuGameState.savedDate();
    final today = SudokuGameState.todayString();
    if (saved != null && saved != today) {
      await SudokuGameState.clearAllState();
    }

    // Generate and (try to) restore each difficulty.
    for (final diff in SudokuDifficulty.values) {
      final (:puzzle, :solution) = generatePuzzle(date, diff);
      final gs = SudokuGameState.fromPuzzle(puzzle: puzzle, solution: solution);
      await gs.loadState(diff);
      _states[diff] = gs;
    }

    if (mounted) {
      setState(() => _loading = false);
    }

    // Request keyboard focus after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  /// Checks whether the calendar date has rolled over since the last init.
  Future<void> _checkDateChange() async {
    final saved = await SudokuGameState.savedDate();
    final today = SudokuGameState.todayString();
    if (saved != null && saved != today) {
      // New day — reinitialise everything.
      setState(() => _loading = true);
      _states.clear();
      final now = DateTime.now();
      _puzzleNum = puzzleNumber(now);
      await _initAllDifficulties(now);
    }
  }

  // ── Difficulty switching ─────────────────────────────────────────────────

  /// Switches to [d] and saves current difficulty's state before doing so.
  Future<void> _changeDifficulty(SudokuDifficulty d) async {
    if (_difficulty == d) return;

    // Persist current difficulty's progress.
    await _currentState.saveState(_difficulty);

    setState(() => _difficulty = d);

    // Regain keyboard focus after tab switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  // ── Convenience getters ─────────────────────────────────────────────────

  SudokuGameState get _currentState => _states[_difficulty]!;

  bool get _isSolved => _currentState.solved;

  // ── Game actions ────────────────────────────────────────────────────────

  void _onCellTap(int index) {
    if (_isSolved) return;
    setState(() => _currentState.selectedCell = index);
  }

  Future<void> _onNumber(int digit) async {
    if (_isSolved) return;
    final gs = _currentState;
    final cell = gs.selectedCell;
    if (cell == null || gs.isGiven(cell)) return;

    setState(() {
      if (gs.notesMode) {
        gs.toggleNote(cell, digit);
      } else {
        gs.placeDigit(cell, digit);
      }
    });

    if (gs.solved) {
      await _onPuzzleSolved();
    } else {
      await gs.saveState(_difficulty);
    }
  }

  void _onNotes() {
    if (_isSolved) return;
    setState(() => _currentState.notesMode = !_currentState.notesMode);
  }

  Future<void> _onUndo() async {
    if (_isSolved) return;
    setState(() => _currentState.undo());
    await _currentState.saveState(_difficulty);
  }

  Future<void> _onErase() async {
    if (_isSolved) return;
    final gs = _currentState;
    final cell = gs.selectedCell;
    if (cell == null) return;
    setState(() => gs.erase(cell));
    await gs.saveState(_difficulty);
  }

  Future<void> _onPuzzleSolved() async {
    // Persist first, then the setState from _onNumber's caller already
    // triggers the rebuild that shows the completion overlay.
    await _currentState.saveState(_difficulty);
  }

  // ── Physical keyboard ───────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isSolved) return KeyEventResult.ignored;

    final logicalKey = event.logicalKey;

    // Arrow key navigation.
    if (logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-9);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(9);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }

    // Digit keys 1–9.
    for (int d = 1; d <= 9; d++) {
      if (logicalKey == LogicalKeyboardKey(0x00000030 + d) ||
          logicalKey == LogicalKeyboardKey(0x00070000 + d + 0x58)) {
        _onNumber(d);
        return KeyEventResult.handled;
      }
    }

    // Also handle Digit1–Digit9 and Numpad1–Numpad9.
    final keyLabel = event.character;
    if (keyLabel != null && keyLabel.length == 1) {
      final code = keyLabel.codeUnitAt(0);
      if (code >= 49 && code <= 57) {
        // ASCII '1' = 49, '9' = 57
        _onNumber(code - 48);
        return KeyEventResult.handled;
      }
    }

    // Backspace / Delete → erase.
    if (logicalKey == LogicalKeyboardKey.backspace ||
        logicalKey == LogicalKeyboardKey.delete) {
      _onErase();
      return KeyEventResult.handled;
    }

    // 'n' → toggle notes mode.
    if (logicalKey == LogicalKeyboardKey.keyN) {
      _onNotes();
      return KeyEventResult.handled;
    }

    // 'z' → undo.
    if (logicalKey == LogicalKeyboardKey.keyZ) {
      _onUndo();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Moves the selected cell by [delta] positions (wraps around the grid).
  void _moveSelection(int delta) {
    final gs = _currentState;
    final current = gs.selectedCell;
    int next;
    if (current == null) {
      next = 0;
    } else {
      // For horizontal movement, clamp within the same row.
      if (delta == 1 || delta == -1) {
        final row = current ~/ 9;
        next = (current + delta).clamp(row * 9, row * 9 + 8);
      } else {
        next = (current + delta).clamp(0, 80);
      }
    }
    setState(() => gs.selectedCell = next);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(
        children: [
          _buildHeader(),
          const Divider(color: Color(0xFF3A3A3C), height: 1),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          ),
        ],
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) => _handleKey(_focusNode, event),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(color: Color(0xFF3A3A3C), height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _buildDifficultyTabs(),
                      const SizedBox(height: 16),
                      // Grid + optional completion overlay.
                      Stack(
                        children: [
                          SudokuGrid(
                            board: _currentState.board,
                            puzzle: _currentState.puzzle,
                            notes: _currentState.notes,
                            conflicts: _currentState.conflicts,
                            selectedCell: _isSolved ? null : _currentState.selectedCell,
                            onCellTap: _onCellTap,
                            theme: widget.theme,
                          ),
                          if (_isSolved) _buildCompletionOverlay(),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_isSolved)
                        _buildCompletedMessage()
                      else
                        SudokuNumpad(
                          onNumber: _onNumber,
                          onNotes: _onNotes,
                          onUndo: _onUndo,
                          onErase: _onErase,
                          notesMode: _currentState.notesMode,
                          board: _currentState.board,
                          theme: widget.theme,
                        ),
                      const SizedBox(height: 24),
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

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBack,
            tooltip: 'Back',
          ),
          Text(
            'Sudo.IT',
            style: TextStyle(
              color: widget.theme.correct,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            'Puzzle #$_puzzleNum',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Difficulty tabs ──────────────────────────────────────────────────────

  Widget _buildDifficultyTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDiffTab('Easy', SudokuDifficulty.easy),
        const SizedBox(width: 8),
        _buildDiffTab('Medium', SudokuDifficulty.medium),
        const SizedBox(width: 8),
        _buildDiffTab('Hard', SudokuDifficulty.hard),
      ],
    );
  }

  Widget _buildDiffTab(String label, SudokuDifficulty d) {
    final selected = _difficulty == d;
    // Show a completion badge on tabs that are already solved.
    final tabSolved = _states[d]?.solved ?? false;

    return GestureDetector(
      onTap: () => _changeDifficulty(d),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? widget.theme.correct.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? widget.theme.correct
                : const Color(0xFF3A3A3C),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? widget.theme.correct : Colors.grey,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
            if (tabSolved) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_circle,
                size: 12,
                color: selected
                    ? widget.theme.correct
                    : widget.theme.correct.withValues(alpha: 0.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Completion overlay ───────────────────────────────────────────────────

  Widget _buildCompletionOverlay() {
    final diffName = switch (_difficulty) {
      SudokuDifficulty.easy => 'Easy',
      SudokuDifficulty.medium => 'Medium',
      SudokuDifficulty.hard => 'Hard',
    };

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🎉',
                style: TextStyle(fontSize: 40),
              ),
              const SizedBox(height: 8),
              const Text(
                'Puzzle Complete!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                diffName,
                style: TextStyle(
                  color: widget.theme.correct,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Replaces the number pad when the puzzle is solved.
  Widget _buildCompletedMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: widget.theme.correct.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.theme.correct.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Text(
          'Completed — come back tomorrow!',
          style: TextStyle(
            color: widget.theme.correct,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
