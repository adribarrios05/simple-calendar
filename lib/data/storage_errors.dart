import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart';

/// Explains storage failures without exposing SQL or the user's row contents.
String? storageErrorMessage(Object error) {
  var cause = error;
  while (cause is DriftRemoteException) {
    cause = cause.remoteCause;
  }
  if (cause is! SqliteException) return null;
  return switch (cause.resultCode & 0xff) {
    13 =>
      'There is not enough space to save changes. Free up space and try again.',
    8 => 'The database is read-only. Check the folder and file permissions.',
    5 || 6 => 'The database is busy. Close other instances and try again.',
    11 || 26 =>
      'The database cannot be read. Keep the original file and consult the recovery guide before restoring a backup.',
    14 =>
      'The database cannot be opened. Check that its folder exists and that you have permission to access it.',
    _ =>
      'The local data operation could not be completed. Try again; if it persists, keep a backup and consult the recovery guide.',
  };
}
