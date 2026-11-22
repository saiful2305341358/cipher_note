import 'dart:math';

import 'hill_key_matrix.dart';

/// Generates random, valid 2×2 Hill Cipher keys.
///
/// Uses [Random.secure] (the platform's cryptographically secure random
/// source) by default. Candidates are drawn until one is valid. In addition
/// to invertibility, generated keys must mix both bytes of each pair
/// (`b != 0` and `c != 0`), which rules out the identity and other diagonal
/// matrices that would encrypt each byte on its own.
class KeyGenerator {
  KeyGenerator([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  static const int maxAttempts = 10000;

  /// Whether a generated candidate is acceptable.
  static bool isAcceptable(int a, int b, int c, int d) =>
      HillKeyMatrix.isValid(a, b, c, d) && b != 0 && c != 0;

  HillKeyMatrix generate() {
    for (var i = 0; i < maxAttempts; i++) {
      final a = _random.nextInt(256);
      final b = _random.nextInt(256);
      final c = _random.nextInt(256);
      final d = _random.nextInt(256);
      if (isAcceptable(a, b, c, d)) return HillKeyMatrix(a, b, c, d);
    }
    // About 3 in 8 random candidates are acceptable, so this is unreachable
    // in practice with a working random source.
    throw StateError('Could not generate a valid key.');
  }
}
