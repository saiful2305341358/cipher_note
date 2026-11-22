import '../../../core/errors/app_exceptions.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../data/models/cipher_format.dart';
import '../../../data/models/key_metadata.dart';
import '../../../data/models/note_model.dart';
import '../domain/word_cipher.dart';
import 'key_service.dart';

/// Readable title and content of a decrypted note. Held in memory only
/// while the note is open; never stored.
class DecryptedText {
  const DecryptedText({required this.title, required this.content});

  final String title;
  final String content;

  @override
  String toString() => 'DecryptedText(hidden)';
}

/// Connects the cipher with keys and notes. It only *computes* encrypted
/// or decrypted notes; storing the result is up to the caller, so a failed
/// operation can never change a stored note.
class NoteEncryptionService {
  NoteEncryptionService({
    required this._keys,
    this._cipher = const WordCipher(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final KeyService _keys;
  final WordCipher _cipher;
  final DateTime Function() _clock;

  static const CipherFormat format = CipherFormat.hillV1;

  /// Returns [note] encrypted with [key], using [title] and [content] as the
  /// plaintext (title and content are encrypted separately).
  Future<Note> encrypt({
    required Note note,
    required String title,
    required String content,
    required KeyMetadata key,
  }) => _guard('The note could not be encrypted.', () async {
    final matrix = await _keys.loadKey(key.id, key.version);
    final cipherTitle = _cipher.encrypt(title, matrix);
    final cipherContent = _cipher.encrypt(content, matrix);
    return note.toEncrypted(
      cipherTitle: cipherTitle,
      cipherContent: cipherContent,
      keyId: key.id,
      keyVersion: key.version,
      format: format,
      updatedAt: _clock(),
    );
  });

  /// Decrypts an encrypted note with exactly the key version it references.
  ///
  /// Success means the padding and UTF-8 were valid. The Hill Cipher has no
  /// integrity check, so this does not prove the text is unchanged.
  Future<DecryptedText> decrypt(Note note) =>
      _guard('The note could not be decrypted.', () async {
        final keyId = note.keyId;
        final keyVersion = note.keyVersion;
        if (!note.isEncrypted || keyId == null || keyVersion == null) {
          throw const CiphertextFormatException(
            'This note is missing its encryption details.',
          );
        }
        final noteFormat = note.cipherFormat;
        if (noteFormat == null || !noteFormat.isSupported) {
          throw const CiphertextFormatException(
            'This note was encrypted in a format this app cannot read.',
          );
        }
        final matrix = await _keys.loadKey(keyId, keyVersion);
        return DecryptedText(
          title: _cipher.decrypt(note.title, matrix),
          content: _cipher.decrypt(note.content, matrix),
        );
      });

  Future<T> _guard<T>(String failure, Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stack) {
      // Only the error type is reported, never note text or key values.
      ErrorReporter.report('NoteEncryptionService', error.runtimeType, stack);
      throw EncryptionFailedException(failure, cause: error.runtimeType);
    }
  }
}
