import 'package:flutter/foundation.dart';

import 'cipher_format.dart';

/// A single note.
///
/// A plain note has `isEncrypted == false` and readable [title] and
/// [content]; [keyId], [keyVersion] and [cipherFormat] are `null`.
///
/// An encrypted note stores ciphertext in [title] and [content] (both are
/// encrypted, separately), plus the [keyId] and [keyVersion] of the key
/// needed to read it and the [cipherFormat] used. The plaintext is never
/// stored. Use [toEncrypted] and [toPlain] to switch between the two so the
/// fields always stay consistent.
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
    this.cipherFormat,
  });

  /// Label used instead of the title for encrypted notes.
  static const String encryptedLabel = 'Encrypted note';

  final String id;
  final String title;
  final String content;
  final bool isEncrypted;

  /// Id of the key metadata record needed to read this note, if encrypted.
  final String? keyId;

  /// Version of that key used for this note, if encrypted.
  final int? keyVersion;

  /// How the note was encrypted, if encrypted.
  final CipherFormat? cipherFormat;

  /// ARGB value of the note colour (see `AppColors.noteColors`).
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when both title and content are blank.
  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;

  /// Title to show in lists. Falls back to the first content line. For
  /// encrypted notes this is always [encryptedLabel], so ciphertext and
  /// plaintext titles never appear in lists, sorting or semantics.
  String get displayTitle {
    if (isEncrypted) return encryptedLabel;
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) return trimmedTitle;
    final firstLine = content.trim().split('\n').first.trim();
    return firstLine.isEmpty ? 'Untitled' : firstLine;
  }

  /// Copies the note. Encryption fields are kept as they are; use
  /// [toEncrypted] / [toPlain] to change them.
  Note copyWith({
    String? id,
    String? title,
    String? content,
    int? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      isEncrypted: isEncrypted,
      keyId: keyId,
      keyVersion: keyVersion,
      cipherFormat: cipherFormat,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The same note holding ciphertext, linked to a key.
  Note toEncrypted({
    required String cipherTitle,
    required String cipherContent,
    required String keyId,
    required int keyVersion,
    required CipherFormat format,
    required DateTime updatedAt,
  }) => Note(
    id: id,
    title: cipherTitle,
    content: cipherContent,
    isEncrypted: true,
    keyId: keyId,
    keyVersion: keyVersion,
    cipherFormat: format,
    color: color,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// The same note holding readable text, with all encryption fields
  /// cleared.
  Note toPlain({
    required String title,
    required String content,
    required DateTime updatedAt,
  }) => Note(
    id: id,
    title: title,
    content: content,
    color: color,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// Plain map representation (used for export and diagnostics in tests).
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'isEncrypted': isEncrypted,
    'keyId': keyId,
    'keyVersion': keyVersion,
    'cipherFormat': cipherFormat?.toMap(),
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
    cipherFormat: CipherFormat.fromMap(map['cipherFormat']),
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
      other.cipherFormat == cipherFormat &&
      other.color == color &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    content,
    isEncrypted,
    keyId,
    keyVersion,
    cipherFormat,
    color,
    createdAt,
    updatedAt,
  );

  /// Never includes title or content, so notes cannot leak into logs.
  @override
  String toString() => 'Note($id${isEncrypted ? ', encrypted' : ''})';
}
