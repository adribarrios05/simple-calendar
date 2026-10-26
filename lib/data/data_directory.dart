import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'database.dart' show calendarSchemaVersion;

/// Uses a stable folder name independent of executable version metadata.
Future<File> applicationDatabaseFile() {
  final roamingPath = Platform.environment['APPDATA'];
  if (roamingPath == null ||
      roamingPath.isEmpty ||
      !p.isAbsolute(roamingPath)) {
    throw const DataDirectoryException(
      'The Windows application data folder could not be located.',
    );
  }
  return prepareDatabaseFile(Directory(roamingPath));
}

class DataDirectoryException implements Exception {
  final String message;
  const DataDirectoryException(this.message);
  @override
  String toString() => message;
}

/// Resolves storage and snapshots a legacy agenda before its first new-path use.
/// Tests supply an isolated roaming root; normal startup supplies APPDATA.
Future<File> prepareDatabaseFile(Directory roamingRoot) async {
  final directory = Directory(p.join(roamingRoot.path, 'Simple Calendar'));
  await directory.create(recursive: true);
  final destination = File(p.join(directory.path, 'calendar.sqlite'));
  final legacy = File(
    p.join(
      roamingRoot.path,
      'local.calendario',
      'calendario',
      'calendario.sqlite',
    ),
  );
  // Keep a persistent lock file: deleting it could let concurrent processes lock
  // different files. The native single-instance mutex also remains unchanged.
  final lock = await File(
    p.join(directory.path, '.migration.lock'),
  ).open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    // An existing destination is authoritative, even when the legacy copy exists.
    if (await FileSystemEntity.type(destination.path) !=
        FileSystemEntityType.notFound) {
      if (!await destination.exists()) {
        throw const DataDirectoryException(
          'The Simple Calendar data path is not a database file.',
        );
      }
      return destination;
    }
    if (await FileSystemEntity.type(legacy.path) ==
        FileSystemEntityType.notFound) {
      return destination;
    }
    final staging = await directory.createTemp('.migration-');
    try {
      final snapshot = File(p.join(staging.path, 'calendar.sqlite'));
      final source = sqlite3.open(legacy.path, mode: OpenMode.readOnly);
      try {
        final version = source
            .select('PRAGMA user_version')
            .single
            .values
            .single;
        if (version is! int || version < 1 || version > calendarSchemaVersion) {
          throw const DataDirectoryException(
            'The previous database version is unsupported. Keep the original data folder and use a compatible application version.',
          );
        }
        if (source.select('PRAGMA quick_check').single.values.single != 'ok') {
          throw const DataDirectoryException(
            'The previous database failed its integrity check. Keep the original data folder and restore a valid backup.',
          );
        }
        // SQLite creates a consistent snapshot, including committed WAL data.
        // Copying only the main file could silently omit recent changes.
        source.execute('VACUUM INTO ?', [snapshot.path]);
      } finally {
        source.close();
      }
      final check = sqlite3.open(snapshot.path, mode: OpenMode.readOnly);
      try {
        if (check.select('PRAGMA quick_check').single.values.single != 'ok') {
          throw const DataDirectoryException(
            'The migrated database failed its integrity check. The original data folder has been preserved.',
          );
        }
      } finally {
        check.close();
      }
      // Publish only a complete snapshot. Failed/interrupted staging is never
      // mistaken for the active database. The original is intentionally retained.
      await snapshot.rename(destination.path);
      return destination;
    } finally {
      await staging.delete(recursive: true);
    }
  } finally {
    // Closing also releases the OS lock when migration throws.
    await lock.close();
  }
}
