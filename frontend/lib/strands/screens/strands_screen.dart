import 'package:flutter/material.dart';
import '../../models/app_theme.dart';
import '../services/strands_api.dart';
import '../widgets/strand_grid.dart';

class StrandsScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final VoidCallback onLeaderboard;
  const StrandsScreen({super.key, required this.theme, required this.onBack, required this.onLeaderboard});

  @override
  State<StrandsScreen> createState() => _StrandsScreenState();
}

class _StrandsScreenState extends State<StrandsScreen> {
  List<List<String>> _grid = [];
  int _wordCount = 0;
  List<Map<String, dynamic>> _foundWords = [];
  int _hintCharges = 0;
  int _hintsUsed = 0;
  bool _completed = false;
  bool _checking = false;
  bool _loading = true;
  String? _message;
  Color? _messageColor;
  Set<String> _foundThemeCells = {};
  Set<String> _foundSpangramCells = {};
  Set<String> _hintCells = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await StrandsApi.getToday();
      _grid = (data['grid'] as List).map((r) => (r as List).map((c) => c.toString()).toList()).toList();
      _wordCount = data['wordCount'] ?? 0;
      _hintCharges = data['hintCharges'] ?? 0;
      _hintsUsed = data['hintsUsed'] ?? 0;
      _completed = data['completed'] ?? false;
      _foundWords = List<Map<String, dynamic>>.from(data['foundWords'] ?? []);
      _rebuildCellSets();
    } catch (e) {
      _message = 'Failed to load puzzle';
    }
    setState(() => _loading = false);
  }

  void _rebuildCellSets() {
    _foundThemeCells = {};
    _foundSpangramCells = {};
    _hintCells = {};
    for (final fw in _foundWords) {
      final type = fw['type'];
      final path = fw['path'] as List?;
      if (path == null) continue;
      for (final p in path) {
        final key = '${(p as List)[0]}:${p[1]}';
        if (type == 'target') _foundThemeCells.add(key);
      }
    }
  }

  int get _themeFound => _foundWords.where((f) => f['type'] == 'target').length;
  int get _nonThemeFound => _foundWords.where((f) => f['type'] == 'bonus').length;

  Future<void> _onWordSubmit(List<List<int>> path) async {
    if (_completed || _checking) return;
    setState(() => _checking = true);
    try {
      final res = await StrandsApi.checkWord(path);
      final type = res['type'];
      if (type == 'target') {
        _foundWords.add({'word': res['word'], 'type': 'target', 'path': path});
        _showMessage('✓ ${res['word']}!', widget.theme.correct);
        if (res['completed'] == true) _completed = true;
      } else if (type == 'bonus') {
        _hintCharges = res['hintCharges'] ?? _hintCharges;
        _foundWords.add({'word': res['word'], 'type': 'bonus', 'path': path});
        final bc = res['bonusCount'] ?? 0;
        _showMessage('${res['word']} — bonus word! (${bc % 3}/3 to hint)', Colors.grey);
      } else if (type == 'already_found') {
        _showMessage('Already found!', Colors.grey);
      } else {
        _showMessage('Not a valid word', Colors.redAccent);
      }
      _rebuildCellSets();
      setState(() => _checking = false);
    } catch (e) {
      _showMessage('Error checking word', Colors.redAccent);
      setState(() => _checking = false);
    }
  }

  void _showMessage(String msg, Color color) {
    setState(() { _message = msg; _messageColor = color; });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _useHint() async {
    if (_hintCharges <= 0) return;
    try {
      final res = await StrandsApi.useHint();
      if (res['error'] != null) {
        _showMessage(res['error'], Colors.redAccent);
        return;
      }
      _hintCharges = res['hintCharges'] ?? (_hintCharges - 1);
      _hintsUsed++;
      if (res['level'] == 1) {
        // Show cells
        final cells = (res['cells'] as List).map((p) => '${(p as List)[0]}:${p[1]}').toSet();
        setState(() => _hintCells = cells);
        _showMessage('Hint: letters highlighted on grid', widget.theme.present);
      } else if (res['level'] == 2) {
        _showMessage('Hint: the word is ${res['word']}', widget.theme.present);
        final path = (res['path'] as List).map((p) => '${(p as List)[0]}:${p[1]}').toSet();
        setState(() => _hintCells = path);
      }
    } catch (e) {
      _showMessage('Error using hint', Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: widget.theme.correct));

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
              Text('Span.IT', style: TextStyle(
                fontFamily: 'Trebuchet MS', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                shadows: [Shadow(color: widget.theme.correct, blurRadius: 8), Shadow(color: widget.theme.correct, blurRadius: 16)],
              )),
              const Spacer(),
              GestureDetector(
                onTap: _hintCharges > 0 ? _useHint : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _hintCharges > 0 ? widget.theme.present.withValues(alpha: 0.2) : widget.theme.absent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _hintCharges > 0 ? widget.theme.present : widget.theme.absent),
                  ),
                  child: Text('💡 $_hintCharges', style: TextStyle(color: _hintCharges > 0 ? widget.theme.present : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    // Word count
                    Text('Find $_wordCount hidden dev words!', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.7), fontSize: 14)),
                    const SizedBox(height: 12),

                    // Message
                    SizedBox(
                      height: 28,
                      child: _message != null
                          ? Text(_message!, style: TextStyle(color: _messageColor ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold))
                          : null,
                    ),

                    // Grid
                    StrandGrid(
                      grid: _grid,
                      foundThemeCells: _foundThemeCells,
                      foundSpangramCells: _foundSpangramCells,
                      hintCells: _hintCells,
                      onWordSubmit: _onWordSubmit,
                      theme: widget.theme,
                      completed: _completed,
                      checking: _checking,
                    ),

                    const SizedBox(height: 16),

                    // Progress
                    Text('Theme: $_themeFound/$_wordCount   Non-theme: $_nonThemeFound (${_nonThemeFound % 3}/3 to hint)',
                      style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.5), fontSize: 12)),

                    if (_completed) ...[
                      const SizedBox(height: 12),
                      Text('🎉 Puzzle Complete! Hints used: $_hintsUsed', style: TextStyle(color: widget.theme.correct, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: widget.onLeaderboard,
                        style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct),
                        child: const Text('View Leaderboard', style: TextStyle(color: Colors.white)),
                      ),
                    ],

                    // Found words
                    if (_foundWords.where((f) => f['type'] == 'target').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8, runSpacing: 6,
                        children: _foundWords.where((f) => f['type'] == 'target').map((f) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.theme.correct,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(f['word'], style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
