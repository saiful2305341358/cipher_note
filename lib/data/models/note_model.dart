import 'package:flutter/foundation.dart';

/// A single note.
///
/// In Phase 1 [isEncrypted] is always `false` and [content] is always
/// ordinary readable text. The field exists so that future storage and
/// encryption layers can use the same model without changing the UI.
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.isEncrypted = false,
  });

  final String id;
  final String title;
  final String content;
  final bool isEncrypted;

  /// ARGB value of the note colour (see `AppColors.noteColors`).
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when both title and content are blank.
  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;

  /// Title to show in lists. Falls back to the first content line.
  String get displayTitle {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) return trimmedTitle;
    final firstLine = content.trim().split('\n').first.trim();
    return firstLine.isEmpty ? 'Untitled' : firstLine;
  }

  Note copyWith({
    String? title,
    String? content,
    bool? isEncrypted,
    int? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Plain map representation, ready for a future storage adapter.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'isEncrypted': isEncrypted,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Note.fromMap(Map<String, Object?> map) => Note(
    id: map['id']! as String,
    title: (map['title'] as String?) ?? '',
    content: (map['content'] as String?) ?? '',
    isEncrypted: (map['isEncrypted'] as bool?) ?? false,
    color: map['color']! as int,
    createdAt: DateTime.parse(map['createdAt']! as String),
    updatedAt: DateTime.parse(map['updatedAt']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.content == content &&
      other.isEncrypted == isEncrypted &&
      other.color == color &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, title, content, isEncrypted, color, createdAt, updatedAt);

  @override
  String toString() => 'Note($id, "$displayTitle")';
}
