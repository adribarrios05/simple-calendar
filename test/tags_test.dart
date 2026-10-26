import 'dart:convert';
import 'dart:io';
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/domain/tag.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  // The migration fixture intentionally uses independent in-memory/disk executors.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final first = DateTime(2026, 10, 19);
  final now = DateTime(2026, 10, 23, 10);
  final tomorrow = DateTime(2026, 10, 24);
  const custom = Tag(id: 'custom', name: 'Música', color: 0xff91c7b1);
  Task task({List<String> tags = const ['tag-trabajo', 'tag-estudio']}) => Task(
    id: 'routine',
    title: 'Rutina',
    date: first,
    repeat: Repeat.daily,
    tagIds: tags,
    subtasks: const ['Paso'],
  );
  late CalendarDatabase db;
  late DriftCalendarRepository repo;
  late CalendarService service;
  setUp(() {
    db = CalendarDatabase(NativeDatabase.memory());
    repo = DriftCalendarRepository(db);
    service = CalendarService(repo, planner: Planner(clock: FixedClock(now)));
  });
  tearDown(() => db.close());

  test(
    'fresh catalogue, create, rename, recolor and case insensitive names',
    () async {
      expect(
        (await repo.tags()).map((t) => t.id),
        defaultTags.map((t) => t.id),
      );
      await repo.saveTag(custom);
      await repo.saveTag(custom.copy(name: 'Piano', color: tagPalette.last));
      expect((await repo.tags()).last.name, 'Piano');
      expect((await repo.tags()).last.color, tagPalette.last);
      for (final name in ['trabajo', 'TRABAJO', 'pIaNo']) {
        await expectLater(
          repo.saveTag(Tag(id: 'other', name: name, color: custom.color)),
          throwsFormatException,
        );
      }
      await expectLater(
        repo.saveTag(custom.copy(name: '   ')),
        throwsFormatException,
      );
      await expectLater(
        repo.archiveTag(defaultTags.first.id),
        throwsFormatException,
      );
      await repo.saveTag(defaultTags.first.copy(name: 'Profesional'));
      expect((await repo.tags()).first.id, defaultTags.first.id);
    },
  );

  test(
    'multiple memberships validate duplicates and unknown references atomically',
    () async {
      await service.save(task());
      expect((await repo.tasks()).single.tagIds, task().tagIds);
      await expectLater(
        service.save(task(tags: ['missing'])),
        throwsFormatException,
      );
      await expectLater(
        service.save(task(tags: ['tag-estudio', 'tag-estudio'])),
        throwsFormatException,
      );
      expect((await repo.tasks()).single.tagIds, task().tagIds);
      await expectLater(
        repo.saveOccurrences([
          Occurrence(
            task: task(tags: ['missing']),
            day: first,
          ),
        ]),
        throwsFormatException,
      );
      expect(await repo.allOccurrences(), isEmpty);
    },
  );

  test(
    'tag only definition edits preserve schedules and protected snapshots',
    () async {
      await service.save(task());
      final states = [
        Occurrence(
          task: task(),
          day: first,
          status: TaskStatus.completed,
          assigned: 480,
          checked: [0],
        ),
        Occurrence(
          task: task(),
          day: DateTime(2026, 10, 20),
          status: TaskStatus.skipped,
        ),
        Occurrence(task: task(), day: now, assigned: 540), // already started
        Occurrence(task: task(), day: tomorrow, assigned: 610, locked: true),
        Occurrence(
          task: task(),
          day: DateTime(2026, 10, 25),
          assigned: 700,
          exception: true,
        ),
        Occurrence(
          task: task(),
          day: DateTime(2026, 10, 26),
          assigned: 800,
          checked: [0],
        ),
        Occurrence(task: task(), day: DateTime(2026, 10, 27), assigned: 900),
      ];
      await repo.saveOccurrences(states);
      await service.save(task(tags: ['tag-personal']));
      final saved = await repo.allOccurrences();
      for (final old in states.take(6)) {
        expect(saved.singleWhere((o) => o.id == old.id).toJson(), old.toJson());
      }
      final changed = saved.singleWhere((o) => o.id == states.last.id);
      expect(changed.assigned, 900);
      expect(changed.task.tagIds, ['tag-personal']);
      expect((await repo.tasksForDay(first)).single.tagIds, task().tagIds);
      expect((await repo.tasksForDay(tomorrow)).single.tagIds, [
        'tag-personal',
      ]);
      expect(
        (await service.day(DateTime(2026, 10, 28))).items.single.task.tagIds,
        ['tag-personal'],
      );
    },
  );

  test(
    'individual membership changes retain state and do not alter definition or other days',
    () async {
      await service.save(task());
      final original = Occurrence(
        task: task(),
        day: first,
        status: TaskStatus.completed,
        checked: [0],
        assigned: 650,
        locked: true,
      );
      final other = Occurrence(task: task(), day: tomorrow, assigned: 800);
      await repo.saveOccurrences([original, other]);
      final changed = original.copy(
        task: task(tags: ['tag-salud']),
        exception: true,
      );
      await service.update(changed);
      expect((await repo.occurrences(first)).single.toJson(), changed.toJson());
      expect(
        (await repo.occurrences(tomorrow)).single.toJson(),
        other.toJson(),
      );
      expect((await repo.tasks()).single.toJson(), task().toJson());
      await service.save(
        Task.fromJson({
          ...task().toJson(),
          'title': 'Nueva',
          'tagIds': ['tag-hogar'],
        }),
      );
      expect((await repo.occurrences(first)).single.toJson(), changed.toJson());
    },
  );

  test(
    'global metadata and logical deletion never rewrite tasks or executions',
    () async {
      await repo.saveTag(custom);
      await service.save(task(tags: [custom.id]));
      await service.day(first);
      final before = (await repo.allOccurrences())
          .map((o) => o.toJson())
          .toList();
      expect(await repo.tagInUse(custom.id), true);
      await repo.saveTag(custom.copy(name: 'Lectura', color: tagPalette.first));
      await repo.archiveTag(custom.id);
      expect((await repo.tags()).last.archived, true);
      expect((await repo.tasks()).single.tagIds, [custom.id]);
      expect((await repo.allOccurrences()).map((o) => o.toJson()), before);
      await expectLater(
        repo.saveTag(Tag(id: 'another', name: 'lectura', color: custom.color)),
        throwsFormatException,
      );
      final backup = await repo.exportBackup();
      await repo.importBackup(backup);
      expect(await repo.exportBackup(), backup);
    },
  );

  test(
    'planner outputs, assignments, conflicts and free spans ignore tags',
    () {
      final planner = Planner(clock: FixedClock(now));
      final plain = [
        Occurrence(
          task: task(tags: []),
          day: tomorrow,
        ),
        Occurrence(
          task: Task(
            id: 'fixed',
            title: 'Fija',
            date: tomorrow,
            kind: TaskKind.strict,
            start: 600,
          ),
          day: tomorrow,
        ),
      ];
      final tagged = plain
          .map(
            (o) => o.copy(
              task: Task.fromJson({
                ...o.task.toJson(),
                'tagIds': ['tag-ocio', 'tag-estudio'],
              }),
            ),
          )
          .toList();
      final a = planner.plan(tomorrow, const Span(480, 1320), plain);
      final b = planner.plan(tomorrow, const Span(480, 1320), tagged);
      expect(
        b.items.map((o) => [o.id, o.start, o.locked, o.status, o.checked]),
        a.items.map((o) => [o.id, o.start, o.locked, o.status, o.checked]),
      );
      expect(b.issues, a.issues);
      expect(
        b.free.map((s) => [s.start, s.end]),
        a.free.map((s) => [s.start, s.end]),
      );
    },
  );

  test('single tag filters include untagged and clearing', () {
    expect(matchesTag(task().tagIds, null), true);
    expect(matchesTag(task().tagIds, 'tag-estudio'), true);
    expect(matchesTag(task().tagIds, 'tag-hogar'), false);
    expect(matchesTag(task().tagIds, ''), false);
    expect(matchesTag([], ''), true);
  });

  test('backup v2 round trip and old v1 without tag fields', () async {
    await repo.saveTag(custom);
    await service.save(task(tags: [custom.id, 'tag-estudio']));
    await service.day(first);
    final backup = await repo.exportBackup();
    await repo.importBackup(backup);
    expect(await repo.exportBackup(), backup);
    final old = jsonDecode(backup) as Map<String, dynamic>;
    old['version'] = 1;
    old.remove('tags');
    for (final t in old['tasks']) {
      (t as Map).remove('tagIds');
    }
    for (final r in old['revisions']) {
      (r['task'] as Map).remove('tagIds');
    }
    for (final o in old['occurrences']) {
      (o['task'] as Map).remove('tagIds');
    }
    await repo.importBackup(jsonEncode(old));
    expect((await repo.tags()).length, 8);
    expect((await repo.tasks()).single.tagIds, isEmpty);
    expect((await repo.allOccurrences()).single.task.tagIds, isEmpty);
  });

  for (final variant in [
    'duplicate-id',
    'duplicate-name',
    'unknown-task-tag',
    'unknown-revision-tag',
    'unknown-occurrence-tag',
    'missing-default',
    'archived-default',
    'bad-id',
    'duplicate-membership',
    'null-membership',
  ]) {
    test('invalid tag backup $variant leaves all data intact', () async {
      await service.save(task());
      await service.day(first);
      final before = await repo.exportBackup();
      final j = jsonDecode(before) as Map<String, dynamic>;
      switch (variant) {
        case 'duplicate-id':
          j['tags'].add(j['tags'].first);
        case 'duplicate-name':
          j['tags'][1]['name'] = 'TRABAJO';
        case 'unknown-task-tag':
          j['tasks'][0]['tagIds'] = ['missing'];
        case 'unknown-revision-tag':
          j['revisions'][0]['task']['tagIds'] = ['missing'];
        case 'unknown-occurrence-tag':
          j['occurrences'][0]['task']['tagIds'] = ['missing'];
        case 'missing-default':
          j['tags'].removeLast();
        case 'archived-default':
          j['tags'][0]['archived'] = true;
        case 'bad-id':
          j['tags'][0]['id'] = '../invalid';
        case 'duplicate-membership':
          j['occurrences'][0]['task']['tagIds'] = ['tag-ocio', 'tag-ocio'];
        case 'null-membership':
          j['occurrences'][0]['task']['tagIds'] = null;
      }
      await expectLater(repo.importBackup(jsonEncode(j)), throwsA(anything));
      expect(await repo.exportBackup(), before);
    });
  }

  test(
    'schema v2 migration and close/reopen retain legacy data and memberships',
    () async {
      final dir = await Directory.systemTemp.createTemp('calendar-tags-');
      final file = File('${dir.path}/test.sqlite');
      final raw = sqlite.sqlite3.open(file.path);
      final oldTask = task(tags: []).toJson()..remove('tagIds');
      raw.execute(
        'CREATE TABLE definitions (id TEXT NOT NULL PRIMARY KEY, payload TEXT NOT NULL)',
      );
      raw.execute(
        'CREATE TABLE revisions (task_id TEXT NOT NULL REFERENCES definitions(id), effective TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(task_id,effective))',
      );
      raw.execute(
        'CREATE TABLE executions (task_id TEXT NOT NULL REFERENCES definitions(id), day TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(task_id,day))',
      );
      raw.execute(
        'CREATE TABLE settings (id TEXT NOT NULL PRIMARY KEY, payload TEXT NOT NULL)',
      );
      raw.execute('INSERT INTO definitions VALUES (?,?)', [
        'routine',
        jsonEncode(oldTask),
      ]);
      raw.execute('INSERT INTO revisions VALUES (?,?,?)', [
        'routine',
        dayKey(first),
        jsonEncode(oldTask),
      ]);
      final historic = Occurrence(
        task: task(tags: []),
        day: first,
        status: TaskStatus.completed,
        locked: true,
        assigned: 540,
        checked: [0],
      );
      final historicJson = historic.toJson();
      (historicJson['task'] as Map).remove('tagIds');
      raw.execute('INSERT INTO executions VALUES (?,?,?)', [
        'routine',
        dayKey(first),
        jsonEncode(historicJson),
      ]);
      raw.execute('PRAGMA user_version = 2');
      raw.close();
      var disk = CalendarDatabase.file(file);
      try {
        var diskRepo = DriftCalendarRepository(disk);
        expect((await diskRepo.tags()).length, 8);
        expect((await diskRepo.tasks()).single.tagIds, isEmpty);
        expect(
          (await diskRepo.allOccurrences()).single.toJson(),
          historic.toJson(),
        );
        await diskRepo.saveTag(custom);
        await diskRepo.saveTask(task(tags: [custom.id, 'tag-hogar']), now);
        await disk.close();
        disk = CalendarDatabase.file(file);
        diskRepo = DriftCalendarRepository(disk);
        expect((await diskRepo.tasks()).single.tagIds, [
          custom.id,
          'tag-hogar',
        ]);
        expect((await diskRepo.tags()).last.toJson(), custom.toJson());
        expect(
          (await diskRepo.allOccurrences()).single.toJson(),
          historic.toJson(),
        );
        expect(
          (await disk.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          5,
        );
      } finally {
        await disk.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
