import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  final day = DateTime(2026, 10, 27);
  final planner = Planner(clock: FixedClock(DateTime(2026, 10, 26, 6)));
  Task task({
    Span? window = const Span(540, 840),
    int duration = 60,
    String id = 'auto',
  }) => Task(
    id: id,
    title: id,
    date: day,
    duration: duration,
    autoWindow: window,
  );
  Plan plan(
    Task t, {
    int? assigned,
    bool locked = false,
    TaskStatus status = TaskStatus.pending,
    Span available = const Span(420, 1320),
  }) => planner.plan(day, available, [
    Occurrence(
      task: t,
      day: day,
      assigned: assigned,
      locked: locked,
      status: status,
    ),
  ]);

  test('optional windows round trip and old tasks remain unrestricted', () {
    expect(Task.fromJson(task().toJson()).autoWindow!.end, 840);
    final legacy = task(window: null);
    expect(legacy.toJson().containsKey('autoWindow'), isFalse);
    expect(plan(Task.fromJson(legacy.toJson())).items.single.start, 420);
  });
  test('invalid windows and non-automatic windows are rejected', () {
    for (final value in [
      [],
      [540],
      [540, 840, 900],
      ['540', 840],
      [540, 540],
      [840, 540],
      [-1, 840],
      [540, 1441],
    ]) {
      expect(
        () => Task.fromJson({...task().toJson(), 'autoWindow': value}),
        throwsFormatException,
      );
    }
    for (final kind in [TaskKind.strict, TaskKind.manual]) {
      expect(
        () => Task.fromJson({...task().toJson(), 'kind': kind.name}),
        throwsFormatException,
      );
    }
  });
  test('first fit respects window, availability and exact end boundary', () {
    expect(plan(task()).items.single.start, 540);
    expect(
      plan(task(), available: const Span(600, 900)).items.single.start,
      600,
    );
    expect(plan(task(window: const Span(780, 840))).items.single.start, 780);
    expect(plan(task(window: const Span(541, 840))).items.single.start, 545);
    expect(
      plan(
        task(window: const Span(1380, 1440)),
        available: const Span(0, 1440),
      ).items.single.start,
      1380,
    );
  });
  test('insufficient or disjoint availability never escapes the window', () {
    for (final available in [
      const Span(420, 540),
      const Span(840, 1320),
      const Span(800, 830),
      const Span(0, 0),
    ]) {
      final result = plan(task(), available: available);
      expect(result.items.single.start, isNull);
      expect(
        result.issues.values.single.single,
        contains('activity time window'),
      );
    }
    expect(plan(task(duration: 301)).items.single.start, isNull);
    expect(plan(task(window: const Span(541, 601))).items.single.start, isNull);
  });
  test('old invalid suggestions move; valid suggestions remain stable', () {
    expect(plan(task(), assigned: 420).items.single.start, 540);
    expect(plan(task(), assigned: 810).items.single.start, 540);
    expect(plan(task(), assigned: 600).items.single.start, 600);
  });
  test('protected and completed blocks remain visible with a warning', () {
    for (final status in [TaskStatus.pending, TaskStatus.completed]) {
      final result = plan(task(), assigned: 420, locked: true, status: status);
      expect(result.items.single.start, 420);
      expect(
        result.issues.values.single.single,
        contains('Outside the activity time window'),
      );
    }
    final nowPlanner = Planner(
      clock: FixedClock(DateTime(2026, 10, 27, 7, 30)),
    );
    final started = nowPlanner.plan(day, const Span(420, 1320), [
      Occurrence(task: task(), day: day, assigned: 420),
    ]);
    expect(started.items.single.start, 420);
    expect(started.issues, isNotEmpty);
  });
  test(
    'skipped blocks do not warn and current time floors window placement',
    () {
      expect(plan(task(), status: TaskStatus.skipped).issues, isEmpty);
      final nowPlanner = Planner(
        clock: FixedClock(DateTime(2026, 10, 27, 10, 2)),
      );
      expect(
        nowPlanner
            .plan(day, const Span(420, 1320), [
              Occurrence(task: task(), day: day),
            ])
            .items
            .single
            .start,
        605,
      );
    },
  );
  test(
    'randomized first-fit schedules obey bounds, avoid conflicts and are deterministic',
    () {
      final random = Random(42);
      for (var run = 0; run < 100; run++) {
        final input = List.generate(12, (i) {
          final start = random.nextInt(1200);
          return Occurrence(
            task: task(
              id: 'task-$i',
              duration: random.nextInt(120) + 1,
              window: Span(start, start + random.nextInt(1440 - start) + 1),
            ),
            day: day,
          );
        });
        final result = planner.plan(day, const Span(420, 1320), input);
        final repeat = planner.plan(
          day,
          const Span(420, 1320),
          input.reversed.toList(),
        );
        expect(
          {for (final o in result.items) o.id: o.start},
          {for (final o in repeat.items) o.id: o.start},
        );
        final spans = <Span>[];
        for (final o in result.items.where((o) => o.start != null)) {
          final span = Span(o.start!, o.start! + o.task.duration);
          expect(o.task.autoWindow!.contains(span), isTrue);
          expect(const Span(420, 1320).contains(span), isTrue);
          expect(spans.any(span.overlaps), isFalse);
          spans.add(span);
        }
      }
    },
  );
  test(
    'assignment rejects out-of-window time without changing stored data',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = CalendarService(repo, planner: planner);
        await service.save(task());
        final occurrence = (await service.day(day)).items.single;
        final before = await repo.exportBackup();
        await expectLater(service.assign(occurrence, 480), throwsStateError);
        await expectLater(service.assign(occurrence, 810), throwsStateError);
        expect(await repo.exportBackup(), before);
        await service.assign(occurrence, 780);
        expect((await repo.occurrences(day)).single.assigned, 780);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'backup v4 preserves windows and rejects downgrade or malformed restore atomically',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = CalendarService(repo, planner: planner);
        await service.save(task());
        await service.day(day);
        final backup = await repo.exportBackup();
        expect(jsonDecode(backup)['version'], 4);
        await repo.importBackup(backup);
        expect((await repo.tasks()).single.autoWindow!.start, 540);
        expect((await repo.occurrences(day)).single.task.autoWindow!.end, 840);
        for (final version in [1, 2, 3]) {
          final downgraded = jsonDecode(backup)..['version'] = version;
          await expectLater(
            repo.importBackup(jsonEncode(downgraded)),
            throwsFormatException,
          );
          expect(await repo.exportBackup(), backup);
        }
        final invalid = jsonDecode(backup);
        invalid['tasks'][0]['autoWindow'] = [840, 540];
        await expectLater(
          repo.importBackup(jsonEncode(invalid)),
          throwsFormatException,
        );
        expect(await repo.exportBackup(), backup);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'v4 database upgrades to v5 without rewriting definitions or execution history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'calendar-window-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = CalendarDatabase.file(file);
      try {
        var repo = DriftCalendarRepository(db);
        final service = CalendarService(repo, planner: planner);
        await service.save(task(window: null));
        await service.day(day);
        final before = await repo.exportBackup();
        final legacyBackup = jsonDecode(before)..['version'] = 3;
        await repo.importBackup(jsonEncode(legacyBackup));
        await db.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('PRAGMA user_version = 4');
        raw.close();
        db = CalendarDatabase.file(file);
        repo = DriftCalendarRepository(db);
        expect(await repo.exportBackup(), before);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          5,
        );
        expect((await repo.tasks()).single.autoWindow, isNull);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'general window edits preserve history, progress, locks and individual exceptions',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final original = Task.fromJson({
          ...task(window: null).toJson(),
          'date': '2026-10-25',
          'repeat': 'daily',
          'subtasks': ['Read'],
        });
        await repo.saveTask(original, DateTime(2026, 10, 25, 6));
        final retained = [
          Occurrence(
            task: original,
            day: DateTime(2026, 10, 25),
            assigned: 420,
            status: TaskStatus.completed,
          ),
          Occurrence(
            task: original,
            day: day,
            assigned: 420,
            locked: true,
            checked: const [0],
          ),
          Occurrence(
            task: original,
            day: DateTime(2026, 10, 28),
            assigned: 480,
            exception: true,
          ),
        ];
        await repo.saveOccurrences(retained);
        final updated = Task.fromJson({
          ...original.toJson(),
          'autoWindow': [540, 840],
        });
        await repo.saveTask(updated, DateTime(2026, 10, 26, 6));
        expect(
          (await repo.allOccurrences()).map((o) => o.toJson()).toList(),
          retained.map((o) => o.toJson()).toList(),
        );
        expect(
          (await repo.tasksForDay(DateTime(2026, 10, 25))).single.autoWindow,
          isNull,
        );
        expect((await repo.tasksForDay(day)).single.autoWindow!.start, 540);
        final service = CalendarService(repo, planner: planner);
        expect(
          (await service.day(DateTime(2026, 10, 29))).items.single.start,
          540,
        );
        final backup = await repo.exportBackup();
        await repo.importBackup(backup);
        expect(await repo.exportBackup(), backup);
      } finally {
        await db.close();
      }
    },
  );
}
