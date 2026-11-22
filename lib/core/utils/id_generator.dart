import 'dart:math';

/// Generates unique, URL-safe record ids such as `n_mi3k2x9a_4f1c0e9b2a7d`.
///
/// The id combines a timestamp with 48 random bits from a secure random
/// source, so ids from different sessions and devices do not collide in
/// practice. No extra package is needed.
class IdGenerator {
  IdGenerator._();

  static final Random _random = Random.secure();

  static String generate([String prefix = 'n']) {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return '${prefix}_${time}_$buffer';
  }
}
