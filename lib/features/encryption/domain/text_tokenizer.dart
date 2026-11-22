import 'package:flutter/foundation.dart';

enum TokenType { word, separator }

@immutable
class TextToken {
  const TextToken(this.type, this.text);

  final TokenType type;
  final String text;

  bool get isWord => type == TokenType.word;

  @override
  bool operator ==(Object other) =>
      other is TextToken && other.type == type && other.text == text;

  @override
  int get hashCode => Object.hash(type, text);

  @override
  String toString() => '${type.name}(${text.length})';
}

/// Splits text into word and separator tokens. Joining all token texts
/// always gives back the exact input.
///
/// **Word rule.** A word is a run of *word characters* — any Unicode letter
/// (`\p{L}`), combining mark (`\p{M}`, including Bangla vowel signs and
/// hasanta), number (`\p{N}`), connector (`\p{Pc}`, e.g. `_`), or the zero
/// width (non-)joiner used in Bangla conjuncts — optionally joined by
/// *joiner punctuation* (`' ’ - . @ / : ? = & % + # ~`) that sits **between**
/// word characters. So `don't`, `well-known`, `3.14`, `2026-11-22`,
/// `user@example.com` and `https://example.com/a?b=1` are single words,
/// while punctuation at the start or end of a word (`Hello,` → `Hello` +
/// `,`) is a separator.
///
/// **Separators** are everything else: whitespace, line breaks, commas,
/// `।`, brackets, quotes, emoji and other symbols.
class TextTokenizer {
  const TextTokenizer();

  static const String wordCharClass = r'[\p{L}\p{M}\p{N}\p{Pc}‌‍]';
  static const String joinerClass = r"['’\-.@/:?=&%+#~]";

  static final RegExp _word = RegExp(
    '$wordCharClass+(?:$joinerClass+$wordCharClass+)*',
    unicode: true,
  );

  static final RegExp wordChar = RegExp(wordCharClass, unicode: true);

  List<TextToken> tokenize(String text) {
    final tokens = <TextToken>[];
    var position = 0;
    for (final match in _word.allMatches(text)) {
      if (match.start > position) {
        tokens.add(
          TextToken(TokenType.separator, text.substring(position, match.start)),
        );
      }
      tokens.add(TextToken(TokenType.word, match[0]!));
      position = match.end;
    }
    if (position < text.length) {
      tokens.add(TextToken(TokenType.separator, text.substring(position)));
    }
    return tokens;
  }
}
