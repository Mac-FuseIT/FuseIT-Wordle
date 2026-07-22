/// Error thrown during DSL parsing or execution.
class DslError implements Exception {
  final String message;
  final int? line;

  DslError(this.message, [this.line]);

  @override
  String toString() => line != null ? 'Line $line: $message' : message;
}
