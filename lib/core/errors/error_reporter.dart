import 'package:flutter/foundation.dart';

/// Central place for reporting technical errors during development.
///
/// Only the error type and message are printed, and only in debug builds.
/// Callers must never pass note content, titles or key material.
class ErrorReporter {
  ErrorReporter._();

  /// Replaceable for tests.
  static void Function(String context, Object error, StackTrace? stack)
  handler = _debugHandler;

  static void report(String context, Object error, [StackTrace? stack]) =>
      handler(context, error, stack);

  static void _debugHandler(String context, Object error, StackTrace? stack) {
    if (!kDebugMode) return;
    debugPrint('[$context] $error');
    if (stack != null) debugPrint(stack.toString());
  }
}
