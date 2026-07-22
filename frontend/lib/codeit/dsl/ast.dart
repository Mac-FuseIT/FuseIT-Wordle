/// Base class for AST nodes.
abstract class AstNode {}

/// Root node containing a list of statements.
class ProgramNode extends AstNode {
  final List<AstNode> statements;
  ProgramNode(this.statements);
}

/// For loop: `for VAR in range(EXPR):`
class ForNode extends AstNode {
  final String variable;
  final AstNode rangeExpr;
  final List<AstNode> body;
  final int line;
  ForNode(this.variable, this.rangeExpr, this.body, this.line);
}

/// If statement with optional else block.
class IfNode extends AstNode {
  final Condition condition;
  final List<AstNode> thenBody;
  final List<AstNode>? elseBody;
  final int line;
  IfNode(this.condition, this.thenBody, this.elseBody, this.line);
}

/// Function call: `set_pixel(x, y, 'color')` or `fill('color')`
class FuncCallNode extends AstNode {
  final String name;
  final List<AstNode> args;
  final int line;
  FuncCallNode(this.name, this.args, this.line);
}

/// Number literal: `5`, `0`, `42`
class NumberLiteral extends AstNode {
  final int value;
  NumberLiteral(this.value);
}

/// String literal: `'red'`, `'blue'`
class StringLiteral extends AstNode {
  final String value;
  StringLiteral(this.value);
}

/// Variable reference: `x`, `y`
class VariableRef extends AstNode {
  final String name;
  VariableRef(this.name);
}

/// Binary expression: `x + 1`, `y - 2`, `x % 2`
class BinaryExpr extends AstNode {
  final AstNode left;
  final String op; // '%', '+', '-'
  final AstNode right;
  BinaryExpr(this.left, this.op, this.right);
}

/// Condition in if statements: `x == 2`, `y != 0`, `x % 2 == 0`
class Condition {
  final AstNode left;
  final String op; // '==', '!=', '>', '<', '>=', '<='
  final AstNode right;
  Condition(this.left, this.op, this.right);
}
