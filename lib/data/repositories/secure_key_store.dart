/// Where key material (the cipher matrix) will be kept in a later phase.
///
/// Key material must never be written to Hive. A future implementation will
/// use platform secure storage (Android Keystore-backed), for example via
/// the `flutter_secure_storage` package, and will look keys up by the
/// metadata id and version stored in `KeyMetadata`.
///
/// No implementation exists yet: key generation and encryption are not part
/// of the current version, so nothing calls this interface.
abstract class SecureKeyStore {
  /// Stores key material for [keyId] / [version].
  Future<void> write({
    required String keyId,
    required int version,
    required List<int> material,
  });

  /// Returns key material, or `null` if none is stored.
  Future<List<int>?> read({required String keyId, required int version});

  Future<void> delete({required String keyId, required int version});
}
