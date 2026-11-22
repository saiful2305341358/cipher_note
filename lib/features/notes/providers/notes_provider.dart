import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/models/note_model.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../core/utils/text_utils.dart';

/// How notes are ordered on the home screen.
enum NoteSortOrder {
  modified('Modified time'),
  created('Created time'),
  title('Title'),
  color('Color');

  const NoteSortOrder(this.label);
  final String label;
}

/// App-facing note state. Screens read and change notes only through this
/// class; persistence is delegated to a [NoteRepository].
///
/// Changes are applied to the in-memory cache first (so the UI updates
/// immediately) and then forwarded to the repository.
class NotesProvider extends ChangeNotifier {
  NotesProvider(
    this._repository, {
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? _defaultId;

  final NoteRepository _repository;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  final Map<String, Note> _notes = {};
  bool _isLoaded = false;

  static int _idCounter = 0;
  static final Random _random = Random();

  static String _defaultId() {
    _idCounter++;
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = _random.nextInt(1 << 20).toRadixString(36);
    return 'n_${time}_${_idCounter.toRadixString(36)}_$rand';
  }

  bool get isLoaded => _isLoaded;

  /// All notes, most recently modified first.
  List<Note> get notes => sorted(NoteSortOrder.modified);

  int get count => _notes.length;

  bool get isEmpty => _notes.isEmpty;

  /// Loads notes from the repository into memory.
  Future<void> load() async {
    final stored = await _repository.getAll();
    _notes
      ..clear()
      ..addEntries(stored.map((n) => MapEntry(n.id, n)));
    _isLoaded = true;
    notifyListeners();
  }

  Note? getById(String id) => _notes[id];

  /// Returns the notes ordered by [order].
  List<Note> sorted(NoteSortOrder order) {
    final list = _notes.values.toList();
    switch (order) {
      case NoteSortOrder.modified:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case NoteSortOrder.created:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case NoteSortOrder.title:
        list.sort(
          (a, b) =>
              TextUtils.searchKey(a.displayTitle)
                  .compareTo(TextUtils.searchKey(b.displayTitle)),
        );
      case NoteSortOrder.color:
        list.sort((a, b) {
          final byColor = a.color.compareTo(b.color);
          return byColor != 0 ? byColor : b.updatedAt.compareTo(a.updatedAt);
        });
    }
    return list;
  }

  /// Creates and stores a new note.
  Future<Note> createNote({
    String title = '',
    String content = '',
    required int color,
  }) async {
    final now = _clock();
    final note = Note(
      id: _idGenerator(),
      title: title,
      content: content,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    _notes[note.id] = note;
    notifyListeners();
    await _repository.save(note);
    return note;
  }

  /// Updates an existing note. Only the given fields change. The modified
  /// time is updated only when something actually changed.
  Future<Note?> updateNote(
    String id, {
    String? title,
    String? content,
    int? color,
  }) async {
    final existing = _notes[id];
    if (existing == null) return null;
    final changed =
        (title != null && title != existing.title) ||
        (content != null && content != existing.content) ||
        (color != null && color != existing.color);
    if (!changed) return existing;

    final updated = existing.copyWith(
      title: title,
      content: content,
      color: color,
      updatedAt: _clock(),
    );
    _notes[id] = updated;
    notifyListeners();
    await _repository.save(updated);
    return updated;
  }

  /// Changes the colour of a note.
  Future<Note?> changeColor(String id, int color) =>
      updateNote(id, color: color);

  /// Deletes a note and returns it (so it can be restored), or `null`.
  Future<Note?> deleteNote(String id) async {
    final removed = _notes.remove(id);
    if (removed == null) return null;
    notifyListeners();
    await _repository.delete(id);
    return removed;
  }

  /// Puts a previously deleted note back, unchanged.
  Future<void> restoreNote(Note note) async {
    _notes[note.id] = note;
    notifyListeners();
    await _repository.save(note);
  }

  /// Notes whose title or content contains [query] (case-insensitive for
  /// English; Bangla is matched exactly). Results are ordered with title
  /// matches first, then by modified time.
  List<Note> search(String query) {
    final key = TextUtils.searchKey(query.trim());
    if (key.isEmpty) return const [];
    final titleMatches = <Note>[];
    final contentMatches = <Note>[];
    for (final note in sorted(NoteSortOrder.modified)) {
      if (TextUtils.searchKey(note.title).contains(key)) {
        titleMatches.add(note);
      } else if (TextUtils.searchKey(note.content).contains(key)) {
        contentMatches.add(note);
      }
    }
    return [...titleMatches, ...contentMatches];
  }
}
