import 'dart:typed_data';

import '../../../core/errors/app_exceptions.dart';
import 'hill_key_matrix.dart';

/// Byte-oriented 2×2 Hill Cipher (modulo 256), with PKCS#7-style padding
/// to 2-byte blocks and uppercase hexadecimal encoding.
///
/// This is a classical, educational cipher. It is linear, has a tiny key
/// space and provides no integrity check. It is not secure encryption.
class HillCipher {
  const HillCipher();

  static const int blockSize = 2;
  static const int _mod = HillKeyMatrix.modulus;

  /// Pads to a multiple of 2 bytes. Padding is always added: one `0x01`
  /// byte for odd lengths, `0x02 0x02` for even lengths (including empty).
  static Uint8List pad(List<int> bytes) {
    final padLength = blockSize - (bytes.length % blockSize);
    return Uint8List.fromList([
      ...bytes,
      for (var i = 0; i < padLength; i++) padLength,
    ]);
  }

  /// Removes and validates padding added by [pad].
  static Uint8List unpad(List<int> bytes) {
    if (bytes.isEmpty || bytes.length % blockSize != 0) {
      throw const DecryptionFailedException('The encrypted data is damaged.');
    }
    final padLength = bytes.last;
    if (padLength < 1 || padLength > blockSize) {
      throw const DecryptionFailedException(
        'The note could not be decrypted (invalid padding).',
      );
    }
    for (var i = bytes.length - padLength; i < bytes.length; i++) {
      if (bytes[i] != padLength) {
        throw const DecryptionFailedException(
          'The note could not be decrypted (invalid padding).',
        );
      }
    }
    return Uint8List.fromList(bytes.sublist(0, bytes.length - padLength));
  }

  /// Multiplies each byte pair by [key]: `C = K·P mod 256`.
  static Uint8List transformPairs(List<int> bytes, HillKeyMatrix key) {
    if (bytes.length % blockSize != 0) {
      throw ArgumentError('Byte length must be a multiple of $blockSize');
    }
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i += 2) {
      final p1 = bytes[i], p2 = bytes[i + 1];
      out[i] = (key.a * p1 + key.b * p2) % _mod;
      out[i + 1] = (key.c * p1 + key.d * p2) % _mod;
    }
    return out;
  }

  /// Pads and encrypts [plain].
  Uint8List encryptBytes(List<int> plain, HillKeyMatrix key) =>
      transformPairs(pad(plain), key);

  /// Decrypts with the already-inverted key [inverseKey] and removes
  /// padding. Pass `key.inverse()`; computing it once per text avoids
  /// repeating the work for every word.
  Uint8List decryptBytes(List<int> cipher, HillKeyMatrix inverseKey) {
    if (cipher.isEmpty || cipher.length % blockSize != 0) {
      throw const CiphertextFormatException(
        'The encrypted data has an unexpected length.',
      );
    }
    return unpad(transformPairs(cipher, inverseKey));
  }

  static const _hex = '0123456789ABCDEF';

  /// Two uppercase hexadecimal characters per byte.
  static String toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer
        ..write(_hex[b >> 4])
        ..write(_hex[b & 0x0F]);
    }
    return buffer.toString();
  }

  /// Parses text produced by [toHex]. Only `0-9` and `A-F` are accepted.
  static Uint8List fromHex(String text) {
    if (text.length.isOdd) {
      throw const CiphertextFormatException(
        'The encrypted data is not in the expected format.',
      );
    }
    final out = Uint8List(text.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final hi = _hex.indexOf(text[i * 2]);
      final lo = _hex.indexOf(text[i * 2 + 1]);
      if (hi < 0 || lo < 0) {
        throw const CiphertextFormatException(
          'The encrypted data is not in the expected format.',
        );
      }
      out[i] = (hi << 4) | lo;
    }
    return out;
  }
}
