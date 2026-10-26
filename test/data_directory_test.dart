import 'dart:convert';
import 'dart:io';

import 'package:simple_calendar/data/data_directory.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late File legacy;
  late File destination;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('simple-calendar-storage-');
    legacy = File(
      p.join(root.path, 'local.calendario', 'calendario', 'calendario.sqlite'),
    );
    destination = File(p.join(root.path, 'Simple Calendar', 'calendar.sqlite'));
  });
  tearDown(() async => root.delete(recursive: true));

  for (final version in [1, 2]) {
    test('legacy schema v$version relocates before the existing v4 upgrade', () async {
      await legacy.parent.create(recursive: true);
      final raw = sqlite.sqlite3.open(legacy.path);
      try {
        raw.execute(
          'CREATE TABLE definitions (id TEXT NOT NULL PRIMARY KEY, payload TEXT NOT NULL)',
        );
        raw.execute(
          'CREATE TABLE executions (task_id TEXT NOT NULL REFERENCES definitions(id), day TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(task_id, day))',
        );
        raw.execute(
          'CREATE TABLE settings (id TEXT NOT NULL PRIMARY KEY, payload TEXT NOT NULL)',
        );
        if (version == 2) {
          raw.execute(
            'CREATE TABLE revisions (task_id TEXT NOT NULL REFERENCES definitions(id), effective TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(task_id, effective))',
          );
        }
        final task = Task(
          id: 'legacy',
          title: 'Original task',
          date: DateTime(2026, 10, 20),
        );
        raw.execute('INSERT INTO definitions VALUES (?, ?)', [
          task.id,
          jsonEncode(task.toJson()),
        ]);
        if (version == 2) {
          raw.execute('INSERT INTO revisions VALUES (?, ?, ?)', [
            task.id,
            dayKey(task.date),
            jsonEncode(task.toJson()),
          ]);
        }
        raw.execute('PRAGMA user_version = $version');
      } finally {
        raw.close();
      }
      final db = CalendarDatabase.file(await prepareDatabaseFile(root));
      try {
        final repo = DriftCalendarRepository(db);
        expect((await repo.tasks()).single.title, 'Original task');
        expect((await repo.tags()).length, 8);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          5,
        );
      } finally {
        await db.close();
      }
      final unchanged = sqlite.sqlite3.open(
        legacy.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        expect(
          unchanged.select('PRAGMA user_version').single.values.single,
          version,
        );
      } finally {
        unchanged.close();
      }
    });
  }

  test(
    'new installs use only Simple Calendar under the supplied roaming root',
    () async {
      final file = await prepareDatabaseFile(root);
      expect(file.path, destination.path);
      expect(await legacy.parent.exists(), isFalse);
      final db = CalendarDatabase.file(file);
      try {
        expect(await DriftCalendarRepository(db).tasks(), isEmpty);
        expect((await DriftCalendarRepository(db).tags()).length, 8);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'migration preserves all backup content and leaves the legacy original untouched',
    () async {
      await legacy.parent.create(recursive: true);
      final oldDb = CalendarDatabase.file(legacy);
      final oldRepo = DriftCalendarRepository(oldDb);
      final day = DateTime(2026, 10, 20);
      final task = Task(
        id: 'task',
        title: 'Synthetic task',
        date: day,
        subtasks: ['Read', 'Practice'],
        tagIds: ['tag-estudio'],
      );
      await oldRepo.saveTask(task, day);
      await oldRepo.saveTask(
        Task.fromJson({...task.toJson(), 'title': 'Revised task'}),
        DateTime(2026, 10, 22),
      );
      await oldRepo.saveOccurrences([
        Occurrence(
          task: task,
          day: day,
          assigned: 540,
          status: TaskStatus.completed,
          checked: [0],
          locked: true,
          exception: true,
        ),
      ]);
      await oldRepo.savePreferences(Preferences(language: 'es', theme: 'dark'));
      final before = jsonDecode(await oldRepo.exportBackup());
      await oldDb.close();
      final originalBytes = await legacy.readAsBytes();

      final migrated = await prepareDatabaseFile(root);
      expect(migrated.path, destination.path);
      expect(await legacy.readAsBytes(), originalBytes);
      var db = CalendarDatabase.file(migrated);
      try {
        expect(
          jsonDecode(await DriftCalendarRepository(db).exportBackup()),
          before,
        );
        await DriftCalendarRepository(
          db,
        ).savePreferences(Preferences(language: 'en'));
      } finally {
        await db.close();
      }
      // A subsequent launch must not reimport the old language or overwrite data.
      expect((await prepareDatabaseFile(root)).path, destination.path);
      db = CalendarDatabase.file(destination);
      try {
        expect(
          (await DriftCalendarRepository(db).preferences()).language,
          'en',
        );
      } finally {
        await db.close();
      }
      expect(await legacy.readAsBytes(), originalBytes);
    },
  );

  test(
    'snapshot includes committed WAL content while preserving the source',
    () async {
      await legacy.parent.create(recursive: true);
      final writer = sqlite.sqlite3.open(legacy.path);
      try {
        writer.execute('PRAGMA journal_mode = WAL');
        writer.execute('PRAGMA wal_autocheckpoint = 0');
        writer.execute('PRAGMA user_version = 3');
        writer.execute(
          'CREATE TABLE sentinel (id TEXT PRIMARY KEY, payload TEXT)',
        );
        writer.execute(
          "INSERT INTO sentinel VALUES ('last', 'committed in WAL')",
        );
        expect(File('${legacy.path}-wal').lengthSync(), greaterThan(0));
        final migrated = await prepareDatabaseFile(root);
        final reader = sqlite.sqlite3.open(migrated.path);
        try {
          expect(
            reader.select('SELECT payload FROM sentinel').single['payload'],
            'committed in WAL',
          );
        } finally {
          reader.close();
        }
        expect(
          writer.select('SELECT count(*) AS n FROM sentinel').single['n'],
          1,
        );
      } finally {
        writer.close();
      }
    },
  );

  test(
    'a corrupt source fails without publishing an empty destination and can be retried',
    () async {
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('not a database');
      await expectLater(
        prepareDatabaseFile(root),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(await destination.exists(), isFalse);
      expect(await legacy.readAsString(), 'not a database');
      expect(
        await destination.parent
            .list()
            .where((e) => p.basename(e.path).startsWith('.migration-'))
            .toList(),
        isEmpty,
      );
      await legacy.delete();
      final db = CalendarDatabase.file(legacy);
      await DriftCalendarRepository(db).preferences();
      await db.close();
      expect(await (await prepareDatabaseFile(root)).exists(), isTrue);
    },
  );

  test(
    'unsupported legacy version is retained without an active destination',
    () async {
      await legacy.parent.create(recursive: true);
      final raw = sqlite.sqlite3.open(legacy.path);
      raw.execute('PRAGMA user_version = 99');
      raw.close();
      await expectLater(
        prepareDatabaseFile(root),
        throwsA(isA<DataDirectoryException>()),
      );
      expect(await destination.exists(), isFalse);
      expect(await legacy.exists(), isTrue);
    },
  );

  test('an existing destination wins over any legacy file', () async {
    await destination.parent.create(recursive: true);
    await destination.writeAsString(
      'existing destination, never replace even if unreadable',
    );
    await legacy.parent.create(recursive: true);
    await legacy.writeAsString('legacy sentinel');
    expect((await prepareDatabaseFile(root)).path, destination.path);
    expect(
      await destination.readAsString(),
      'existing destination, never replace even if unreadable',
    );
    expect(await legacy.readAsString(), 'legacy sentinel');
  });

  test(
    'a blocked destination directory fails without changing legacy data',
    () async {
      await Directory(destination.path).create(recursive: true);
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('legacy sentinel');
      await expectLater(
        prepareDatabaseFile(root),
        throwsA(isA<DataDirectoryException>()),
      );
      expect(await legacy.readAsString(), 'legacy sentinel');
    },
  );

  test('abandoned staging is never treated as the active database', () async {
    final abandoned = Directory(
      p.join(destination.parent.path, '.migration-interrupted'),
    );
    await abandoned.create(recursive: true);
    await File(
      p.join(abandoned.path, 'calendar.sqlite'),
    ).writeAsString('incomplete snapshot');
    expect((await prepareDatabaseFile(root)).path, destination.path);
    expect(await destination.exists(), isFalse);
    expect(
      await File(p.join(abandoned.path, 'calendar.sqlite')).readAsString(),
      'incomplete snapshot',
    );
  });
}
