import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 21);
  final now = DateTime(2026, 10, 21, 12, 30);
  final planner = Planner(clock: FixedClock(now));
  Task task(String id, {TaskKind kind = TaskKind.automatic}) => Task(
    id: id,
    title: id,
    date: day,
    kind: kind,
    start: 720,
    repeat: Repeat.daily,
    subtasks: const ['Leer', 'Practicar'],
  );

  test(
    'started suggestions keep their time and report protected conflicts',
    () {
      final automatic = Occurrence(task: task('auto'), day: day, assigned: 720);
      final strict = Occurrence(
        task: task('strict', kind: TaskKind.strict),
        day: day,
      );
      final plan = planner.plan(day, const Span(480, 1320), [
        automatic,
        strict,
      ]);
      expect(
        plan.items.singleWhere((o) => o.task.id == 'auto').toJson(),
        automatic.toJson(),
      );
      expect(plan.issues.keys, unorderedEquals([automatic.id, strict.id]));
      expect(plan.free.first.start, 780);
      final again = planner.plan(day, const Span(480, 1320), plan.items);
      expect(
        again.items.map((o) => o.toJson()),
        plan.items.map((o) => o.toJson()),
      );
      expect(again.issues.keys, unorderedEquals(plan.issues.keys));
    },
  );

  test(
    'availability changes preserve started and elapsed suggestions with warnings',
    () {
      for (final start in [600, 720, 750]) {
        final o = Occurrence(task: task('auto'), day: day, assigned: start);
        final plan = planner.plan(day, const Span(780, 1320), [o]);
        expect(plan.items.single.toJson(), o.toJson());
        expect(
          plan.issues[o.id],
          contains('Outside availability. Move or unlock the block.'),
        );
      }
    },
  );

  test('future suggestions still move when their availability changes', () {
    final o = Occurrence(task: task('auto'), day: day, assigned: 760);
    final plan = planner.plan(day, const Span(780, 1320), [o]);
    expect(plan.items.single.start, 780);
    expect(plan.issues, isEmpty);
  });

  group('stored execution preservation', () {
    late CalendarDatabase db;
    late DriftCalendarRepository repo;
    late CalendarService service;
    setUp(() {
      db = CalendarDatabase(NativeDatabase.memory());
      repo = DriftCalendarRepository(db);
      service = CalendarService(repo, planner: planner);
    });
    tearDown(() => db.close());

    test(
      'renaming preserves started snapshots and updates future unprotected ones',
      () async {
        final t = task('auto');
        await service.save(t);
        final started = Occurrence(task: t, day: day, assigned: 720);
        await service.update(started);
        final tomorrow = DateTime(2026, 10, 22);
        await service.day(tomorrow);
        await service.save(
          Task.fromJson({...t.toJson(), 'title': 'Actualizada'}),
        );
        expect((await repo.occurrences(day)).single.toJson(), started.toJson());
        expect(
          (await service.day(day)).items.single.toJson(),
          started.toJson(),
        );
        expect(
          (await service.day(tomorrow)).items.single.task.title,
          'Actualizada',
        );
        expect((await repo.tasks()).single.title, 'Actualizada');
      },
    );

    test(
      'a start at the current minute is preserved on definition edit',
      () async {
        final t = task('auto');
        await service.save(t);
        final started = Occurrence(task: t, day: day, assigned: 750);
        await service.update(started);
        await service.save(Task.fromJson({...t.toJson(), 'duration': 90}));
        expect((await repo.occurrences(day)).single.toJson(), started.toJson());
      },
    );

    test(
      'future strict snapshots can still follow an explicit definition edit',
      () async {
        final t = task('strict', kind: TaskKind.strict);
        await service.save(t);
        final tomorrow = DateTime(2026, 10, 22);
        await service.day(tomorrow);
        await service.save(Task.fromJson({...t.toJson(), 'start': 840}));
        expect((await service.day(tomorrow)).items.single.start, 840);
      },
    );

    test(
      'manual placement cannot displace an already started suggestion',
      () async {
        final t = task('auto');
        await service.save(t);
        final started = Occurrence(task: t, day: day, assigned: 720);
        await service.update(started);
        final manualTask = task('manual', kind: TaskKind.manual);
        await service.save(manualTask);
        final manual = (await service.day(
          day,
        )).items.singleWhere((o) => o.task.id == 'manual');
        await expectLater(service.assign(manual, 750), throwsStateError);
        expect(
          (await repo.occurrences(
            day,
          )).singleWhere((o) => o.task.id == 'auto').toJson(),
          started.toJson(),
        );
        expect(
          (await repo.occurrences(
            day,
          )).singleWhere((o) => o.task.id == 'manual').start,
          isNull,
        );
      },
    );

    test('strict conflict preview includes started suggestions', () async {
      final t = task('auto');
      await service.save(t);
      await service.update(Occurrence(task: t, day: day, assigned: 720));
      expect(
        await service.conflicts(task('strict', kind: TaskKind.strict)),
        contains('2026-10-21 · auto'),
      );
    });

    test(
      'archiving preserves materialized strict blocks but stops new occurrences',
      () async {
        final t = task('strict', kind: TaskKind.strict);
        await service.save(t);
        final future = DateTime(2026, 10, 22);
        final snapshots = [
          (await service.day(day)).items.single,
          (await service.day(future)).items.single,
        ];
        await service.save(t.copy(archived: true));
        expect(
          (await service.day(day)).items.single.toJson(),
          snapshots.first.toJson(),
        );
        expect(
          (await service.day(future)).items.single.toJson(),
          snapshots.last.toJson(),
        );
        expect((await service.day(DateTime(2026, 10, 23))).items, isEmpty);
      },
    );

    test(
      'archiving preserves all progress and started assignments, removes regenerable ones',
      () async {
        final t = task('auto');
        await service.save(t);
        final saved = [
          Occurrence(task: t, day: day, assigned: 720),
          Occurrence(
            task: t,
            day: DateTime(2026, 10, 22),
            status: TaskStatus.completed,
          ),
          Occurrence(
            task: t,
            day: DateTime(2026, 10, 23),
            status: TaskStatus.skipped,
          ),
          Occurrence(
            task: t,
            day: DateTime(2026, 10, 24),
            assigned: 900,
            locked: true,
          ),
          Occurrence(task: t, day: DateTime(2026, 10, 25), checked: [1]),
          Occurrence(task: t, day: DateTime(2026, 10, 26), exception: true),
        ];
        await repo.saveOccurrences([
          ...saved,
          Occurrence(task: t, day: DateTime(2026, 10, 27), assigned: 900),
        ]);
        await service.save(t.copy(archived: true));
        expect(
          (await repo.allOccurrences()).map((o) => o.toJson()),
          saved.map((o) => o.toJson()),
        );
        final backup = await repo.exportBackup();
        await repo.importBackup(backup);
        expect(await repo.exportBackup(), backup);
      },
    );
  });
}
