import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/cipher_format.dart';
import '../../data/models/key_metadata.dart';
import '../../data/models/note_model.dart';
import 'database_constants.dart';

// Hand-written adapters. Every record is written as a map of
// `field index -> value`, the same layout Hive's code generator uses. Reading
// is tolerant: unknown fields are ignored and missing or malformed fields get
// safe defaults, so old records keep loading after the model gains fields.
//
// Field indexes are permanent. Never reuse or renumber them.

Map<int, Object?> _readFields(BinaryReader reader) {
  final count = reader.readByte();
  return {for (var i = 0; i < count; i++) reader.readByte(): reader.read()};
}

void _writeFields(BinaryWriter writer, Map<int, Object?> fields) {
  writer.writeByte(fields.length);
  fields.forEach((index, value) {
    writer
      ..writeByte(index)
      ..write(value);
  });
}

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int? _intOrNull(Object? value) => switch (value) {
  final int v => v,
  final double v when v == v.roundToDouble() => v.toInt(),
  _ => null,
};

bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

/// Timestamps are stored as UTC microseconds since epoch and read back as
/// local time.
int _encodeTime(DateTime time) => time.toUtc().microsecondsSinceEpoch;

DateTime? _decodeTime(Object? value) {
  final micros = _intOrNull(value);
  return micros == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toLocal();
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Stores [Note]. Field indexes:
/// 0 id, 1 title, 2 content, 3 isEncrypted, 4 color, 5 createdAt,
/// 6 updatedAt, 7 keyId, 8 keyVersion, 9 cipherFormat (map, schema v2).
class NoteAdapter extends TypeAdapter<Note> {
  @override
  int get typeId => DatabaseConstants.noteTypeId;

  @override
  Note read(BinaryReader reader) {
    final f = _readFields(reader);
    final updatedAt = _decodeTime(f[6]);
    final createdAt = _decodeTime(f[5]) ?? updatedAt;
    final fallbackTime = DateTime.fromMicrosecondsSinceEpoch(0);
    return Note(
      // An empty id is repaired from the box key by the repository.
      id: _string(f[0]),
      title: _string(f[1]),
      content: _string(f[2]),
      isEncrypted: _bool(f[3], false),
      color: _intOrNull(f[4]) ?? AppSettings.defaultColorValue,
      createdAt: createdAt ?? fallbackTime,
      updatedAt: updatedAt ?? createdAt ?? fallbackTime,
      keyId: f[7] is String ? f[7] as String : null,
      keyVersion: _intOrNull(f[8]),
      cipherFormat: CipherFormat.fromMap(f[9]),
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) => _writeFields(writer, {
    0: obj.id,
    1: obj.title,
    2: obj.content,
    3: obj.isEncrypted,
    4: obj.color,
    5: _encodeTime(obj.createdAt),
    6: _encodeTime(obj.updatedAt),
    7: obj.keyId,
    8: obj.keyVersion,
    9: obj.cipherFormat?.toMap(),
  });
}

/// Stores [KeyMetadata] (never key material). Field indexes:
/// 0 id, 1 name, 2 version, 3 algorithm, 4 createdAt, 5 isActive.
class KeyMetadataAdapter extends TypeAdapter<KeyMetadata> {
  @override
  int get typeId => DatabaseConstants.keyMetadataTypeId;

  @override
  KeyMetadata read(BinaryReader reader) {
    final f = _readFields(reader);
    final name = _string(f[1]).trim();
    final version = _intOrNull(f[2]) ?? 1;
    return KeyMetadata(
      id: _string(f[0], 'unknown'),
      name: name.isEmpty
          ? 'Key'
          : name.substring(0, name.length.clamp(0, KeyMetadata.maxNameLength)),
      version: version < 1 ? 1 : version,
      algorithm: _string(f[3], KeyMetadata.hillCipher2x2),
      createdAt: _decodeTime(f[4]) ?? DateTime.fromMicrosecondsSinceEpoch(0),
      isActive: _bool(f[5], false),
    );
  }

  @override
  void write(BinaryWriter writer, KeyMetadata obj) => _writeFields(writer, {
    0: obj.id,
    1: obj.name,
    2: obj.version,
    3: obj.algorithm,
    4: _encodeTime(obj.createdAt),
    5: obj.isActive,
  });
}

/// Stores [AppSettings]. Enums are stored by name. Field indexes:
/// 0 themeMode, 1 viewMode, 2 sortOrder, 3 defaultNoteColor,
/// 4 showContentPreview, 5 autoSave.
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  int get typeId => DatabaseConstants.appSettingsTypeId;

  @override
  AppSettings read(BinaryReader reader) {
    final f = _readFields(reader);
    const d = AppSettings.defaults;
    return AppSettings(
      themeMode: _enumByName(ThemeMode.values, f[0], d.themeMode),
      viewMode: _enumByName(NoteViewMode.values, f[1], d.viewMode),
      sortOrder: _enumByName(NoteSortOrder.values, f[2], d.sortOrder),
      defaultNoteColor: _intOrNull(f[3]) ?? d.defaultNoteColor,
      showContentPreview: _bool(f[4], d.showContentPreview),
      autoSave: _bool(f[5], d.autoSave),
    ).sanitized();
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) => _writeFields(writer, {
    0: obj.themeMode.name,
    1: obj.viewMode.name,
    2: obj.sortOrder.name,
    3: obj.defaultNoteColor,
    4: obj.showContentPreview,
    5: obj.autoSave,
  });
}
