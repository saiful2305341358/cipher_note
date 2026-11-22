import 'package:flutter/foundation.dart';

/// Descriptive information about an encryption key.
///
/// This record never contains key material. The actual key (the cipher
/// matrix) will live in platform secure storage in a later phase, looked up
/// by [id] and [version]. [name] is a display label only.
@immutable
class KeyMetadata {
  KeyMetadata({
    required this.id,
    required String name,
    required this.version,
    required this.algorithm,
    required this.createdAt,
    this.isActive = true,
  }) : name = validateName(name) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be 1 or more');
    }
  }

  /// Algorithm identifier for the planned 2×2 Hill Cipher.
  static const String hillCipher2x2 = 'hill-2x2';

  static const int maxNameLength = 40;

  final String id;

  /// User-facing label, e.g. "Personal key".
  final String name;

  /// Increases each time the key is replaced, so notes can record which
  /// version they were encrypted with.
  final int version;

  final String algorithm;
  final DateTime createdAt;

  /// Whether this key is the one used for new encrypted notes.
  final bool isActive;

  /// Trims [name] and checks that it is a short, non-empty label.
  static String validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (trimmed.length > maxNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'must be at most $maxNameLength characters',
      );
    }
    return trimmed;
  }

  KeyMetadata copyWith({String? name, int? version, bool? isActive}) =>
      KeyMetadata(
        id: id,
        name: name ?? this.name,
        version: version ?? this.version,
        algorithm: algorithm,
        createdAt: createdAt,
        isActive: isActive ?? this.isActive,
      );

  @override
  bool operator ==(Object other) =>
      other is KeyMetadata &&
      other.id == id &&
      other.name == name &&
      other.version == version &&
      other.algorithm == algorithm &&
      other.createdAt == createdAt &&
      other.isActive == isActive;

  @override
  int get hashCode =>
      Object.hash(id, name, version, algorithm, createdAt, isActive);

  @override
  String toString() => 'KeyMetadata($id, v$version, $algorithm)';
}
