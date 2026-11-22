import 'dart:io';

import 'package:cipher_note/core/database/hive_service.dart';
import 'package:hive_ce/hive_ce.dart';

/// Creates an isolated temporary database directory for one test.
/// Real app data is never touched.
class TestDatabase {
  TestDatabase._(this.directory);

  final Directory directory;
  HiveService? service;

  static Future<TestDatabase> create() async {
    final dir = await Directory.systemTemp.createTemp('cipher_note_test_');
    return TestDatabase._(dir);
  }

  /// Opens (or re-opens, simulating an app restart) the database.
  Future<HiveService> open() async {
    await service?.close();
    service = await HiveService.open(directory: directory.path);
    return service!;
  }

  /// Closes the database without opening it again.
  Future<void> close() async {
    await service?.close();
    service = null;
  }

  Future<void> dispose() async {
    await close();
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
