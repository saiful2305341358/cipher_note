import '../models/encryption_key_info.dart';

/// Storage abstraction for encryption key metadata.
///
/// Kept separate from [NoteRepository] so that key handling (secure storage,
/// validation) can evolve independently of note storage.
abstract class KeyRepository {
  Future<EncryptionKeyInfo?> getKeyInfo();

  Future<void> saveKeyInfo(EncryptionKeyInfo info);

  Future<void> deleteKeyInfo();
}

/// In-memory key metadata store used in Phase 1. It never holds key material.
class InMemoryKeyRepository implements KeyRepository {
  InMemoryKeyRepository([this._info]);

  EncryptionKeyInfo? _info;

  @override
  Future<EncryptionKeyInfo?> getKeyInfo() async => _info;

  @override
  Future<void> saveKeyInfo(EncryptionKeyInfo info) async => _info = info;

  @override
  Future<void> deleteKeyInfo() async => _info = null;
}
