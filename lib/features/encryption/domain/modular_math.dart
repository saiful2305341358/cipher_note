/// Integer helpers for modular arithmetic. Pure Dart, no Flutter.
class ModularMath {
  ModularMath._();

  /// Greatest common divisor (Euclid). Result is always >= 0.
  static int gcd(int a, int b) {
    a = a.abs();
    b = b.abs();
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    return a;
  }

  /// Extended Euclidean algorithm. Returns `(g, x, y)` with
  /// `a*x + b*y == g == gcd(a, b)`.
  static (int, int, int) extendedGcd(int a, int b) {
    var oldR = a, r = b;
    var oldS = 1, s = 0;
    var oldT = 0, t = 1;
    while (r != 0) {
      final q = oldR ~/ r;
      (oldR, r) = (r, oldR - q * r);
      (oldS, s) = (s, oldS - q * s);
      (oldT, t) = (t, oldT - q * t);
    }
    return (oldR, oldS, oldT);
  }

  /// Non-negative remainder of [value] modulo [modulus].
  static int mod(int value, int modulus) => value % modulus;

  /// Multiplicative inverse of [a] modulo [modulus], computed with
  /// [extendedGcd].
  ///
  /// Throws [ArgumentError] if no inverse exists (gcd != 1).
  static int modInverse(int a, int modulus) {
    if (modulus < 2) throw ArgumentError.value(modulus, 'modulus');
    final (g, x, _) = extendedGcd(mod(a, modulus), modulus);
    if (g != 1) {
      throw ArgumentError.value(a, 'a', 'has no inverse modulo $modulus');
    }
    return mod(x, modulus);
  }
}
