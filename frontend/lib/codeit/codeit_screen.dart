import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_theme.dart';
import 'dsl/errors.dart';
import 'dsl/executor.dart';
import 'dsl/parser.dart';
import 'dsl/tokenizer.dart';
import 'puzzle_generator.dart';
import 'widgets/code_editor.dart';
import 'widgets/console_output.dart';
import 'widgets/pixel_grid.dart';

/// The Code.IT daily coding puzzle screen.
///
/// Players write a small Python-like DSL program to reproduce a
/// deterministically generated 5×5 target grid.  All execution is
/// client-side; the backend is only touched for optional completion tracking.
class CodeItScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final int userId;
  final String nickname;

  const CodeItScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.userId,
    required this.nickname,
  });

  @override
  State<CodeItScreen> createState() => _CodeItScreenState();
}

class _CodeItScreenState extends State<CodeItScreen> {
  late final TextEditingController _codeController;
  late final List<List<String>> _target;
  late final int _puzzleNum;

  List<List<String>> _userGrid =
      List.generate(5, (_) => List.generate(5, (_) => 'black'));
  List<List<bool>>? _matchOverlay;
  String _consoleMsg = '';
  ConsoleType _consoleType = ConsoleType.info;
  int _attempts = 0;
  bool _solved = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    final now = DateTime.now();
    _target = generateTarget(now);
    _puzzleNum = puzzleNumber(now);
    _loadSavedCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  String _todayKey() {
    final now = DateTime.now();
    return 'codeit_code_${now.year}-${now.month}-${now.day}';
  }

  Future<void> _loadSavedCode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_todayKey());
    if (saved != null && saved.isNotEmpty) {
      // Defer setting the controller until after first frame so the
      // TextField is mounted and the cursor position is handled cleanly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeController.text = saved;
      });
    }
  }

  Future<void> _saveCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_todayKey(), _codeController.text);
  }

  // ── Game actions ─────────────────────────────────────────────────────────

  void _run() {
    _saveCode();
    final source = _codeController.text.trim();

    if (source.isEmpty) {
      setState(() {
        _userGrid = List.generate(5, (_) => List.generate(5, (_) => 'black'));
        _matchOverlay = null;
        _consoleMsg = '0/25 cells match';
        _consoleType = ConsoleType.info;
      });
      return;
    }

    try {
      final tokens = tokenize(source);
      final ast = parse(tokens);
      final result = DslExecutor().execute(ast);

      if (result.error != null) {
        setState(() {
          _userGrid = result.grid;
          _matchOverlay = null;
          _consoleMsg = result.error!;
          _consoleType = ConsoleType.error;
        });
        return;
      }

      // Compare result grid with target and build the overlay.
      int matching = 0;
      final overlay = List.generate(5, (x) {
        return List.generate(5, (y) {
          final match = result.grid[x][y] == _target[x][y];
          if (match) matching++;
          return match;
        });
      });

      _attempts++;

      if (matching == 25) {
        setState(() {
          _userGrid = result.grid;
          _matchOverlay = overlay;
          _consoleMsg =
              '🎉 Perfect! All 25 cells match! '
              'Solved in $_attempts attempt${_attempts == 1 ? '' : 's'}!';
          _consoleType = ConsoleType.success;
          _solved = true;
        });
      } else {
        setState(() {
          _userGrid = result.grid;
          _matchOverlay = overlay;
          _consoleMsg = '$matching/25 cells match';
          _consoleType = ConsoleType.info;
        });
      }
    } on DslError catch (e) {
      setState(() {
        _matchOverlay = null;
        _consoleMsg = e.toString();
        _consoleType = ConsoleType.error;
      });
    } catch (e) {
      setState(() {
        _matchOverlay = null;
        _consoleMsg = 'Unexpected error: $e';
        _consoleType = ConsoleType.error;
      });
    }
  }

  void _reset() {
    setState(() {
      _codeController.clear();
      _userGrid = List.generate(5, (_) => List.generate(5, (_) => 'black'));
      _matchOverlay = null;
      _consoleMsg = '';
      _consoleType = ConsoleType.info;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    _buildGridRow(),
                    const SizedBox(height: 16),
                    CodeEditor(
                      controller: _codeController,
                      enabled: !_solved,
                    ),
                    const SizedBox(height: 12),
                    _buildButtonRow(),
                    const SizedBox(height: 12),
                    if (_consoleMsg.isNotEmpty)
                      ConsoleOutput(
                        message: _consoleMsg,
                        type: _consoleType,
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

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
            'Code.IT',
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

  Widget _buildGridRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PixelGrid(
          grid: _userGrid,
          matchOverlay: _matchOverlay,
          label: 'Your Output',
        ),
        const SizedBox(width: 16),
        PixelGrid(
          grid: _target,
          label: 'Target',
        ),
      ],
    );
  }

  Widget _buildButtonRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _solved ? null : _run,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Run'),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.correct,
              foregroundColor: Colors.white,
              disabledBackgroundColor: widget.theme.correct.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _solved ? null : _reset,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF3A3A3C)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Reset',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
