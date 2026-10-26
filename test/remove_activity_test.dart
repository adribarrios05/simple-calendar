import 'dart:convert';
import 'dart:io';

import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 26, 12);
final tomorrow = DateTime(2026, 10, 27);
Task routine({TaskKind kind = TaskKind.strict}) => Task(
  id: 'routine',
  title: 'Work',
  date: DateTime(2026, 10, 24),
  kind: kind,
  start: 420,
  duration: 480,
  repeat: Repeat.daily,
  subtasks: const ['Read'],
  tagIds: const ['tag-trabajo'],
);
CalendarService serviceFor(DriftCalendarRepository repo) =>
    CalendarService(repo, planner: Planner(clock: FixedClock(now)));

void main() {
  for (final kind in TaskKind.values) {
    test(
      'removing a $kind routine releases future slots and stops generation',
      () async {
        final db = CalendarDatabase(NativeDatabase.memory());
        try {
          final repo = DriftCalendarRepository(db);
          final service = serviceFor(repo);
          final task = routine(kind: kind);
          await service.save(task);
          final saved = (await service.day(tomorrow)).items.single;
          if (kind == TaskKind.manual) await service.assign(saved, 480);
          await service.removeActivity(task.id);
          expect((await repo.tasks()).single.archived, isTrue);
          final plan = await service.day(tomorrow);
          expect(
            plan.items.where((o) => o.status != TaskStatus.skipped),
            isEmpty,
          );
          expect(plan.free, isNotEmpty);
          expect((await service.day(DateTime(2026, 11, 2))).items, isEmpty);
        } finally {
          await db.close();
        }
      },
    );
  }

  test(
    'removal hides today and future dates while retaining original records and past history',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = serviceFor(repo);
        final task = routine();
        await service.save(task);
        final originals = [
          Occurrence(task: task, day: DateTime(2026, 10, 25)),
          Occurrence(task: task, day: dateOnly(now)),
          Occurrence(
            task: task,
            day: tomorrow,
            locked: true,
            exception: true,
            checked: [0],
          ),
          Occurrence(
            task: task,
            day: DateTime(2026, 10, 28),
            status: TaskStatus.completed,
            checked: [0],
          ),
          Occurrence(
            task: task,
            day: DateTime(2026, 10, 29),
            status: TaskStatus.skipped,
          ),
        ];
        await repo.saveOccurrences(originals);
        await service.removeActivity(task.id);
        expect(
          (await repo.occurrences(originals.first.day)).single.toJson(),
          originals.first.toJson(),
        );
        expect((await service.day(dateOnly(now))).items, isEmpty);
        expect((await service.day(tomorrow)).items, isEmpty);
        expect((await service.day(DateTime(2026, 10, 28))).items, isEmpty);
        expect(
          (await repo.allOccurrences()).map((o) => o.toJson()),
          originals.map((o) => o.toJson()),
        );
        final plan = await service.day(tomorrow);
        expect(plan.issues, isEmpty);
        expect(plan.free.single.start, 480);
        expect(plan.free.single.end, 1320);
        await expectLater(
          service.update(originals[2].copy(status: TaskStatus.pending)),
          throwsStateError,
        );
        await expectLater(service.save(task), throwsStateError);
        await service.removeActivity(task.id);
        expect((await repo.tasks()).single.removedFrom, dateOnly(now));
      } finally {
        await db.close();
      }
    },
  );

  test(
    'removal also cleans up future fixed blocks from previously archived definitions',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = serviceFor(repo);
        final task = routine();
        await service.save(task);
        await service.day(tomorrow);
        await service.save(task.copy(archived: true));
        expect(
          (await service.day(tomorrow)).items.single.status,
          TaskStatus.pending,
        );
        await service.removeActivity(task.id);
        expect((await service.day(tomorrow)).items, isEmpty);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'removal by ID never replaces the latest definition with a historical snapshot',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = serviceFor(repo);
        final original = routine();
        await service.save(original);
        await service.day(DateTime(2026, 10, 25));
        final updated = Task.fromJson({
          ...original.toJson(),
          'title': 'Updated work',
          'duration': 300,
        });
        await service.save(updated);
        await service.removeActivity(original.id);
        expect((await repo.tasks()).single.toJson(), {
          ...updated.toJson(),
          'archived': true,
          'removedFrom': dayKey(now),
        });
        expect(
          (await repo.tasksForDay(DateTime(2026, 10, 25))).single.title,
          'Work',
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'cancellation failure rolls back both definition archival and execution changes',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = serviceFor(repo);
        await service.save(routine());
        await service.day(tomorrow);
        final before = jsonDecode(await repo.exportBackup());
        await db.customStatement(
          "CREATE TRIGGER fail_cancel BEFORE INSERT ON revisions BEGIN SELECT RAISE(ABORT, 'synthetic cancellation failure'); END",
        );
        await expectLater(
          service.removeActivity('routine'),
          throwsA(isA<Exception>()),
        );
        expect(jsonDecode(await repo.exportBackup()), before);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'cancelled routines survive backup restore and disk reopening without regeneration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simple-calendar-remove-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = CalendarDatabase.file(file);
      try {
        var repo = DriftCalendarRepository(db);
        var service = serviceFor(repo);
        await service.save(routine());
        await service.day(tomorrow);
        await service.removeActivity('routine');
        final backup = await repo.exportBackup();
        await repo.importBackup(backup);
        await db.close();
        db = CalendarDatabase.file(file);
        repo = DriftCalendarRepository(db);
        service = serviceFor(repo);
        expect((await service.day(tomorrow)).items, isEmpty);
        expect((await service.day(DateTime(2026, 11, 2))).items, isEmpty);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Spanish removal confirmation can cancel or stop a fixed recurring activity',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = CalendarDatabase(NativeDatabase.memory());
      final repo = DriftCalendarRepository(db);
      final service = serviceFor(repo);
      await service.save(routine());
      await repo.savePreferences(Preferences(language: 'es'));
      final container = ProviderContainer(
        overrides: [serviceProvider.overrideWithValue(service)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const CalendarApp(initialLanguage: 'es'),
          ),
        );
        await tester.pumpAndSettle();
        final controller = container.read(calendarProvider);
        controller.navigate(1, tomorrow);
        await controller.refresh();
        controller.select(controller.plans[dayKey(tomorrow)]!.items.single);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Eliminar actividad'));
        await tester.pumpAndSettle();
        expect(find.text('¿Eliminar actividad?'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect((await repo.tasks()).single.archived, isFalse);
        await tester.tap(find.widgetWithText(TextButton, 'Eliminar actividad'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Eliminar actividad'),
        );
        await tester.pumpAndSettle();
        expect((await repo.tasks()).single.archived, isTrue);
        expect(controller.plans[dayKey(tomorrow)]!.items, isEmpty);
        expect(controller.error, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      }
    },
  );
}
