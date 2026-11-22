import 'package:flutter/foundation.dart';

/// Describes how an encrypted note was encrypted, so that future versions
/// of the app can recognise (and migrate) older formats.
@immutable
class CipherFormat {
  const CipherFormat({
    required this.algorithm,
    required this.version,
    required this.encoding,
    required this.blockSize,
    required this.modulus,
  });

  /// Word-level 2×2 Hill Cipher over UTF-8 bytes, PKCS#7-style padding to
  /// 2-byte blocks, uppercase hexadecimal per word, separators kept.
  static const CipherFormat hillV1 = CipherFormat(
    algorithm: 'hill_cipher',
    version: 1,
    encoding: 'hex',
    blockSize: 2,
    modulus: 256,
  );

  static const List<CipherFormat> supported = [hillV1];

  final String algorithm;
  final int version;
  final String encoding;
  final int blockSize;
  final int modulus;

  bool get isSupported => supported.contains(this);

  Map<String, Object> toMap() => {
    'algorithm': algorithm,
    'version': version,
    'encoding': encoding,
    'blockSize': blockSize,
    'modulus': modulus,
  };

  /// Reads a stored map. Returns `null` if required values are missing.
  static CipherFormat? fromMap(Object? value) {
    if (value is! Map) return null;
    int? asInt(Object? v) => v is int ? v : (v is double ? v.toInt() : null);
    final algorithm = value['algorithm'];
    final version = asInt(value['version']);
    final encoding = value['encoding'];
    final blockSize = asInt(value['blockSize']);
    final modulus = asInt(value['modulus']);
    if (algorithm is! String ||
        version == null ||
        encoding is! String ||
        blockSize == null ||
        modulus == null) {
      return null;
    }
    return CipherFormat(
      algorithm: algorithm,
      version: version,
      encoding: encoding,
      blockSize: blockSize,
      modulus: modulus,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CipherFormat &&
      other.algorithm == algorithm &&
      other.version == version &&
      other.encoding == encoding &&
      other.blockSize == blockSize &&
      other.modulus == modulus;

  @override
  int get hashCode =>
      Object.hash(algorithm, version, encoding, blockSize, modulus);

  @override
  String toString() => '$algorithm v$version';
}
