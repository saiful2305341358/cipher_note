import 'dart:math';

import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/features/encryption/domain/hill_cipher.dart';
import 'package:cipher_note/features/encryption/domain/hill_key_matrix.dart';
import 'package:cipher_note/features/encryption/domain/key_generator.dart';
import 'package:cipher_note/features/encryption/domain/modular_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// Several fixed valid keys, plus random ones, so tests never rely on one
/// hand-picked matrix.
final List<HillKeyMatrix> _keys = [
  HillKeyMatrix(3, 5, 7, 2), // det -29 ≡ 227
  HillKeyMatrix(1, 1, 0, 1), // det 1
  HillKeyMatrix(255, 254, 1, 1), // det 1
  HillKeyMatrix(17, 200, 33, 91), // det -5053 ≡ 67
  HillKeyMatrix(0, 1, 1, 0), // det -1 ≡ 255 (swap)
  for (var i = 0; i < 20; i++) KeyGenerator(Random(i)).generate(),
];

void main() {
  group('ModularMath', () {
    test('gcd', () {
      expect(ModularMath.gcd(0, 256), 256);
      expect(ModularMath.gcd(12, 18), 6);
      expect(ModularMath.gcd(-12, 18), 6);
      expect(ModularMath.gcd(227, 256), 1);
      expect(ModularMath.gcd(128, 256), 128);
    });

    test('extended Euclid satisfies Bézout identity', () {
      for (final (a, b) in [(240, 46), (227, 256), (7, 3), (0, 5), (256, 1)]) {
        final (g, x, y) = ModularMath.extendedGcd(a, b);
        expect(g, ModularMath.gcd(a, b));
        expect(a * x + b * y, g);
      }
    });

    test('mod is always non-negative', () {
      expect(ModularMath.mod(-1, 256), 255);
      expect(ModularMath.mod(-512, 256), 0);
      expect(ModularMath.mod(513, 256), 1);
    });

    test('every odd number has an inverse mod 256; even numbers do not', () {
      for (var a = 0; a < 256; a++) {
        if (a.isOdd) {
          final inv = ModularMath.modInverse(a, 256);
          expect((a * inv) % 256, 1, reason: 'a=$a');
          expect(inv, inInclusiveRange(0, 255));
        } else {
          expect(() => ModularMath.modInverse(a, 256), throwsArgumentError);
        }
      }
      expect(
        ModularMath.modInverse(-29, 256),
        ModularMath.modInverse(227, 256),
      );
    });
  });

  group('HillKeyMatrix', () {
    test('determinant modulo 256', () {
      expect(HillKeyMatrix.determinantOf(3, 5, 7, 2), -29);
      expect(HillKeyMatrix(3, 5, 7, 2).determinant, 227);
      expect(HillKeyMatrix(17, 200, 33, 91).determinant, 67);
    });

    test('rejects values outside 0–255', () {
      expect(
        () => HillKeyMatrix(256, 1, 0, 1),
        throwsA(isA<InvalidKeyException>()),
      );
      expect(
        () => HillKeyMatrix(-1, 1, 0, 1),
        throwsA(isA<InvalidKeyException>()),
      );
      expect(
        () => HillKeyMatrix.fromList([1, 2, 3]),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('rejects matrices whose determinant is even (not invertible)', () {
      expect(HillKeyMatrix.isValid(2, 4, 6, 8), isFalse); // det -8
      expect(HillKeyMatrix.isValid(1, 2, 2, 4), isFalse); // det 0
      expect(HillKeyMatrix.isValid(2, 0, 0, 1), isFalse); // det 2
      expect(
        () => HillKeyMatrix(1, 2, 2, 4),
        throwsA(isA<InvalidKeyException>()),
      );
      expect(HillKeyMatrix.isValid(3, 5, 7, 2), isTrue);
    });

    test('accepts exactly the matrices with odd determinant (exhaustive '
        'over a sample grid)', () {
      for (var a = 0; a < 256; a += 17) {
        for (var b = 0; b < 256; b += 23) {
          for (var c = 0; c < 256; c += 29) {
            for (var d = 0; d < 256; d += 31) {
              final det = ModularMath.mod(a * d - b * c, 256);
              expect(HillKeyMatrix.isValid(a, b, c, d), det.isOdd);
            }
          }
        }
      }
    });

    test('K × K⁻¹ is the identity mod 256 for every test key', () {
      for (final k in _keys) {
        final inv = k.inverse();
        expect((k.a * inv.a + k.b * inv.c) % 256, 1);
        expect((k.a * inv.b + k.b * inv.d) % 256, 0);
        expect((k.c * inv.a + k.d * inv.c) % 256, 0);
        expect((k.c * inv.b + k.d * inv.d) % 256, 1);
        expect(inv.inverse(), k);
      }
    });

    test('toString never reveals key values', () {
      expect(HillKeyMatrix(3, 5, 7, 2).toString(), isNot(contains('3')));
    });
  });

  group('Byte-pair encryption', () {
    test('C = K·P mod 256 (worked example)', () {
      // K = [3 5; 7 2], P = ('H', 'i') = (72, 105)
      // c1 = 3·72 + 5·105 = 741 ≡ 229, c2 = 7·72 + 2·105 = 714 ≡ 202
      final out = HillCipher.transformPairs([
        72,
        105,
      ], HillKeyMatrix(3, 5, 7, 2));
      expect(out, [229, 202]);
    });

    test('results stay within 0–255 at the edges', () {
      final out = HillCipher.transformPairs([
        255,
        255,
        0,
        0,
        255,
        0,
      ], HillKeyMatrix(255, 254, 1, 1));
      expect(out.every((b) => b >= 0 && b <= 255), isTrue);
      // 255·255 + 254·255 = 129795 ≡ 3; 255 + 255 = 510 ≡ 254
      expect(out.sublist(0, 2), [3, 254]);
    });

    test('decryption inverts encryption for random data and every key', () {
      final random = Random(42);
      const cipher = HillCipher();
      for (final k in _keys) {
        final inv = k.inverse();
        for (var length = 0; length < 40; length++) {
          final plain = List.generate(length, (_) => random.nextInt(256));
          final encrypted = cipher.encryptBytes(plain, k);
          expect(encrypted.length, length + (length.isEven ? 2 : 1));
          expect(cipher.decryptBytes(encrypted, inv), plain);
        }
      }
    });
  });

  group('Padding', () {
    test('always pads to a multiple of two', () {
      expect(HillCipher.pad([]), [2, 2]);
      expect(HillCipher.pad([9]), [9, 1]);
      expect(HillCipher.pad([9, 8]), [9, 8, 2, 2]);
      expect(HillCipher.pad([9, 8, 7]), [9, 8, 7, 1]);
    });

    test('unpad removes valid padding', () {
      expect(HillCipher.unpad([2, 2]), isEmpty);
      expect(HillCipher.unpad([9, 1]), [9]);
      expect(HillCipher.unpad([9, 8, 2, 2]), [9, 8]);
    });

    test('unpad rejects invalid padding instead of ignoring it', () {
      for (final bad in [
        <int>[],
        [1],
        [9, 0],
        [9, 3],
        [5, 2],
        [9, 255],
      ]) {
        expect(
          () => HillCipher.unpad(bad),
          throwsA(isA<DecryptionFailedException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('Hex encoding', () {
    test('two uppercase characters per byte', () {
      expect(HillCipher.toHex([0, 15, 16, 171, 255]), '000F10ABFF');
      expect(HillCipher.fromHex('000F10ABFF'), [0, 15, 16, 171, 255]);
    });

    test('rejects odd length, lowercase and non-hex characters', () {
      for (final bad in ['ABC', 'ab', '0G', 'Z1', ' 1']) {
        expect(
          () => HillCipher.fromHex(bad),
          throwsA(isA<CiphertextFormatException>()),
          reason: bad,
        );
      }
    });

    test('rejects ciphertext with an impossible length', () {
      final inv = HillKeyMatrix(3, 5, 7, 2).inverse();
      expect(
        () => const HillCipher().decryptBytes([1, 2, 3], inv),
        throwsA(isA<CiphertextFormatException>()),
      );
      expect(
        () => const HillCipher().decryptBytes([], inv),
        throwsA(isA<CiphertextFormatException>()),
      );
    });
  });

  group('KeyGenerator', () {
    test('only produces valid, mixing keys', () {
      final generator = KeyGenerator();
      for (var i = 0; i < 500; i++) {
        final k = generator.generate();
        expect(HillKeyMatrix.isValid(k.a, k.b, k.c, k.d), isTrue);
        expect(k.b, isNot(0));
        expect(k.c, isNot(0));
      }
    });

    test('skips invalid candidates until a valid one appears', () {
      // Candidates: identity-like and even-determinant ones first.
      final random = _ScriptedRandom([
        1, 0, 0, 1, // identity: rejected (b = c = 0)
        2, 4, 6, 8, // det -8: rejected
        3, 5, 7, 2, // valid
      ]);
      final k = KeyGenerator(random).generate();
      expect(k, HillKeyMatrix(3, 5, 7, 2));
      expect(random.calls, 12);
    });

    test('random keys differ from each other', () {
      final generator = KeyGenerator();
      final keys = {for (var i = 0; i < 200; i++) generator.generate()};
      expect(keys.length, greaterThan(190));
    });
  });
}

class _ScriptedRandom implements Random {
  _ScriptedRandom(this.values);

  final List<int> values;
  int calls = 0;

  @override
  int nextInt(int max) => values[calls++];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
