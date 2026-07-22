import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A multi-line monospace code editor for writing DSL programs.
///
/// - Dark VS Code-style background (#1E1E1E)
/// - Courier New / monospace font, 13 px
/// - Tab key intercepted: inserts 4 spaces instead of moving focus
class CodeEditor extends StatelessWidget {
  final TextEditingController controller;

  /// When false the field is read-only (e.g. after puzzle is solved).
  final bool enabled;

  const CodeEditor({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  static const _hintText =
      '# Write your code here...\n'
      'for x in range(5):\n'
      "    for y in range(5):\n"
      "        set_pixel(x, y, 'red')";

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: KeyboardListener(
        // A dedicated FocusNode for the listener so it doesn't steal focus
        // from the inner TextField.
        focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            final text = controller.text;
            final sel = controller.selection;
            // Guard against invalid selection (e.g. before any input).
            if (!sel.isValid) return;
            final start = sel.start;
            final end = sel.end;
            final newText = text.replaceRange(start, end, '    ');
            controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: start + 4),
            );
          }
        },
        child: TextField(
          controller: controller,
          enabled: enabled,
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
            hintText: _hintText,
            hintStyle: TextStyle(
              color: const Color(0xFF555555),
              fontSize: 13,
              fontFamily: 'Courier New',
              height: 1.5,
            ),
            // Tighten disabled opacity so it still looks readable.
            disabledBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
