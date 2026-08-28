/// Game state management for Sudo.IT.
///
/// Holds the complete mutable state for one puzzle session:
/// board, notes, conflicts, undo stack, selected cell, notes mode, and
/// solved flag.  Also handles SharedPreferences persistence per difficulty
/// per day.
library sudoku.sudoku_state;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Difficulty enum
// ---------------------------------------------------------------------------

/// The three playable difficulty levels.
///
/// Defined here (rather than in the generator) so the state layer can be
/// compiled and tested independently without importing the full generator.
enum SudokuDifficulty { easy, medium, hard }

extension SudokuDifficultyLabel on SudokuDifficulty {
  /// Lowercase label used in SharedPreferences key suffixes.
  String get label => switch (this) {
    SudokuDifficulty.easy => 'easy',
    SudokuDifficulty.medium => 'medium',
    SudokuDifficulty.hard => 'hard',
  };
}

// ---------------------------------------------------------------------------
// UndoEntry
// ---------------------------------------------------------------------------

/// A snapshot of a single cell's state before a mutating action.
///
/// Used by the undo stack to restore the previous state of [cellIndex].
class UndoEntry {
  final int cellIndex;
  final int previousValue;

  /// A copy of the notes set for [cellIndex] at the time of the action.
  final Set<int> previousNotes;

  const UndoEntry({
    required this.cellIndex,
    required this.previousValue,
    required this.previousNotes,
  });
}

// ---------------------------------------------------------------------------
// SudokuGameState
// ---------------------------------------------------------------------------

/// Holds all mutable state for a single Sudo.IT puzzle session.
///
/// The caller is responsible for calling [setState] (or equivalent) on the
/// enclosing Flutter widget whenever a mutating method returns.  All mutating
/// methods modify the object in-place and do not return a new instance.
class SudokuGameState {
  // ---- Core board state ----

  /// The initial puzzle clues — 81 ints, 0 = empty, 1–9 = given digit.
  /// Immutable after construction.
  final List<int> puzzle;

  /// The player's current board — 81 ints, 0 = empty, 1–9 = entered digit.
  final List<int> board;

  /// The unique solution — 81 ints, 1–9.  Used for validation (not exposed to
  /// the player, but available for future hint support).
  final List<int> solution;

  // ---- Notes ----

  /// Pencil marks — one [Set<int>] per cell (81 entries).
  /// Each set contains the candidate digits the player has noted.
  final List<Set<int>> notes;

  // ---- Conflict tracking ----

  /// The set of cell indices that are currently in conflict (duplicate digit
  /// in the same row, column, or 3×3 box).
  Set<int> conflicts;

  // ---- Undo stack ----

  /// Stack of previous cell states.  The top entry is the most recent action.
  /// Not persisted — cleared when switching puzzles.
  final List<UndoEntry> undoStack;

  // ---- UI state ----

  /// The currently selected cell index (0–80), or null if none.
  int? selectedCell;

  /// When true, tapping a number toggles a pencil mark instead of placing a
  /// digit.
  bool notesMode;

  /// True once the puzzle is fully and correctly solved.
  bool solved;

  // ---- Constructor ----

  SudokuGameState({
    required this.puzzle,
    required this.board,
    required this.solution,
    required this.notes,
    required this.conflicts,
    required this.undoStack,
    this.selectedCell,
    this.notesMode = false,
    this.solved = false,
  })  : assert(puzzle.length == 81, 'puzzle must have 81 cells'),
        assert(board.length == 81, 'board must have 81 cells'),
        assert(solution.length == 81, 'solution must have 81 cells'),
        assert(notes.length == 81, 'notes must have 81 entries');

  /// Creates a fresh game state from a generated puzzle + solution.
  ///
  /// [puzzle] is the given-clue board (0 = empty cell to be filled).
  /// [solution] is the complete solved grid.
  factory SudokuGameState.fromPuzzle({
    required List<int> puzzle,
    required List<int> solution,
  }) {
    return SudokuGameState(
      puzzle: List<int>.from(puzzle),
      board: List<int>.from(puzzle), // player starts with givens pre-filled
      solution: List<int>.from(solution),
      notes: List.generate(81, (_) => <int>{}),
      conflicts: <int>{},
      undoStack: [],
    );
  }

  // ---- Helpers ----

  /// Returns true if [cell] was pre-filled in the puzzle (a given clue).
  bool isGiven(int cell) => puzzle[cell] != 0;

  // ---- Mutating actions ----

  /// Places [digit] (1–9) in [cell], unless it is a given.
  ///
  /// - Pushes the previous cell state onto [undoStack].
  /// - Sets [board[cell]] to [digit].
  /// - Auto-clears that digit from notes in every peer cell (same row, col,
  ///   box) as a standard QoL feature.
  /// - Recomputes [conflicts].
  /// - Checks for completion and sets [solved] if the puzzle is done.
  void placeDigit(int cell, int digit) {
    if (isGiven(cell)) return;

    // Push undo entry before mutating.
    undoStack.add(
      UndoEntry(
        cellIndex: cell,
        previousValue: board[cell],
        previousNotes: Set<int>.from(notes[cell]),
      ),
    );

    board[cell] = digit;
    // Clear notes for this cell when a digit is placed.
    notes[cell].clear();

    // Auto-clear the placed digit from peer notes.
    for (final peer in _peers(cell)) {
      notes[peer].remove(digit);
    }

    conflicts = computeConflicts();
    if (checkCompletion()) solved = true;
  }

  /// Toggles pencil mark [digit] in [cell].
  ///
  /// Has no effect on given cells.  Pushes undo entry first.
  void toggleNote(int cell, int digit) {
    if (isGiven(cell)) return;

    undoStack.add(
      UndoEntry(
        cellIndex: cell,
        previousValue: board[cell],
        previousNotes: Set<int>.from(notes[cell]),
      ),
    );

    if (notes[cell].contains(digit)) {
      notes[cell].remove(digit);
    } else {
      notes[cell].add(digit);
    }
  }

  /// Clears the player-entered digit and all notes from [cell].
  ///
  /// Has no effect on given cells.  Pushes undo entry first.
  void erase(int cell) {
    if (isGiven(cell)) return;
    if (board[cell] == 0 && notes[cell].isEmpty) return;

    undoStack.add(
      UndoEntry(
        cellIndex: cell,
        previousValue: board[cell],
        previousNotes: Set<int>.from(notes[cell]),
      ),
    );

    board[cell] = 0;
    notes[cell].clear();

    conflicts = computeConflicts();
  }

  /// Pops the top [UndoEntry] and restores the cell to its previous state.
  ///
  /// Also recomputes [conflicts] after the restore.
  void undo() {
    if (undoStack.isEmpty) return;

    final entry = undoStack.removeLast();
    board[entry.cellIndex] = entry.previousValue;
    notes[entry.cellIndex]
      ..clear()
      ..addAll(entry.previousNotes);

    conflicts = computeConflicts();
    // A previously solved puzzle cannot be un-solved via undo because the
    // game becomes read-only on completion, but guard defensively.
    if (solved && !checkCompletion()) solved = false;
  }

  // ---- Conflict computation ----

  /// Scans the entire board for duplicate digits in rows, columns, and 3×3
  /// boxes.  Returns the set of all conflicting cell indices.
  ///
  /// A cell is conflicting if it shares the same non-zero digit with at least
  /// one other cell in the same group.
  Set<int> computeConflicts() {
    final result = <int>{};

    // Check all 9 rows.
    for (int r = 0; r < 9; r++) {
      final start = r * 9;
      _flagGroupConflicts(
        List.generate(9, (c) => start + c),
        result,
      );
    }

    // Check all 9 columns.
    for (int c = 0; c < 9; c++) {
      _flagGroupConflicts(
        List.generate(9, (r) => r * 9 + c),
        result,
      );
    }

    // Check all 9 boxes.
    for (int br = 0; br < 3; br++) {
      for (int bc = 0; bc < 3; bc++) {
        final indices = <int>[];
        for (int dr = 0; dr < 3; dr++) {
          for (int dc = 0; dc < 3; dc++) {
            indices.add((br * 3 + dr) * 9 + (bc * 3 + dc));
          }
        }
        _flagGroupConflicts(indices, result);
      }
    }

    return result;
  }

  /// Adds to [result] any index in [group] whose digit appears more than once.
  void _flagGroupConflicts(List<int> group, Set<int> result) {
    // Map digit → list of indices that hold it.
    final seen = <int, List<int>>{};
    for (final idx in group) {
      final digit = board[idx];
      if (digit == 0) continue;
      seen.putIfAbsent(digit, () => []).add(idx);
    }
    for (final indices in seen.values) {
      if (indices.length > 1) {
        result.addAll(indices);
      }
    }
  }

  // ---- Completion ----

  /// Returns true when every cell is filled (no zeros) and there are no
  /// conflicts.
  bool checkCompletion() {
    if (board.contains(0)) return false;
    if (conflicts.isNotEmpty) return false;
    return true;
  }

  // ---- Peer calculation ----

  /// Returns all cell indices that share a row, column, or 3×3 box with
  /// [cell] — excluding [cell] itself.
  List<int> _peers(int cell) {
    final row = cell ~/ 9;
    final col = cell % 9;
    final boxRow = (row ~/ 3) * 3;
    final boxCol = (col ~/ 3) * 3;

    final peers = <int>{};

    // Same row.
    for (int c = 0; c < 9; c++) {
      peers.add(row * 9 + c);
    }

    // Same column.
    for (int r = 0; r < 9; r++) {
      peers.add(r * 9 + col);
    }

    // Same box.
    for (int dr = 0; dr < 3; dr++) {
      for (int dc = 0; dc < 3; dc++) {
        peers.add((boxRow + dr) * 9 + (boxCol + dc));
      }
    }

    peers.remove(cell);
    return peers.toList();
  }

  // ---------------------------------------------------------------------------
  // SharedPreferences persistence
  // ---------------------------------------------------------------------------

  // Key schema (spec §Daily Persistence):
  //   sudoku_date                    — today's YYYY-MM-DD string
  //   sudoku_board_{easy|medium|hard} — JSON List<int>  (81 values)
  //   sudoku_notes_{easy|medium|hard} — JSON List<List<int>>  (81 entries)
  //   sudoku_solved_{easy|medium|hard} — bool

  static const _keyDate = 'sudoku_date';

  static String _boardKey(SudokuDifficulty d) => 'sudoku_board_${d.label}';
  static String _notesKey(SudokuDifficulty d) => 'sudoku_notes_${d.label}';
  static String _solvedKey(SudokuDifficulty d) => 'sudoku_solved_${d.label}';

  /// Persists the current [board], [notes], and [solved] flag for [difficulty].
  ///
  /// Also writes today's date string under [_keyDate] so the screen can detect
  /// day changes on next load.
  Future<void> saveState(SudokuDifficulty difficulty) async {
    final prefs = await SharedPreferences.getInstance();

    final today = _todayString();
    await prefs.setString(_keyDate, today);

    // Board — flat List<int>.
    final boardJson = jsonEncode(board);
    await prefs.setString(_boardKey(difficulty), boardJson);

    // Notes — List<List<int>>.
    final notesJson = jsonEncode(
      notes.map((s) => s.toList()..sort()).toList(),
    );
    await prefs.setString(_notesKey(difficulty), notesJson);

    // Solved flag.
    await prefs.setBool(_solvedKey(difficulty), solved);
  }

  /// Attempts to restore board state for [difficulty] from SharedPreferences.
  ///
  /// Returns `true` if state was successfully loaded (meaning the saved date
  /// matches today AND data is present and valid).
  /// Returns `false` if no matching data exists — the caller should use the
  /// freshly generated puzzle state as-is.
  Future<bool> loadState(SudokuDifficulty difficulty) async {
    final prefs = await SharedPreferences.getInstance();

    final savedDate = prefs.getString(_keyDate);
    if (savedDate != _todayString()) {
      // Stale — do not load.
      return false;
    }

    final boardStr = prefs.getString(_boardKey(difficulty));
    final notesStr = prefs.getString(_notesKey(difficulty));
    if (boardStr == null || notesStr == null) return false;

    try {
      // Decode board.
      final boardDecoded = (jsonDecode(boardStr) as List).cast<int>();
      if (boardDecoded.length != 81) return false;

      // Decode notes.
      final notesDecoded = (jsonDecode(notesStr) as List)
          .map((e) => (e as List).cast<int>().toSet())
          .toList();
      if (notesDecoded.length != 81) return false;

      // Apply to this state object.
      for (int i = 0; i < 81; i++) {
        board[i] = boardDecoded[i];
        notes[i]
          ..clear()
          ..addAll(notesDecoded[i]);
      }

      solved = prefs.getBool(_solvedKey(difficulty)) ?? false;
      conflicts = computeConflicts();

      return true;
    } catch (_) {
      // Corrupt data — treat as no saved state.
      return false;
    }
  }

  /// Removes all `sudoku_*` keys from SharedPreferences.
  ///
  /// Called when the date has changed and all saved progress should be wiped.
  static Future<void> clearAllState() async {
    final prefs = await SharedPreferences.getInstance();

    final keysToRemove = prefs.getKeys().where((k) => k.startsWith('sudoku_')).toList();
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  // ---- Date helper ----

  /// Returns today's date as `YYYY-MM-DD`.
  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Returns the saved date string from SharedPreferences, or null.
  ///
  /// Used by the screen to detect day changes on init.
  static Future<String?> savedDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDate);
  }
}
