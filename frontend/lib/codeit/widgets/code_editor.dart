import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A code editor with basic Python-like syntax highlighting.
///
/// Wraps an external [TextEditingController] (owned by the parent) and keeps
/// an internal [_HighlightController] in sync.  The parent continues to read
/// and write `controller.text` for `_run()` / `_saveCode()` as before —
/// bidirectional sync ensures both controllers always hold the same text.
///
/// Highlighting categories (VS Code-style dark theme):
/// - Keywords (for, in, range, if, else): purple/pink
/// - Built-in DSL functions (set_pixel, fill): yellow
/// - String literals ('…'): orange
/// - Numeric literals: green
/// - Comments (# …): grey-green
/// - Everything else: light grey
class CodeEditor extends StatefulWidget {
  final TextEditingController controller;

  /// When false the field is read-only (e.g. after puzzle is solved).
  final bool enabled;

  const CodeEditor({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late _HighlightController _highlightController;

  @override
  void initState() {
    super.initState();
    _highlightController = _HighlightController(text: widget.controller.text);
    // Bidirectional sync so the parent controller always has the latest text.
    widget.controller.addListener(_syncFromExternal);
    _highlightController.addListener(_syncToExternal);
  }

  /// Parent wrote to its controller → propagate into the highlight controller.
  void _syncFromExternal() {
    if (_highlightController.text != widget.controller.text) {
      _highlightController.text = widget.controller.text;
    }
  }

  /// User typed in the editor → propagate back to the parent controller.
  void _syncToExternal() {
    if (widget.controller.text != _highlightController.text) {
      widget.controller.text = _highlightController.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromExternal);
    _highlightController.removeListener(_syncToExternal);
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      // Use Focus (not KeyboardListener) so we can return KeyEventResult and
      // prevent the Tab key from escaping the widget tree.
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            final ctrl = _highlightController;
            final sel = ctrl.selection;
            if (sel.isValid) {
              final newText = ctrl.text.replaceRange(sel.start, sel.end, '    ');
              ctrl.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: sel.start + 4),
              );
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _highlightController,
          enabled: widget.enabled,
          maxLines: null,
          minLines: 8,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: const TextStyle(
            fontFamily: 'Courier New',
            fontSize: 13,
            color: Color(0xFFD4D4D4),
            height: 1.5,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(12),
            border: InputBorder.none,
            hintText:
                '# Write your code here...\n'
                'for x in range(5):\n'
                "    for y in range(5):\n"
                "        set_pixel(x, y, 'red')",
            hintStyle: const TextStyle(
              color: Color(0xFF555555),
              fontSize: 13,
              fontFamily: 'Courier New',
              height: 1.5,
            ),
            disabledBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Syntax-highlighting controller
// ---------------------------------------------------------------------------

/// A [TextEditingController] that renders the editor text as coloured
/// [TextSpan] children, providing basic Python-style syntax highlighting.
class _HighlightController extends TextEditingController {
  _HighlightController({super.text});

  // DSL keyword set — drives purple/pink highlighting.
  static const _keywords = {'for', 'in', 'range', 'if', 'else'};

  // DSL built-in function set — drives yellow highlighting.
  static const _builtins = {'set_pixel', 'fill'};

  static const _keywordStyle = TextStyle(color: Color(0xFFC586C0)); // purple/pink
  static const _builtinStyle = TextStyle(color: Color(0xFFDCDCAA)); // yellow
  static const _stringStyle  = TextStyle(color: Color(0xFFCE9178)); // orange
  static const _numberStyle  = TextStyle(color: Color(0xFFB5CEA8)); // green
  static const _commentStyle = TextStyle(color: Color(0xFF6A9955)); // grey-green
  static const _defaultStyle = TextStyle(color: Color(0xFFD4D4D4)); // light grey

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <TextSpan>[];
    final src = text;

    int i = 0;
    while (i < src.length) {
      // ---- Comment (# … end-of-line) ----------------------------------------
      if (src[i] == '#') {
        final newline = src.indexOf('\n', i);
        final end = newline == -1 ? src.length : newline;
        spans.add(TextSpan(text: src.substring(i, end), style: _commentStyle));
        i = end;
        continue;
      }

      // ---- String literal ('…') ---------------------------------------------
      if (src[i] == "'") {
        final close = src.indexOf("'", i + 1);
        final end = close == -1 ? src.length : close + 1;
        spans.add(TextSpan(text: src.substring(i, end), style: _stringStyle));
        i = end;
        continue;
      }

      // ---- Numeric literal ---------------------------------------------------
      if (_isDigit(src[i])) {
        final start = i;
        while (i < src.length && _isDigit(src[i])) {
          i++;
        }
        spans.add(TextSpan(text: src.substring(start, i), style: _numberStyle));
        continue;
      }

      // ---- Identifier, keyword, or built-in ---------------------------------
      if (_isAlpha(src[i])) {
        final start = i;
        while (i < src.length && _isAlphaNum(src[i])) {
          i++;
        }
        final word = src.substring(start, i);
        if (_keywords.contains(word)) {
          spans.add(TextSpan(text: word, style: _keywordStyle));
        } else if (_builtins.contains(word)) {
          spans.add(TextSpan(text: word, style: _builtinStyle));
        } else {
          spans.add(TextSpan(text: word, style: _defaultStyle));
        }
        continue;
      }

      // ---- Operators, whitespace, punctuation --------------------------------
      spans.add(TextSpan(text: src[i], style: _defaultStyle));
      i++;
    }

    return TextSpan(style: style, children: spans);
  }

  // ---------------------------------------------------------------------------
  // Character-class helpers
  // ---------------------------------------------------------------------------

  bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57; // '0'–'9'
  }

  bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // 'A'–'Z'
        (code >= 97 && code <= 122) || // 'a'–'z'
        c == '_';
  }

  bool _isAlphaNum(String c) => _isDigit(c) || _isAlpha(c);
}
