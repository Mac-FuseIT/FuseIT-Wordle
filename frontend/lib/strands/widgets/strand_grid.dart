import 'package:flutter/material.dart';
import '../../models/app_theme.dart';

class StrandGrid extends StatefulWidget {
  final List<List<String>> grid;
  final Set<String> foundThemeCells;
  final Set<String> foundSpangramCells;
  final Set<String> hintCells;
  final Function(List<List<int>>) onWordSubmit;
  final AppTheme theme;
  final bool completed;
  final bool checking;
  final List<Map<String, dynamic>> foundTargetPaths;

  const StrandGrid({
    super.key,
    required this.grid,
    required this.foundThemeCells,
    required this.foundSpangramCells,
    required this.hintCells,
    required this.onWordSubmit,
    required this.theme,
    this.completed = false,
    this.checking = false,
    this.foundTargetPaths = const [],
  });

  @override
  State<StrandGrid> createState() => _StrandGridState();
}

class _StrandGridState extends State<StrandGrid> {
  List<List<int>> _currentPath = [];
  final _gridKey = GlobalKey();
  static const _cellSize = 46.0;
  static const _gap = 8.0;
  static const _cols = 6;
  static const _rows = 8;

  bool _isAdjacent(List<int> a, List<int> b) {
    return (a[0] - b[0]).abs() <= 1 && (a[1] - b[1]).abs() <= 1 && !(a[0] == b[0] && a[1] == b[1]);
  }

  List<int>? _cellFromPosition(Offset localPos) {
    final step = _cellSize + _gap;
    final col = (localPos.dx / step).floor();
    final row = (localPos.dy / step).floor();
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) return null;
    // Check if within the circle
    final cx = col * step + _cellSize / 2;
    final cy = row * step + _cellSize / 2;
    final dx = localPos.dx - cx;
    final dy = localPos.dy - cy;
    if (dx * dx + dy * dy > (_cellSize / 2 + _gap) * (_cellSize / 2 + _gap)) return null;
    return [row, col];
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.completed || widget.checking) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final cell = _cellFromPosition(local);
    if (cell != null) setState(() => _currentPath = [cell]);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.completed || widget.checking || _currentPath.isEmpty) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final cell = _cellFromPosition(local);
    if (cell == null) return;

    if (_currentPath.length >= 2 && _currentPath[_currentPath.length - 2][0] == cell[0] && _currentPath[_currentPath.length - 2][1] == cell[1]) {
      setState(() => _currentPath.removeLast());
      return;
    }
    if (_currentPath.any((p) => p[0] == cell[0] && p[1] == cell[1])) return;
    if (!_isAdjacent(_currentPath.last, cell)) return;
    setState(() => _currentPath.add(cell));
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_currentPath.length >= 3) {
      widget.onWordSubmit(List.from(_currentPath.map((p) => List<int>.from(p))));
    }
    setState(() => _currentPath = []);
  }

  String get _currentWord => _currentPath.map((p) => widget.grid[p[0]][p[1]]).join('');

  @override
  Widget build(BuildContext context) {
    final pathSet = _currentPath.map((p) => '${p[0]}:${p[1]}').toSet();
    final step = _cellSize + _gap;
    final gridWidth = _cols * step;
    final gridHeight = _rows * step;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Current word / loading
        Container(
          height: 36,
          alignment: Alignment.center,
          child: widget.checking
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: widget.theme.correct))
              : Text(_currentWord, style: TextStyle(color: widget.theme.textColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onPanStart: _handleDragStart,
          onPanUpdate: _handleDragUpdate,
          onPanEnd: _handleDragEnd,
          child: SizedBox(
            key: _gridKey,
            width: gridWidth,
            height: gridHeight,
            child: Stack(
              children: [
                // Draw found target paths (persistent)
                for (final fw in widget.foundTargetPaths)
                  CustomPaint(
                    size: Size(gridWidth, gridHeight),
                    painter: _PathPainter(
                      path: (fw['path'] as List).map<List<int>>((p) => [p[0] as int, p[1] as int]).toList(),
                      cellSize: _cellSize,
                      gap: _gap,
                      color: (fw['isSpangram'] == true ? widget.theme.present : widget.theme.correct).withAlpha(160),
                    ),
                  ),
                // Draw active drag path line
                if (_currentPath.length >= 2)
                  CustomPaint(
                    size: Size(gridWidth, gridHeight),
                    painter: _PathPainter(path: _currentPath, cellSize: _cellSize, gap: _gap, color: widget.theme.correct.withAlpha(100)),
                  ),
                // Cells
                for (int r = 0; r < _rows; r++)
                  for (int c = 0; c < _cols; c++)
                    Positioned(
                      left: c * step,
                      top: r * step,
                      child: _buildCell(r, c, pathSet),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCell(int r, int c, Set<String> pathSet) {
    final key = '$r:$c';
    final letter = widget.grid[r][c];
    final inPath = pathSet.contains(key);
    final isTheme = widget.foundThemeCells.contains(key);
    final isSpangram = widget.foundSpangramCells.contains(key);
    final isHint = widget.hintCells.contains(key);

    Color bg;
    Color textColor = widget.theme.textColor;
    if (isSpangram) { bg = widget.theme.present; textColor = Colors.white; }
    else if (isTheme) { bg = widget.theme.correct; textColor = Colors.white; }
    else if (inPath) { bg = widget.theme.correct.withAlpha(140); }
    else if (isHint) { bg = widget.theme.present.withAlpha(80); }
    else { bg = widget.theme.tileEmpty; }

    return Container(
      width: _cellSize, height: _cellSize,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: inPath ? widget.theme.correct : widget.theme.absent.withAlpha(80), width: inPath ? 2.5 : 1),
      ),
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class _PathPainter extends CustomPainter {
  final List<List<int>> path;
  final double cellSize;
  final double gap;
  final Color color;

  _PathPainter({required this.path, required this.cellSize, required this.gap, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final step = cellSize + gap;
    final paint = Paint()..color = color..strokeWidth = cellSize * 0.3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final p = Path();
    for (int i = 0; i < path.length; i++) {
      final x = path[i][1] * step + cellSize / 2;
      final y = path[i][0] * step + cellSize / 2;
      if (i == 0) p.moveTo(x, y); else p.lineTo(x, y);
    }
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) => true;
}
