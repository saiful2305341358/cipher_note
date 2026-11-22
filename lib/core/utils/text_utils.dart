/// Text helpers that work for both English and Bangla.
class TextUtils {
  TextUtils._();

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Counts whitespace-separated words. Works for Bangla because Bangla
  /// words are also separated by spaces.
  static int wordCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(_whitespace).length;
  }

  /// Number of user-perceived characters (grapheme clusters are not used to
  /// avoid an extra dependency; this counts Unicode code points).
  static int characterCount(String text) => text.runes.length;

  /// Collapses whitespace so previews stay on as few lines as possible.
  static String singleLine(String text) =>
      text.trim().replaceAll(_whitespace, ' ');

  /// Case-insensitive comparison key used by search. Bangla has no case, so
  /// lower-casing leaves it unchanged.
  static String searchKey(String text) => text.toLowerCase();
}
