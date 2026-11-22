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
