import '../../data/models/note_model.dart';
import 'text_utils.dart';

/// Search rules shared by the note provider and the repositories, so that
/// every layer returns the same results.
class NoteSearch {
  NoteSearch._();

  /// True when [query] is blank and should return no results.
  static bool isBlank(String query) => query.trim().isEmpty;

  /// Returns notes whose title or content contains [query]. English matches
  /// ignore case; Bangla has no case and matches exactly. Title matches come
  /// first, then content matches, each newest-modified first.
  static List<Note> filter(Iterable<Note> notes, String query) {
    final key = TextUtils.searchKey(query.trim());
    if (key.isEmpty) return const [];
    final ordered = notes.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final titleMatches = <Note>[];
    final contentMatches = <Note>[];
    for (final note in ordered) {
      if (TextUtils.searchKey(note.title).contains(key)) {
        titleMatches.add(note);
      } else if (TextUtils.searchKey(note.content).contains(key)) {
        contentMatches.add(note);
      }
    }
    return [...titleMatches, ...contentMatches];
  }
}
