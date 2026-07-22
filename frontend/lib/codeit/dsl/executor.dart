import 'ast.dart';
import 'errors.dart';

/// Result of executing DSL code against a 5x5 grid.
class ExecutionResult {
  final List<List<String>> grid; // 5x5, each cell is a color string
  final String? error;
  final int steps;

  ExecutionResult({required this.grid, this.error, required this.steps});
}

/// Executes a parsed program on a 5x5 grid.
class DslExecutor {
  int _steps = 0;
  static const maxSteps = 10000;
  final Map<String, int> _vars = {};
  late List<List<String>> _grid;

  static const validColors = [
    'black', 'red', 'blue', 'yellow', 'green', 'white', 'purple', 'orange'
  ];

  ExecutionResult execute(ProgramNode program) {
    _grid = List.generate(5, (_) => List.generate(5, (_) => 'black'));
    _steps = 0;
    _vars.clear();
    try {
      _execBlock(program.statements);
      return ExecutionResult(grid: _grid, error: null, steps: _steps);
    } on DslError catch (e) {
      return ExecutionResult(grid: _grid, error: e.toString(), steps: _steps);
    }
  }

  void _execBlock(List<AstNode> stmts) {
    for (final stmt in stmts) {
      _steps++;
      if (_steps > maxSteps) {
        throw DslError('Execution limit reached (too many steps)');
      }
      _execStmt(stmt);
    }
  }

  void _execStmt(AstNode node) {
    if (node is ForNode) {
      final n = _evalExpr(node.rangeExpr);
      if (n < 0) return; // range(negative) = no iterations
      for (int i = 0; i < n; i++) {
        _vars[node.variable] = i;
        _execBlock(node.body);
      }
      _vars.remove(node.variable);
    } else if (node is IfNode) {
      if (_evalCondition(node.condition)) {
        _execBlock(node.thenBody);
      } else if (node.elseBody != null) {
        _execBlock(node.elseBody!);
      }
    } else if (node is FuncCallNode) {
      _execFunc(node);
    }
  }

  void _execFunc(FuncCallNode node) {
    switch (node.name) {
      case 'set_pixel':
        if (node.args.length != 3) {
          throw DslError('set_pixel takes 3 arguments (x, y, color)', node.line);
        }
        final x = _evalExpr(node.args[0]);
        final y = _evalExpr(node.args[1]);
        final color = _evalString(node.args[2]);
        if (x < 0 || x > 4) throw DslError('Index out of range: x=$x is outside 0-4', node.line);
        if (y < 0 || y > 4) throw DslError('Index out of range: y=$y is outside 0-4', node.line);
        if (!validColors.contains(color)) {
          throw DslError("Unknown color '$color'. Available: ${validColors.join(', ')}", node.line);
        }
        _grid[x][y] = color;
      case 'fill':
        if (node.args.length != 1) {
          throw DslError('fill takes 1 argument (color)', node.line);
        }
        final color = _evalString(node.args[0]);
        if (!validColors.contains(color)) {
          throw DslError("Unknown color '$color'. Available: ${validColors.join(', ')}", node.line);
        }
        for (int i = 0; i < 5; i++) {
          for (int j = 0; j < 5; j++) {
            _grid[i][j] = color;
          }
        }
      default:
        // Friendly suggestions for typos
        String suggestion = '';
        if (node.name.toLowerCase().contains('pixel') || node.name.toLowerCase().contains('set')) {
          suggestion = " Did you mean 'set_pixel'?";
        } else if (node.name.toLowerCase().contains('fill')) {
          suggestion = " Did you mean 'fill'?";
        }
        throw DslError("Unknown function '${node.name}'.$suggestion", node.line);
    }
  }

  int _evalExpr(AstNode node) {
    if (node is NumberLiteral) return node.value;
    if (node is VariableRef) {
      if (!_vars.containsKey(node.name)) {
        throw DslError("Undefined variable '${node.name}'");
      }
      return _vars[node.name]!;
    }
    if (node is BinaryExpr) {
      final left = _evalExpr(node.left);
      final right = _evalExpr(node.right);
      switch (node.op) {
        case '%': return right == 0 ? 0 : left % right;
        case '+': return left + right;
        case '-': return left - right;
        default: throw DslError("Unknown operator '${node.op}'");
      }
    }
    throw DslError('Expected numeric expression');
  }

  String _evalString(AstNode node) {
    if (node is StringLiteral) return node.value;
    throw DslError('Expected string for color argument');
  }

  bool _evalCondition(Condition cond) {
    final left = _evalExpr(cond.left);
    final right = _evalExpr(cond.right);
    switch (cond.op) {
      case '==': return left == right;
      case '!=': return left != right;
      case '>': return left > right;
      case '<': return left < right;
      case '>=': return left >= right;
      case '<=': return left <= right;
      default: throw DslError("Unknown operator '${cond.op}'");
    }
  }
}
