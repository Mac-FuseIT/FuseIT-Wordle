import 'ast.dart';
import 'errors.dart';
import 'tokenizer.dart';

/// Parses a list of [Token]s produced by [tokenize] into a [ProgramNode] AST.
///
/// Throws [DslError] on the first syntax error encountered.
ProgramNode parse(List<Token> tokens) {
  final parser = _Parser(tokens);
  return parser.parseProgram();
}

// ---------------------------------------------------------------------------
// Internal parser implementation
// ---------------------------------------------------------------------------

class _Parser {
  final List<Token> _tokens;
  int _pos = 0;
  int _nestingDepth = 0;

  static const _maxNesting = 3;

  _Parser(this._tokens);

  // ─── Token navigation ───────────────────────────────────────────────────

  /// The token at the current position.
  Token get _current => _tokens[_pos];

  /// Advances past the current token and returns it.
  /// Stops advancing once the last token (always EOF) is reached.
  Token _advance() {
    final t = _tokens[_pos];
    if (_pos < _tokens.length - 1) _pos++;
    return t;
  }

  /// Asserts that the current token has the expected [type], advances, and
  /// returns the consumed token.  Throws [DslError] on mismatch.
  Token _expect(TokenType type, String message) {
    if (_current.type != type) {
      throw DslError(message, _current.line);
    }
    return _advance();
  }

  /// Skips any consecutive NEWLINE tokens.
  void _skipNewlines() {
    while (_current.type == TokenType.newline) {
      _advance();
    }
  }

  // ─── Program ────────────────────────────────────────────────────────────

  /// Entry point: parses a complete program.
  ProgramNode parseProgram() {
    _skipNewlines();
    final stmts = <AstNode>[];
    while (_current.type != TokenType.eof) {
      stmts.add(_parseStatement());
      _skipNewlines();
    }
    return ProgramNode(stmts);
  }

  // ─── Statement ──────────────────────────────────────────────────────────

  /// Dispatches to the appropriate statement parser.
  AstNode _parseStatement() {
    switch (_current.type) {
      case TokenType.forKeyword:
        return _parseFor();
      case TokenType.ifKeyword:
        return _parseIf();
      case TokenType.identifier:
        return _parseFuncCall();
      default:
        throw DslError(
          "Unexpected token '${_current.value}'",
          _current.line,
        );
    }
  }

  // ─── For loop ───────────────────────────────────────────────────────────

  /// Parses: `for IDENT in range ( expr ) : NEWLINE INDENT block DEDENT`
  ForNode _parseFor() {
    final line = _current.line;
    _advance(); // consume 'for'

    final varName =
        _expect(TokenType.identifier, "Expected variable name after 'for'")
            .value;
    _expect(TokenType.inKeyword, "Expected 'in' after variable name");
    _expect(TokenType.rangeKeyword, "Expected 'range' after 'in'");
    _expect(TokenType.lparen, "Expected '(' after 'range'");
    final rangeExpr = _parseExpr();
    _expect(TokenType.rparen, "Expected ')' after range expression");
    _expect(TokenType.colon, "Expected ':' after range expression");
    _skipNewlines();

    // Guard nesting depth *before* parsing the body so the error line points
    // at the `for` keyword, not somewhere inside the nested body.
    _nestingDepth++;
    if (_nestingDepth > _maxNesting) {
      throw DslError('Too many nested loops (max $_maxNesting)', line);
    }
    final body = _parseBlock();
    _nestingDepth--;

    return ForNode(varName, rangeExpr, body, line);
  }

  // ─── If statement ───────────────────────────────────────────────────────

  /// Parses: `if condition : NEWLINE INDENT block DEDENT [ else : NEWLINE INDENT block DEDENT ]`
  IfNode _parseIf() {
    final line = _current.line;
    _advance(); // consume 'if'

    final condition = _parseCondition();
    _expect(TokenType.colon, "Expected ':' after condition");
    _skipNewlines();

    final thenBody = _parseBlock();

    List<AstNode>? elseBody;
    _skipNewlines();
    if (_current.type == TokenType.elseKeyword) {
      _advance(); // consume 'else'
      _expect(TokenType.colon, "Expected ':' after 'else'");
      _skipNewlines();
      elseBody = _parseBlock();
    }

    return IfNode(condition, thenBody, elseBody, line);
  }

  // ─── Function call ──────────────────────────────────────────────────────

  /// Parses: `IDENT ( [ expr ( , expr )* ] )`
  FuncCallNode _parseFuncCall() {
    final line = _current.line;
    final name = _advance().value; // consume function name

    _expect(TokenType.lparen, "Expected '(' after function name '$name'");

    final args = <AstNode>[];
    if (_current.type != TokenType.rparen) {
      args.add(_parseExpr());
      while (_current.type == TokenType.comma) {
        _advance(); // consume ','
        args.add(_parseExpr());
      }
    }

    _expect(TokenType.rparen, "Expected ')' after arguments");
    return FuncCallNode(name, args, line);
  }

  // ─── Block (indented body) ──────────────────────────────────────────────

  /// Parses an INDENT-wrapped sequence of statements followed by a DEDENT.
  List<AstNode> _parseBlock() {
    _expect(TokenType.indent, 'Expected indented block');
    final stmts = <AstNode>[];
    while (_current.type != TokenType.dedent &&
        _current.type != TokenType.eof) {
      stmts.add(_parseStatement());
      _skipNewlines();
    }
    if (_current.type == TokenType.dedent) _advance(); // consume DEDENT
    return stmts;
  }

  // ─── Condition ──────────────────────────────────────────────────────────

  /// Parses: `expr COMP_OP expr`
  ///
  /// COMP_OP is one of `==`, `!=`, `>`, `<`, `>=`, `<=`.
  Condition _parseCondition() {
    final left = _parseExpr();

    final op = _current;
    if (op.type == TokenType.equals ||
        op.type == TokenType.notEquals ||
        op.type == TokenType.greaterThan ||
        op.type == TokenType.lessThan ||
        op.type == TokenType.greaterEqual ||
        op.type == TokenType.lessEqual) {
      _advance(); // consume operator
      final right = _parseExpr();
      return Condition(left, op.value, right);
    }

    throw DslError(
      "Expected comparison operator ('==', '!=', '>', '<', '>=', '<=')",
      _current.line,
    );
  }

  // ─── Expression ─────────────────────────────────────────────────────────

  /// Parses: `primary ( ( '%' | '+' | '-' ) primary )*`
  ///
  /// All binary operators have equal precedence and are left-associative.
  AstNode _parseExpr() {
    var left = _parsePrimary();
    while (_current.type == TokenType.percent ||
        _current.type == TokenType.plus ||
        _current.type == TokenType.minus) {
      final op = _advance().value; // consume operator
      final right = _parsePrimary();
      left = BinaryExpr(left, op, right);
    }
    return left;
  }

  // ─── Primary ────────────────────────────────────────────────────────────

  /// Parses a number literal, string literal, or variable reference.
  AstNode _parsePrimary() {
    switch (_current.type) {
      case TokenType.number:
        return NumberLiteral(int.parse(_advance().value));
      case TokenType.string:
        return StringLiteral(_advance().value);
      case TokenType.identifier:
        return VariableRef(_advance().value);
      default:
        throw DslError(
          "Unexpected token '${_current.value}'",
          _current.line,
        );
    }
  }
}
