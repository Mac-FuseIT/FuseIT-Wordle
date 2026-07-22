import 'errors.dart';

/// All token types produced by the DSL tokenizer.
enum TokenType {
  forKeyword,
  inKeyword,
  rangeKeyword,
  ifKeyword,
  elseKeyword,
  andKeyword,
  orKeyword,
  identifier,
  number,
  string,
  colon,
  comma,
  lparen,
  rparen,
  percent,
  plus,
  minus,
  equals,
  notEquals,
  greaterThan,
  lessThan,
  greaterEqual,
  lessEqual,
  newline,
  indent,
  dedent,
  eof,
}

/// A single token produced by [tokenize].
class Token {
  final TokenType type;
  final String value;
  final int line;

  const Token(this.type, this.value, this.line);

  @override
  String toString() => 'Token($type, ${value.isNotEmpty ? value : "—"}, line=$line)';
}

/// Tokenizes [source] into a list of [Token]s.
///
/// Processing steps:
/// 1. Split into lines, normalize tabs → 4 spaces, strip trailing whitespace.
/// 2. Skip blank lines.
/// 3. Track indentation with a stack; emit [TokenType.indent] / [TokenType.dedent].
/// 4. Tokenize each non-blank line left-to-right.
/// 5. Emit [TokenType.eof] at the end.
List<Token> tokenize(String source) {
  final tokens = <Token>[];
  final lines = source.split('\n');
  // Stack of indent levels; starts at column 0.
  final indentStack = <int>[0];

  for (int lineNum = 0; lineNum < lines.length; lineNum++) {
    // Normalize tabs to 4 spaces, then strip trailing whitespace.
    final normalized = lines[lineNum].replaceAll('\t', '    ').trimRight();
    if (normalized.isEmpty) continue; // skip blank lines

    final indent = _leadingSpaces(normalized);
    final content = normalized.substring(indent);
    final ln = lineNum + 1; // 1-indexed for human-readable errors

    // Handle indentation changes relative to the previous indent level.
    if (indent > indentStack.last) {
      indentStack.add(indent);
      tokens.add(Token(TokenType.indent, '', ln));
    } else {
      // Possibly emit one or more DEDENTs.
      while (indent < indentStack.last) {
        indentStack.removeLast();
        tokens.add(Token(TokenType.dedent, '', ln));
      }
      if (indent != indentStack.last) {
        throw DslError('Unexpected indentation', ln);
      }
    }

    _tokenizeLine(content, ln, tokens);
    tokens.add(Token(TokenType.newline, '', ln));
  }

  // Flush any remaining open indent levels.
  final lastLine = lines.length;
  while (indentStack.length > 1) {
    indentStack.removeLast();
    tokens.add(Token(TokenType.dedent, '', lastLine));
  }
  tokens.add(Token(TokenType.eof, '', lastLine));

  return tokens;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Returns the number of leading space characters in [s].
int _leadingSpaces(String s) {
  int i = 0;
  while (i < s.length && s[i] == ' ') {
    i++;
  }
  return i;
}

/// Scans [content] left-to-right and appends tokens to [tokens].
///
/// [content] must already have its leading whitespace stripped.
void _tokenizeLine(String content, int line, List<Token> tokens) {
  int i = 0;

  while (i < content.length) {
    // Skip intra-line whitespace.
    if (content[i] == ' ') {
      i++;
      continue;
    }

    // ── String literal ────────────────────────────────────────────────────
    if (content[i] == "'") {
      final end = content.indexOf("'", i + 1);
      if (end == -1) throw DslError('Unterminated string', line);
      tokens.add(Token(TokenType.string, content.substring(i + 1, end), line));
      i = end + 1;
      continue;
    }

    // ── Number literal ────────────────────────────────────────────────────
    if (_isDigit(content[i])) {
      final start = i;
      while (i < content.length && _isDigit(content[i])) {
        i++;
      }
      tokens.add(Token(TokenType.number, content.substring(start, i), line));
      continue;
    }

    // ── Identifier / keyword ──────────────────────────────────────────────
    if (_isAlpha(content[i])) {
      final start = i;
      while (i < content.length && _isAlphaNum(content[i])) {
        i++;
      }
      final word = content.substring(start, i);
      switch (word) {
        case 'for':
          tokens.add(Token(TokenType.forKeyword, word, line));
        case 'in':
          tokens.add(Token(TokenType.inKeyword, word, line));
        case 'range':
          tokens.add(Token(TokenType.rangeKeyword, word, line));
        case 'if':
          tokens.add(Token(TokenType.ifKeyword, word, line));
        case 'else':
          tokens.add(Token(TokenType.elseKeyword, word, line));
        case 'and':
          tokens.add(Token(TokenType.andKeyword, word, line));
        case 'or':
          tokens.add(Token(TokenType.orKeyword, word, line));
        default:
          tokens.add(Token(TokenType.identifier, word, line));
      }
      continue;
    }

    // ── Two-character operators ───────────────────────────────────────────
    if (i + 1 < content.length) {
      final two = content.substring(i, i + 2);
      switch (two) {
        case '==':
          tokens.add(Token(TokenType.equals, two, line));
          i += 2;
          continue;
        case '!=':
          tokens.add(Token(TokenType.notEquals, two, line));
          i += 2;
          continue;
        case '>=':
          tokens.add(Token(TokenType.greaterEqual, two, line));
          i += 2;
          continue;
        case '<=':
          tokens.add(Token(TokenType.lessEqual, two, line));
          i += 2;
          continue;
      }
    }

    // ── Single-character tokens ───────────────────────────────────────────
    switch (content[i]) {
      case ':':
        tokens.add(Token(TokenType.colon, ':', line));
      case ',':
        tokens.add(Token(TokenType.comma, ',', line));
      case '(':
        tokens.add(Token(TokenType.lparen, '(', line));
      case ')':
        tokens.add(Token(TokenType.rparen, ')', line));
      case '%':
        tokens.add(Token(TokenType.percent, '%', line));
      case '+':
        tokens.add(Token(TokenType.plus, '+', line));
      case '-':
        tokens.add(Token(TokenType.minus, '-', line));
      case '>':
        tokens.add(Token(TokenType.greaterThan, '>', line));
      case '<':
        tokens.add(Token(TokenType.lessThan, '<', line));
      default:
        throw DslError("Unexpected character '${content[i]}'", line);
    }
    i++;
  }
}

// ---------------------------------------------------------------------------
// Character-class predicates
// ---------------------------------------------------------------------------

bool _isDigit(String c) {
  final code = c.codeUnitAt(0);
  return code >= 48 && code <= 57; // '0'..'9'
}

bool _isAlpha(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 65 && code <= 90) || // 'A'..'Z'
      (code >= 97 && code <= 122) || // 'a'..'z'
      c == '_';
}

bool _isAlphaNum(String c) => _isDigit(c) || _isAlpha(c);
