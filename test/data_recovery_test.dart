import 'dart:convert';
import 'dart:io';
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/data/storage_errors.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final _firstDay = DateTime(2026, 10, 19);
final _editTime = DateTime(2026, 10, 23, 12, 30);
final _task = Task(
  id: 'routine',
  title: 'Rutina',
  date: _firstDay,
  repeat: Repeat.daily,
  subtasks: const ['Leer', 'Practicar'],
);
final _states = [
  Occurrence(
    task: _task,
    day: _firstDay,
    status: TaskStatus.completed,
    checked: [0, 1],
    assigned: 480,
  ),
  Occurrence(
    task: _task,
    day: DateTime(2026, 10, 20),
    status: TaskStatus.skipped,
    assigned: 540,
  ),
  Occurrence(
    task: _task,
    day: DateTime(2026, 10, 21),
    assigned: 600,
    locked: true,
  ),
  Occurrence(
    task: Task.fromJson({..._task.toJson(), 'title': 'Excepción'}),
    day: DateTime(2026, 10, 22),
    checked: [1],
    exception: true,
    assigned: 700,
  ),
];
final _preferences = Preferences(
  theme: 'dark',
  availability: {
    for (var d = 1; d <= 7; d++)
      d: d == 7 ? const Span(0, 0) : const Span(480, 1320),
  },
);

void _createLegacy(File file, {bool malformed = false, int version = 1}) {
  final raw = sqlite.sqlite3.open(file.path);
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
    raw.execute('INSERT INTO definitions VALUES (?, ?)', [
      _task.id,
      malformed ? '{broken' : jsonEncode(_task.toJson()),
    ]);
    for (final o in _states) {
      raw.execute('INSERT INTO executions VALUES (?, ?, ?)', [
        o.task.id,
        dayKey(o.day),
        jsonEncode(o.toJson()),
      ]);
    }
    raw.execute('INSERT INTO settings VALUES (?, ?)', [
      'preferences',
      jsonEncode(_preferences.toJson()),
    ]);
    raw.execute('PRAGMA user_version = $version');
  } finally {
    raw.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'simple-calendar-recovery-',
    );
    file = File('${directory.path}/isolated.sqlite');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'v1 disk update preserves every execution, preferences, revisions and reopening',
    () async {
      _createLegacy(file);
      final migrated = CalendarDatabase.file(file);
      String backup;
      try {
        final repo = DriftCalendarRepository(migrated);
        expect((await repo.tasks()).single.toJson(), _task.toJson());
        expect(
          (await repo.allOccurrences()).map((o) => o.toJson()),
          _states.map((o) => o.toJson()),
        );
        expect((await repo.preferences()).toJson(), _preferences.toJson());
        expect(
          (await repo.tasksForDay(_firstDay)).single.toJson(),
          _task.toJson(),
        );
        expect(
          (await migrated.customSelect('PRAGMA foreign_key_check').get()),
          isEmpty,
        );
        final service = CalendarService(
          repo,
          planner: Planner(clock: FixedClock(_editTime)),
        );
        await service.save(
          Task.fromJson({..._task.toJson(), 'title': 'Actualizada'}),
        );
        expect((await repo.tasksForDay(_firstDay)).single.title, 'Rutina');
        expect(
          (await repo.tasksForDay(DateTime(2026, 10, 24))).single.title,
          'Actualizada',
        );
        backup = await repo.exportBackup();
      } finally {
        await migrated.close();
      }
      final reopened = CalendarDatabase.file(file);
      try {
        final repo = DriftCalendarRepository(reopened);
        expect(await repo.exportBackup(), backup);
        expect(
          (await repo.allOccurrences()).map((o) => o.toJson()),
          _states.map((o) => o.toJson()),
        );
        await repo.importBackup(backup);
        expect(await repo.exportBackup(), backup);
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'a migration error leaves no partial schema and keeps the original database',
    () async {
      _createLegacy(file, malformed: true);
      final db = CalendarDatabase.file(file);
      try {
        await expectLater(
          DriftCalendarRepository(db).preferences(),
          throwsA(anything),
        );
      } finally {
        await db.close();
      }
      final raw = sqlite.sqlite3.open(file.path);
      try {
        expect(raw.userVersion, 1);
        expect(
          raw.select('SELECT payload FROM definitions').single['payload'],
          '{broken',
        );
        expect(
          raw.select("SELECT name FROM sqlite_master WHERE name = 'revisions'"),
          isEmpty,
        );
        expect(
          raw.select('SELECT COUNT(*) AS n FROM executions').single['n'],
          _states.length,
        );
        // Repair only the artificial fixture and retry the same migration.
        raw.execute('UPDATE definitions SET payload = ?', [
          jsonEncode(_task.toJson()),
        ]);
      } finally {
        raw.close();
      }
      final retry = CalendarDatabase.file(file);
      try {
        expect(
          (await DriftCalendarRepository(
            retry,
          ).tasksForDay(_firstDay)).single.id,
          _task.id,
        );
      } finally {
        await retry.close();
      }
    },
  );

  test(
    'an unsupported database version is rejected without rewriting it',
    () async {
      _createLegacy(file, version: 99);
      final before = await file.readAsBytes();
      final db = CalendarDatabase.file(file);
      try {
        await expectLater(
          DriftCalendarRepository(db).preferences(),
          throwsA(anything),
        );
      } finally {
        await db.close();
      }
      expect(await file.readAsBytes(), before);
    },
  );

  Future<CalendarDatabase> seed() async {
    final db = CalendarDatabase.file(file);
    final repo = DriftCalendarRepository(db);
    await repo.saveTask(_task, _editTime);
    await repo.saveOccurrences(_states);
    await repo.savePreferences(_preferences);
    return db;
  }

  for (final variant in [
    'future-version',
    'wrong-format',
    'orphan',
    'duplicate-execution',
    'bad-progress',
    'bad-preferences',
  ]) {
    test(
      'invalid backup ($variant) preserves all existing disk data',
      () async {
        final db = await seed();
        try {
          final repo = DriftCalendarRepository(db);
          final original = await repo.exportBackup();
          final candidate = jsonDecode(original) as Map<String, dynamic>;
          switch (variant) {
            case 'future-version':
              candidate['version'] = 99;
            case 'wrong-format':
              candidate['format'] = 'other-calendar';
            case 'orphan':
              candidate['occurrences'][0]['task']['id'] = 'missing';
            case 'duplicate-execution':
              candidate['occurrences'].add(candidate['occurrences'][0]);
            case 'bad-progress':
              candidate['occurrences'][0]['checked'] = [100];
            case 'bad-preferences':
              candidate['preferences']['theme'] = 'unknown';
          }
          await expectLater(
            repo.importBackup(jsonEncode(candidate)),
            throwsFormatException,
          );
          expect(await repo.exportBackup(), original);
        } finally {
          await db.close();
        }
      },
    );
  }

  test(
    'a late restore write error rolls back and survives closing/reopening',
    () async {
      final db = await seed();
      String original;
      try {
        final repo = DriftCalendarRepository(db);
        original = await repo.exportBackup();
        final candidate = jsonDecode(original) as Map<String, dynamic>;
        candidate['tasks'][0]['title'] = 'Restaurada';
        candidate['revisions'][0]['task']['title'] = 'Restaurada';
        await db.customStatement(
          "CREATE TRIGGER fail_restore BEFORE INSERT ON settings BEGIN SELECT RAISE(ABORT, 'injected restore failure'); END",
        );
        await expectLater(
          repo.importBackup(jsonEncode(candidate)),
          throwsA(anything),
        );
        expect(await repo.exportBackup(), original);
        await db.customStatement('DROP TRIGGER fail_restore');
      } finally {
        await db.close();
      }
      final reopened = CalendarDatabase.file(file);
      try {
        expect(
          await DriftCalendarRepository(reopened).exportBackup(),
          original,
        );
      } finally {
        await reopened.close();
      }
    },
  );

  test('failed definition revision and batch writes are atomic', () async {
    final db = await seed();
    try {
      final repo = DriftCalendarRepository(db);
      final original = await repo.exportBackup();
      await db.customStatement(
        "CREATE TRIGGER fail_revision BEFORE INSERT ON revisions BEGIN SELECT RAISE(ABORT, 'injected revision failure'); END",
      );
      await expectLater(
        repo.saveTask(
          Task.fromJson({..._task.toJson(), 'title': 'Rejected'}),
          _editTime,
        ),
        throwsA(anything),
      );
      expect(await repo.exportBackup(), original);
      await db.customStatement('DROP TRIGGER fail_revision');
      final orphan = Task.fromJson({..._task.toJson(), 'id': 'missing'});
      await expectLater(
        repo.saveOccurrences([
          _states.first.copy(checked: []),
          Occurrence(task: orphan, day: _firstDay),
        ]),
        throwsA(anything),
      );
      expect(await repo.exportBackup(), original);
    } finally {
      await db.close();
    }
  });

  test('SQLite full error rolls back a definition change', () async {
    final db = await seed();
    try {
      final repo = DriftCalendarRepository(db);
      final original = await repo.exportBackup();
      final count = (await db.customSelect('PRAGMA page_count').getSingle())
          .read<int>('page_count');
      await db.customStatement('PRAGMA max_page_count = ${count + 1}');
      Object? storageFailure;
      await expectLater(
        repo
            .saveTask(
              Task.fromJson({
                ..._task.toJson(),
                'description': 'x' * (2 * 1024 * 1024),
              }),
              _editTime,
            )
            .catchError((Object error) {
              storageFailure = error;
              throw error;
            }),
        throwsA(
          isA<DriftRemoteException>().having(
            (e) => e.remoteCause,
            'remote cause',
            isA<sqlite.SqliteException>().having(
              (e) => e.resultCode,
              'SQLITE_FULL',
              13,
            ),
          ),
        ),
      );
      expect(storageErrorMessage(storageFailure!), contains('space'));
      expect(storageErrorMessage(storageFailure!), isNot(contains('INSERT')));
      expect(await repo.exportBackup(), original);
    } finally {
      await db.close();
    }
  });

  test(
    'read-only opening reports a write error without changing data',
    () async {
      final seeded = await seed();
      final original = await DriftCalendarRepository(seeded).exportBackup();
      await seeded.close();
      final raw = sqlite.sqlite3.open(
        file.path,
        mode: sqlite.OpenMode.readOnly,
      );
      final readonly = CalendarDatabase(NativeDatabase.opened(raw));
      try {
        final repo = DriftCalendarRepository(readonly);
        expect(await repo.exportBackup(), original);
        await expectLater(
          repo.savePreferences(Preferences(theme: 'light')),
          throwsA(
            isA<sqlite.SqliteException>().having(
              (e) => e.resultCode,
              'SQLITE_READONLY',
              8,
            ),
          ),
        );
        final controller = CalendarController(
          CalendarService(repo, planner: Planner(clock: FixedClock(_editTime))),
        );
        try {
          await controller.refresh();
          await controller.run(
            () => repo.savePreferences(Preferences(theme: 'light')),
          );
          expect(controller.loading, false);
          expect(controller.error, contains('read-only'));
          expect(controller.error, isNot(contains('INSERT')));
        } finally {
          controller.dispose();
        }
        expect(await repo.exportBackup(), original);
      } finally {
        await readonly.close();
      }
    },
  );

  test(
    'a corrupt database is rejected with a clear error and never recreated',
    () async {
      await file.writeAsString('not a SQLite database', flush: true);
      final original = await file.readAsBytes();
      final db = CalendarDatabase.file(file);
      try {
        Object? failure;
        try {
          await DriftCalendarRepository(db).preferences();
        } catch (error) {
          failure = error;
        }
        expect(failure, isNotNull);
        expect(
          storageErrorMessage(failure!),
          contains('Keep the original file'),
        );
      } finally {
        await db.close();
      }
      expect(await file.readAsBytes(), original);
    },
  );
}
