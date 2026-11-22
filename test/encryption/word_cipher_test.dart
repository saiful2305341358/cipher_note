import 'package:cipher_note/core/errors/app_exceptions.dart';
import 'package:cipher_note/features/encryption/domain/hill_cipher.dart';
import 'package:cipher_note/features/encryption/domain/hill_key_matrix.dart';
import 'package:cipher_note/features/encryption/domain/text_tokenizer.dart';
import 'package:cipher_note/features/encryption/domain/word_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokenizer = TextTokenizer();
const _cipher = WordCipher();
final _key = HillKeyMatrix(3, 5, 7, 2);
final _otherKey = HillKeyMatrix(17, 200, 33, 91);

List<String> _words(String text) => [
  for (final t in _tokenizer.tokenize(text))
    if (t.isWord) t.text,
];

List<String> _separators(String text) => [
  for (final t in _tokenizer.tokenize(text))
    if (!t.isWord) t.text,
];

const _samples = <String, String>{
  'empty': '',
  'spaces only': '   \t \n ',
  'english': 'Hello, how are you?',
  'prompt example': 'Hello, how are you?\nআমি ভালো আছি। Thank you!',
  'bangla': 'আমি Flutter দিয়ে একটি Note Taking Application তৈরি করছি।',
  'bangla vowel signs and conjuncts':
      'কি কী কু কূ কৃ কে কৈ কো কৌ ক্ষ ত্র জ্ঞ ক্য ক্র র্ক শ্রী হ্ম',
  'zwj/zwnj': 'র‍্যাব র‌্যাব ক্‌ষ',
  'combining marks': 'é café ñ Å',
  'emoji': 'Party 🎉 time 👨‍👩‍👧‍👦 🇧🇩 ❤️!',
  'unicode punctuation': '“Quoted” — dash… ‘single’ «guillemets» ¡Hola! ¿Qué?',
  'paragraphs':
      'First paragraph.\n\nSecond   paragraph,\twith tabs.\r\n\nThird',
  'numbers and dates': 'Pi is 3.14, date 2026-11-22, time 16:49, 1,000 items',
  'url and email': 'Visit https://example.com/path?q=1&x=y#top or mail user.name@example.co.bd',
  'apostrophes and hyphens': "don't it’s well-known state-of-the-art",
  'leading/trailing punctuation': '...(hello)... [world]! -- {x}',
  'mixed alphanumeric': 'abc123 Flutter3 ১২৩ abc১২৩ snake_case',
  'bangla numerals and danda': '১২৩৪৫ টাকা। ২০২৬ সাল॥',
};

void main() {
  group('Tokenizer', () {
    test('joining tokens always gives back the exact input', () {
      for (final entry in _samples.entries) {
        final tokens = _tokenizer.tokenize(entry.value);
        expect(
          tokens.map((t) => t.text).join(),
          entry.value,
          reason: entry.key,
        );
        // Words and separators alternate; never two of the same in a row.
        for (var i = 1; i < tokens.length; i++) {
          expect(tokens[i].type, isNot(tokens[i - 1].type), reason: entry.key);
        }
      }
    });

    test('empty text has no tokens', () {
      expect(_tokenizer.tokenize(''), isEmpty);
    });

    test('splits English words from punctuation and spaces', () {
      expect(_words('Hello, how are you?'), ['Hello', 'how', 'are', 'you']);
      expect(_separators('Hello, how are you?'), [', ', ' ', ' ', '?']);
    });

    test('keeps Bangla words whole, including vowel signs and conjuncts', () {
      expect(_words('আমি ভালো আছি। কিছুক্ষণ'), [
        'আমি',
        'ভালো',
        'আছি',
        'কিছুক্ষণ',
      ]);
      expect(_separators('আমি ভালো আছি। কিছুক্ষণ'), [' ', ' ', '। ']);
      expect(_words('র‍্যাব'), ['র‍্যাব'], reason: 'ZWJ stays inside the word');
    });

    test('keeps combining marks with their letters', () {
      expect(_words('café ok'), ['café', 'ok']);
    });

    test(
      'treats numbers, decimals, dates, URLs and emails as single words',
      () {
        expect(_words('3.14 2026-11-22 16:49'), [
          '3.14',
          '2026-11-22',
          '16:49',
        ]);
        expect(_words('https://example.com/a?b=1&c=2#x'), [
          'https://example.com/a?b=1&c=2#x',
        ]);
        expect(_words('mail user.name@example.co.bd.'), [
          'mail',
          'user.name@example.co.bd',
        ]);
        expect(_words("don't well-known it’s"), [
          "don't",
          'well-known',
          'it’s',
        ]);
        expect(_words('abc123 snake_case'), ['abc123', 'snake_case']);
      },
    );

    test('punctuation at word edges is a separator', () {
      expect(_words('(hello) -world- end.'), ['hello', 'world', 'end']);
      expect(_separators('(hello) -world- end.'), ['(', ') -', '- ', '.']);
    });

    test('emoji are separators', () {
      expect(_words('Party 🎉 time'), ['Party', 'time']);
      expect(_separators('Party 🎉 time'), [' 🎉 ']);
    });

    test('tabs, newlines and repeated spaces are separators', () {
      expect(_separators('a\tb\n\nc   d\r\ne'), ['\t', '\n\n', '   ', '\r\n']);
    });
  });

  group('WordCipher round trip', () {
    for (final entry in _samples.entries) {
      test('restores exactly: ${entry.key}', () {
        final encrypted = _cipher.encrypt(entry.value, _key);
        expect(_cipher.decrypt(encrypted, _key), entry.value);

        final encrypted2 = _cipher.encrypt(entry.value, _otherKey);
        expect(_cipher.decrypt(encrypted2, _otherKey), entry.value);
      });
    }

    test('only words change; separators stay in place', () {
      for (final entry in _samples.entries) {
        final plain = entry.value;
        final encrypted = _cipher.encrypt(plain, _key);
        final plainTokens = _tokenizer.tokenize(plain);
        // Every word becomes uppercase hex; every separator is unchanged.
        final hexTokens = RegExp('[0-9A-F]+').allMatches(encrypted).toList();
        expect(hexTokens.length, _words(plain).length, reason: entry.key);
        expect(
          encrypted.split(RegExp('[0-9A-F]+')).where((s) => s.isNotEmpty),
          _separators(plain),
          reason: entry.key,
        );
        // Plain words do not appear in the ciphertext (words made only of
        // hex characters, like "1", can occur in hex by chance).
        final hexOnly = RegExp(r'^[0-9A-F]+$');
        for (final t in plainTokens.where(
          (t) => t.isWord && !hexOnly.hasMatch(t.text),
        )) {
          expect(encrypted, isNot(contains(t.text)), reason: entry.key);
        }
      }
    });

    test('the prompt example keeps its punctuation and line break', () {
      const plain = 'Hello, how are you?\nআমি ভালো আছি। Thank you!';
      final encrypted = _cipher.encrypt(plain, _key);
      final shape = encrypted.replaceAll(RegExp('[0-9A-F]+'), 'W');
      expect(shape, 'W, W W W?\nW W W। W W!');
    });

    test('a different key gives different ciphertext', () {
      expect(
        _cipher.encrypt('Hello world', _key),
        isNot(_cipher.encrypt('Hello world', _otherKey)),
      );
    });
  });

  group('WordCipher decryption errors', () {
    test('wrong key fails or gives different text (never silently '
        'returns the original)', () {
      final encrypted = _cipher.encrypt('Secret meeting at noon', _key);
      try {
        expect(
          _cipher.decrypt(encrypted, _otherKey),
          isNot('Secret meeting at noon'),
        );
      } on AppException catch (error) {
        expect(
          error,
          anyOf(
            isA<DecryptionFailedException>(),
            isA<CiphertextFormatException>(),
          ),
        );
      }
    });

    test('rejects lowercase or letters in the ciphertext', () {
      final encrypted = _cipher.encrypt('Hello world', _key);
      expect(
        () => _cipher.decrypt(encrypted.toLowerCase(), _key),
        throwsA(isA<CiphertextFormatException>()),
      );
      expect(
        () => _cipher.decrypt('$encrypted plain', _key),
        throwsA(isA<CiphertextFormatException>()),
      );
    });

    test('rejects odd-length hex words', () {
      expect(
        () => _cipher.decrypt('ABC', _key),
        throwsA(isA<CiphertextFormatException>()),
      );
    });

    test('rejects invalid padding', () {
      // Bytes whose decryption ends in an invalid padding value (5).
      final bad = HillCipher.toHex(
        HillCipher.transformPairs([0x41, 0x05], _key),
      );
      expect(
        () => _cipher.decrypt(bad, _key),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('rejects invalid UTF-8', () {
      // 0xFF is never valid UTF-8; padding (0x01) is valid.
      final bad = HillCipher.toHex(
        HillCipher.transformPairs([0xFF, 0x01], _key),
      );
      expect(
        () => _cipher.decrypt(bad, _key),
        throwsA(isA<DecryptionFailedException>()),
      );
    });
  });
}
