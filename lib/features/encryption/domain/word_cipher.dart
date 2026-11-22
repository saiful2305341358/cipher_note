import 'dart:convert';

import '../../../core/errors/app_exceptions.dart';
import 'hill_cipher.dart';
import 'hill_key_matrix.dart';
import 'text_tokenizer.dart';

/// Encrypts only the words of a text and keeps every separator (spaces,
/// tabs, line breaks, punctuation, emoji) exactly where it was.
///
/// Each word is converted to UTF-8, encrypted with [HillCipher] and written
/// as uppercase hexadecimal. Separators never contain letters or digits, so
/// in ciphertext every run of `0-9A-F` is one encrypted word and everything
/// else is an original separator.
class WordCipher {
  const WordCipher({
    this.tokenizer = const TextTokenizer(),
    this.cipher = const HillCipher(),
  });

  final TextTokenizer tokenizer;
  final HillCipher cipher;

  static final RegExp _hexRun = RegExp('[0-9A-F]+');

  /// Encrypts [text] and verifies that decrypting the result gives the
  /// original back before returning it.
  String encrypt(String text, HillKeyMatrix key) {
    final buffer = StringBuffer();
    for (final token in tokenizer.tokenize(text)) {
      if (token.isWord) {
        buffer.write(
          HillCipher.toHex(cipher.encryptBytes(utf8.encode(token.text), key)),
        );
      } else {
        buffer.write(token.text);
      }
    }
    final result = buffer.toString();

    // Round-trip check: never hand back ciphertext that cannot be read.
    final String check;
    try {
      check = decrypt(result, key);
    } on AppException catch (error) {
      throw EncryptionFailedException(
        'The note could not be encrypted safely.',
        cause: error,
      );
    }
    if (check != text) {
      throw const EncryptionFailedException(
        'The note could not be encrypted safely.',
      );
    }
    return result;
  }

  /// Decrypts text produced by [encrypt] with the same key.
  ///
  /// Throws [CiphertextFormatException] if the text is not valid ciphertext
  /// and [DecryptionFailedException] if padding or UTF-8 is invalid. Note
  /// that a wrong key can still, by chance, produce valid-looking text: the
  /// Hill Cipher has no integrity check.
  String decrypt(String cipherText, HillKeyMatrix key) {
    final inverse = key.inverse();
    final buffer = StringBuffer();
    var position = 0;
    for (final match in _hexRun.allMatches(cipherText)) {
      _writeSeparator(buffer, cipherText.substring(position, match.start));
      final bytes = cipher.decryptBytes(HillCipher.fromHex(match[0]!), inverse);
      try {
        buffer.write(utf8.decode(bytes));
      } on FormatException catch (error) {
        throw DecryptionFailedException(
          'The note could not be decrypted (the result is not valid text).',
          cause: error,
        );
      }
      position = match.end;
    }
    _writeSeparator(buffer, cipherText.substring(position));
    return buffer.toString();
  }

  void _writeSeparator(StringBuffer buffer, String separator) {
    if (separator.isEmpty) return;
    if (TextTokenizer.wordChar.hasMatch(separator)) {
      throw const CiphertextFormatException(
        'The encrypted text is not in the expected format.',
      );
    }
    buffer.write(separator);
  }
}
