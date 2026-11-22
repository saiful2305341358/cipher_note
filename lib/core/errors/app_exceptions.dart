/// Errors raised by the data layer.
///
/// Messages are written for users. They never contain note text, titles or
/// key material, so they are also safe to log.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Short, user-facing description.
  final String message;

  /// Underlying error, for diagnostics only. Never shown to users.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' (${cause.runtimeType})'}';
}

/// The local database could not be opened or prepared.
class DatabaseInitException extends AppException {
  const DatabaseInitException(super.message, {super.cause});
}

/// A read or write on the local database failed.
class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// A record that was expected to exist was not found.
class RecordNotFoundException extends AppException {
  const RecordNotFoundException(super.message);
}

/// A record with the same id already exists.
class DuplicateRecordException extends AppException {
  const DuplicateRecordException(super.message);
}

// ---------------------------------------------------------------------------
// Encryption errors. Messages never contain plaintext, ciphertext or key
// values.

/// A key matrix is not usable (out of range or not invertible mod 256).
class InvalidKeyException extends AppException {
  const InvalidKeyException(super.message, {super.cause});
}

/// Why a key could not be used.
enum KeyUnavailableReason {
  missingMetadata,
  unsupportedAlgorithm,
  missingMaterial,
}

/// The key a note needs is missing, deleted, or has a different version.
class KeyUnavailableException extends AppException {
  const KeyUnavailableException(
    super.message, {
    super.cause,
    this.reason = KeyUnavailableReason.missingMetadata,
  });

  final KeyUnavailableReason reason;
}

/// Stored ciphertext is not in a format this app can read.
class CiphertextFormatException extends AppException {
  const CiphertextFormatException(super.message, {super.cause});
}

/// Decryption produced invalid padding or invalid UTF-8.
class DecryptionFailedException extends AppException {
  const DecryptionFailedException(super.message, {super.cause});
}

/// Encryption failed or could not be verified.
class EncryptionFailedException extends AppException {
  const EncryptionFailedException(super.message, {super.cause});
}

/// Platform secure storage could not be read or written.
class SecureStorageException extends AppException {
  const SecureStorageException(super.message, {super.cause});
}

/// A key cannot be deleted because encrypted notes still use it.
class KeyInUseException extends AppException {
  const KeyInUseException(super.message, {required this.noteCount});

  final int noteCount;
}

/// An encrypted note's text was about to be edited without decrypting it.
class EncryptedNoteLockedException extends AppException {
  const EncryptedNoteLockedException(super.message);
}
