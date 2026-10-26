import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';

void main() {
  // Independent executors are intentional in persistence and migration tests.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final monday = DateTime(2026, 10, 19);
  final today = DateTime(2026, 10, 21);
  late CalendarDatabase db;
  late DriftCalendarRepository repo;
  late CalendarService service;
  Task task({
    Repeat repeat = Repeat.daily,
    String title = 'Estudiar',
    TaskKind kind = TaskKind.automatic,
  }) => Task(
    id: 'routine',
    title: title,
    date: monday,
    repeat: repeat,
    subtasks: ['Leer', 'Practicar'],
    kind: kind,
  );
  setUp(() {
    db = CalendarDatabase(NativeDatabase.memory());
    repo = DriftCalendarRepository(db);
    service = CalendarService(repo, planner: Planner(clock: FixedClock(today)));
  });
  tearDown(() => db.close());
  test('save, read task, description and subtasks', () async {
    await service.save(task());
    expect((await repo.tasks()).single.toJson(), task().toJson());
  });
  test(
    'editing a future definition does not resurrect its initial revision',
    () async {
      final future = Task(
        id: 'future',
        title: 'Original',
        date: DateTime(2026, 11, 1),
        repeat: Repeat.daily,
      );
      await service.save(future);
      await service.save(
        Task.fromJson({...future.toJson(), 'title': 'Actualizada'}),
      );
      expect(
        (await service.day(DateTime(2026, 11, 2))).items.single.task.title,
        'Actualizada',
      );
    },
  );
  test('strict collision detects a routine that starts next year', () async {
    await service.save(
      Task(
        id: 'later',
        title: 'Futura',
        date: DateTime(2027, 1, 4),
        kind: TaskKind.strict,
        repeat: Repeat.daily,
      ),
    );
    expect(
      await service.conflicts(
        Task(
          id: 'new',
          title: 'Diaria',
          date: today,
          kind: TaskKind.strict,
          repeat: Repeat.daily,
        ),
      ),
      isNotEmpty,
    );
  });
  test('backup rejects invalid dates and inconsistent revisions', () async {
    await service.save(task());
    final data = jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
    data['tasks'][0]['date'] = '2026-02-31';
    await expectLater(
      repo.importBackup(jsonEncode(data)),
      throwsFormatException,
    );
    data['tasks'][0]['date'] = dayKey(monday);
    data['tasks'][0]['title'] = 'Incoherente';
    await expectLater(
      repo.importBackup(jsonEncode(data)),
      throwsFormatException,
    );
    expect((await repo.tasks()).single.title, 'Estudiar');
  });
  test('daily, weekday, weekly and selected recurrences', () {
    expect(task().occurs(DateTime(2026, 10, 25)), true);
    expect(task(repeat: Repeat.weekdays).occurs(DateTime(2026, 10, 25)), false);
    expect(task(repeat: Repeat.weekly).occurs(DateTime(2026, 10, 26)), true);
    expect(task(repeat: Repeat.weekly).occurs(today), false);
    final selected = Task.fromJson({
      ...task().toJson(),
      'repeat': 'selected',
      'weekdays': [1, 3],
    });
    expect(selected.occurs(today), true);
    expect(selected.occurs(DateTime(2026, 10, 20)), false);
    expect(task(repeat: Repeat.once).occurs(today), false);
  });
  test(
    'independent completion, skip, checkbox toggle and no duplicates',
    () async {
      await service.save(task());
      final a = (await service.day(monday)).items.single;
      await service.update(a.copy(status: TaskStatus.completed, checked: [0]));
      final b = (await service.day(today)).items.single;
      expect(b.status, TaskStatus.pending);
      expect(b.checked, isEmpty);
      await service.update(b.copy(status: TaskStatus.skipped));
      await service.day(monday);
      await service.day(monday);
      expect(
        (await repo.occurrences(monday)).single.status,
        TaskStatus.completed,
      );
      expect((await repo.occurrences(today)).single.status, TaskStatus.skipped);
      await service.update(a.copy(checked: []));
      expect((await repo.occurrences(monday)).single.checked, isEmpty);
    },
  );
  test('general edit preserves even previously unvisited history', () async {
    await service.save(task());
    await service.save(task(title: 'Nuevo nombre'));
    expect((await service.day(monday)).items.single.task.title, 'Estudiar');
    expect((await service.day(today)).items.single.task.title, 'Nuevo nombre');
  });
  test(
    'single occurrence exception survives recurrence regeneration',
    () async {
      await service.save(task());
      final o = (await service.day(today)).items.single;
      await service.update(
        o.copy(task: task(title: 'Solo hoy'), exception: true),
      );
      await service.save(task(title: 'Regla nueva'));
      expect((await service.day(today)).items.single.task.title, 'Solo hoy');
      expect(
        (await service.day(DateTime(2026, 10, 22))).items.single.task.title,
        'Regla nueva',
      );
    },
  );
  test(
    'manual assignment is persistent and displaces automatic suggestion',
    () async {
      await service.save(task(kind: TaskKind.manual));
      await service.save(Task(id: 'auto', title: 'Auto', date: today));
      final manual = (await service.day(
        today,
      )).items.singleWhere((o) => o.task.id == 'routine');
      await service.assign(manual, 480);
      final planned = await service.day(today);
      expect(
        planned.items.singleWhere((o) => o.task.id == 'routine').locked,
        true,
      );
      expect(
        planned.items.singleWhere((o) => o.task.id == 'auto').assigned,
        540,
      );
      await expectLater(service.assign(manual, 10), throwsStateError);
    },
  );
  test('strict conflict warning and protected assignment rejection', () async {
    await service.save(
      Task(
        id: 'strict',
        title: 'Gym',
        kind: TaskKind.strict,
        date: today,
        start: 540,
      ),
    );
    expect(
      await service.conflicts(
        Task(
          id: 'other',
          title: 'Other',
          date: today,
          kind: TaskKind.strict,
          start: 560,
        ),
      ),
      isNotEmpty,
    );
    await service.save(task(kind: TaskKind.manual));
    final o = (await service.day(
      today,
    )).items.singleWhere((o) => o.task.id == 'routine');
    await expectLater(service.assign(o, 540), throwsStateError);
  });
  test(
    'backup round trip including history, locked assignment and preferences',
    () async {
      await service.save(task());
      final o = (await service.day(today)).items.single;
      await service.update(
        o.copy(
          assigned: 600,
          locked: true,
          checked: [1],
          status: TaskStatus.completed,
        ),
      );
      await repo.savePreferences(Preferences(theme: 'dark'));
      final backup = await repo.exportBackup();
      await repo.importBackup(backup);
      final restored = (await service.day(today)).items.single;
      expect(restored.checked, [1]);
      expect(restored.locked, true);
      expect(restored.status, TaskStatus.completed);
      expect((await repo.preferences()).theme, 'dark');
      expect(jsonDecode(await repo.exportBackup()), jsonDecode(backup));
    },
  );
  test('invalid and duplicate backup never replace existing data', () async {
    await service.save(task());
    final backup =
        jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
    backup['tasks'].add(backup['tasks'].first);
    await expectLater(
      repo.importBackup(jsonEncode(backup)),
      throwsFormatException,
    );
    await expectLater(repo.importBackup('{broken'), throwsFormatException);
    expect((await repo.tasks()).single.title, 'Estudiar');
  });
  test('foreign keys reject orphan occurrences', () async {
    await expectLater(
      repo.saveOccurrences([Occurrence(task: task(), day: today)]),
      throwsA(anything),
    );
    expect(await repo.allOccurrences(), isEmpty);
  });
  test('disk data survives closing and reopening SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('calendar-test-');
    final file = File('${dir.path}/calendar.sqlite');
    final first = CalendarDatabase(NativeDatabase(file));
    final r = DriftCalendarRepository(first);
    await r.saveTask(task(), today);
    await r.saveOccurrences([
      Occurrence(
        task: task(),
        day: today,
        status: TaskStatus.completed,
        checked: [0],
      ),
    ]);
    await first.close();
    final second = CalendarDatabase(NativeDatabase(file));
    expect(
      (await DriftCalendarRepository(second).occurrences(today)).single.checked,
      [0],
    );
    await second.close();
    await dir.delete(recursive: true);
  });
  test('version 1 database migrates to 3 without losing data', () async {
    final raw = sqlite.sqlite3.openInMemory();
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
      'routine',
      jsonEncode(task().toJson()),
    ]);
    raw.execute('PRAGMA user_version = 1');
    final legacy = CalendarDatabase(NativeDatabase.opened(raw));
    final rows = await legacy.select(legacy.revisions).get();
    expect(rows.single.taskId, 'routine');
    await legacy.close();
  });
}
