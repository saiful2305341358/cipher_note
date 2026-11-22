import 'package:flutter/foundation.dart';

/// A single note.
///
/// Encryption is not implemented yet: [isEncrypted] is always `false`,
/// [keyId] and [keyVersion] are always `null`, and [content] is always
/// ordinary readable text. These fields exist so that a later phase can mark
/// a note as encrypted and record which key (and key version) it needs.
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
    this.keyId,
    this.keyVersion,
  });

  final String id;
  final String title;
  final String content;
  final bool isEncrypted;

  /// Id of the key metadata record needed to read this note, if encrypted.
  final String? keyId;

  /// Version of that key used for this note, if encrypted.
  final int? keyVersion;

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
    String? id,
    String? title,
    String? content,
    bool? isEncrypted,
    int? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      keyId: keyId,
      keyVersion: keyVersion,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Plain map representation (used for export and diagnostics in tests).
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'isEncrypted': isEncrypted,
    'keyId': keyId,
    'keyVersion': keyVersion,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Note.fromMap(Map<String, Object?> map) => Note(
    id: map['id']! as String,
    title: (map['title'] as String?) ?? '',
    content: (map['content'] as String?) ?? '',
    isEncrypted: (map['isEncrypted'] as bool?) ?? false,
    keyId: map['keyId'] as String?,
    keyVersion: map['keyVersion'] as int?,
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
      other.keyId == keyId &&
      other.keyVersion == keyVersion &&
      other.color == color &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, title, content, isEncrypted, color, createdAt, updatedAt);

  @override
  String toString() => 'Note($id, "$displayTitle")';
}
