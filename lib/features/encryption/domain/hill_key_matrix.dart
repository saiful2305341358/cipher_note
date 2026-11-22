import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exceptions.dart';
import 'modular_math.dart';

/// A 2×2 Hill Cipher key over bytes (arithmetic modulo 256):
///
/// ```
/// K = | a  b |
///     | c  d |
/// ```
///
/// A key is valid only when every value is in 0–255 and the determinant is
/// invertible modulo 256, i.e. odd. Instances can only be created valid.
///
/// [toString] never prints the values, so a key cannot leak into logs.
@immutable
class HillKeyMatrix {
  const HillKeyMatrix._(this.a, this.b, this.c, this.d);

  /// Creates a key, throwing [InvalidKeyException] if it is not valid.
  factory HillKeyMatrix(int a, int b, int c, int d) {
    final problem = validationError(a, b, c, d);
    if (problem != null) throw InvalidKeyException(problem);
    return HillKeyMatrix._(a, b, c, d);
  }

  /// Creates a key from `[a, b, c, d]`.
  factory HillKeyMatrix.fromList(List<int> values) {
    if (values.length != 4) {
      throw const InvalidKeyException('A key must have exactly 4 values.');
    }
    return HillKeyMatrix(values[0], values[1], values[2], values[3]);
  }

  static const int modulus = 256;

  final int a;
  final int b;
  final int c;
  final int d;

  List<int> toList() => [a, b, c, d];

  /// Plain determinant `ad - bc` (may be negative).
  static int determinantOf(int a, int b, int c, int d) => a * d - b * c;

  /// Determinant reduced modulo 256 (0–255).
  int get determinant => ModularMath.mod(determinantOf(a, b, c, d), modulus);

  /// Returns `null` when the values form a valid key, otherwise a
  /// description of the problem (without the values themselves).
  static String? validationError(int a, int b, int c, int d) {
    for (final v in [a, b, c, d]) {
      if (v < 0 || v > 255) return 'Key values must be between 0 and 255.';
    }
    final det = ModularMath.mod(determinantOf(a, b, c, d), modulus);
    if (ModularMath.gcd(det, modulus) != 1) {
      return 'The key cannot be reversed: its determinant must be odd.';
    }
    return null;
  }

  static bool isValid(int a, int b, int c, int d) =>
      validationError(a, b, c, d) == null;

  /// The inverse key, used for decryption:
  /// `K⁻¹ = det⁻¹ · | d  -b |  (mod 256)`
  ///              `| -c  a |`
  HillKeyMatrix inverse() {
    final detInv = ModularMath.modInverse(determinant, modulus);
    int m(int v) => ModularMath.mod(v * detInv, modulus);
    return HillKeyMatrix._(m(d), m(-b), m(-c), m(a));
  }

  @override
  bool operator ==(Object other) =>
      other is HillKeyMatrix &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d;

  @override
  int get hashCode => Object.hash(a, b, c, d);

  @override
  String toString() => 'HillKeyMatrix(hidden)';
}
