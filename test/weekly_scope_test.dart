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
import 'package:sqlite3/sqlite3.dart' as sqlite;

final monday = DateTime(2026, 10, 26);
final sunday = DateTime(2026, 11, 1);
CalendarService weeklyService(DriftCalendarRepository repo) => CalendarService(
  repo,
  planner: Planner(clock: FixedClock(DateTime(2026, 10, 26, 8))),
);
Task boundedTask() => Task(
  id: 'bounded',
  title: 'This week',
  date: monday,
  repeat: Repeat.weekdays,
  endDate: sunday,
);

void main() {
  for (final repeat in Repeat.values) {
    test(
      'an inclusive week limit applies to $repeat without changing its day pattern',
      () {
        final task = Task(
          id: 'test',
          title: 'Test',
          date: monday,
          repeat: repeat,
          weekdays: const [1, 3, 5],
          endDate: sunday,
        );
        task.validate();
        expect(task.occurs(monday), isTrue);
        expect(task.occurs(DateTime(2026, 11, 2)), isFalse);
        expect(task.occurs(DateTime(2026, 10, 25)), isFalse);
        expect(Task.fromJson(task.toJson()).toJson(), task.toJson());
      },
    );
  }

  test('invalid end dates and reversible removal markers are rejected', () {
    expect(
      () => Task.fromJson({...boundedTask().toJson(), 'endDate': '2026-10-25'}),
      throwsFormatException,
    );
    expect(
      () => Task.fromJson({...boundedTask().toJson(), 'endDate': '2101-01-01'}),
      throwsFormatException,
    );
    expect(
      () => Task.fromJson({
        ...boundedTask().toJson(),
        'removedFrom': '2026-10-26',
      }),
      throwsFormatException,
    );
  });

  test(
    'week-only and unbounded activities persist through disk, backup and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simple-calendar-week-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = CalendarDatabase.file(file);
      try {
        var repo = DriftCalendarRepository(db);
        var service = weeklyService(repo);
        await service.save(boundedTask());
        await service.save(
          Task(
            id: 'ongoing',
            title: 'Every week',
            date: monday,
            repeat: Repeat.weekdays,
          ),
        );
        expect((await service.day(DateTime(2026, 10, 30))).items.length, 2);
        final backup = await repo.exportBackup();
        expect(jsonDecode(backup)['version'], 4);
        await repo.importBackup(backup);
        await db.close();
        db = CalendarDatabase.file(file);
        repo = DriftCalendarRepository(db);
        service = weeklyService(repo);
        expect(
          (await repo.tasks()).singleWhere((t) => t.id == 'bounded').endDate,
          sunday,
        );
        expect(
          (await service.day(
            DateTime(2026, 11, 2),
          )).items.map((o) => o.task.id),
          ['ongoing'],
        );
        expect((await service.day(DateTime(2026, 10, 30))).items.length, 2);
        final forgedOldBackup =
            jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
        forgedOldBackup['version'] = 2;
        final before = await repo.exportBackup();
        await expectLater(
          repo.importBackup(jsonEncode(forgedOldBackup)),
          throwsFormatException,
        );
        expect(await repo.exportBackup(), before);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'legacy v2 backups retain unlimited recurrences with absent optional fields',
    () async {
      final db = CalendarDatabase(NativeDatabase.memory());
      try {
        final repo = DriftCalendarRepository(db);
        final service = weeklyService(repo);
        await service.save(
          Task(
            id: 'legacy',
            title: 'Legacy',
            date: monday,
            repeat: Repeat.weekly,
          ),
        );
        final legacy =
            jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
        legacy['version'] = 2;
        await repo.importBackup(jsonEncode(legacy));
        expect((await repo.tasks()).single.endDate, isNull);
        expect((await repo.tasks()).single.removedFrom, isNull);
        expect(
          (await service.day(DateTime(2026, 11, 2))).items.single.task.id,
          'legacy',
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'schema v3 upgrades to v4 without rewriting existing agenda data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simple-calendar-schema4-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = CalendarDatabase.file(file);
      try {
        var repo = DriftCalendarRepository(db);
        final task = Task(
          id: 'legacy',
          title: 'Legacy',
          date: monday,
          repeat: Repeat.weekly,
        );
        await repo.saveTask(task, monday);
        await repo.saveOccurrences([
          Occurrence(
            task: task,
            day: monday,
            assigned: 540,
            locked: true,
            checked: const [],
          ),
        ]);
        await repo.savePreferences(Preferences(language: 'es', theme: 'dark'));
        final before = jsonDecode(await repo.exportBackup());
        await db.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('PRAGMA user_version = 3');
        raw.close();
        db = CalendarDatabase.file(file);
        repo = DriftCalendarRepository(db);
        expect(jsonDecode(await repo.exportBackup()), before);
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          5,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'legacy archived removals migrate and restore without becoming visible or reversible',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simple-calendar-removed-v3-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = CalendarDatabase.file(file);
      try {
        var repo = DriftCalendarRepository(db);
        var service = weeklyService(repo);
        final task = Task(
          id: 'old',
          title: 'Old removal',
          date: monday,
          kind: TaskKind.strict,
          repeat: Repeat.daily,
          subtasks: const ['Read'],
        );
        await service.save(task);
        final saved = (await service.day(DateTime(2026, 10, 27))).items.single;
        await service.save(task.copy(archived: true));
        final legacy =
            jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
        legacy['version'] = 2;
        final retained = (await repo.allOccurrences())
            .map((o) => o.toJson())
            .toList();
        await db.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('PRAGMA user_version = 3');
        raw.close();
        db = CalendarDatabase.file(file);
        repo = DriftCalendarRepository(db);
        service = weeklyService(repo);
        expect((await repo.tasks()).single.removedFrom, monday);
        expect((await service.day(DateTime(2026, 10, 27))).items, isEmpty);
        expect((await repo.allOccurrences()).map((o) => o.toJson()), retained);
        await expectLater(service.update(saved), throwsStateError);
        await repo.importBackup(jsonEncode(legacy));
        expect((await repo.tasks()).single.removedFrom, monday);
        expect((await service.day(DateTime(2026, 10, 27))).items, isEmpty);
        await expectLater(service.update(saved), throwsStateError);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'a legacy removal migration failure rolls back the version and definition updates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simple-calendar-removed-rollback-',
      );
      final file = File('${directory.path}/test.sqlite');
      var db = CalendarDatabase.file(file);
      try {
        final repo = DriftCalendarRepository(db);
        final service = weeklyService(repo);
        final task = Task(id: 'old', title: 'Old removal', date: monday);
        await service.save(task);
        await service.save(task.copy(archived: true));
        await db.close();
        var raw = sqlite.sqlite3.open(file.path);
        final original = raw
            .select('SELECT payload FROM definitions')
            .single['payload'];
        raw.execute('PRAGMA user_version = 3');
        raw.execute(
          "CREATE TRIGGER fail_migration BEFORE UPDATE ON revisions BEGIN SELECT RAISE(ABORT, 'synthetic migration failure'); END",
        );
        raw.close();
        db = CalendarDatabase.file(file);
        await expectLater(
          DriftCalendarRepository(db).preferences(),
          throwsA(isA<Exception>()),
        );
        await db.close();
        raw = sqlite.sqlite3.open(file.path);
        try {
          expect(raw.select('PRAGMA user_version').single.values.single, 3);
          expect(
            raw.select('SELECT payload FROM definitions').single['payload'],
            original,
          );
        } finally {
          raw.close();
        }
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final language in ['en', 'es']) {
    for (final onlyThisWeek in [true, false]) {
      testWidgets(
        '$language creation selects ${onlyThisWeek ? "this week" : "every week"}',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = CalendarDatabase(NativeDatabase.memory());
          final repo = DriftCalendarRepository(db);
          await repo.savePreferences(Preferences(language: language));
          final service = weeklyService(repo);
          final container = ProviderContainer(
            overrides: [serviceProvider.overrideWithValue(service)],
          );
          try {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: CalendarApp(initialLanguage: language),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(language == 'es' ? 'Crear' : 'Create'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(
                TextFormField,
                language == 'es' ? 'Nombre' : 'Name',
              ),
              'Weekly routine',
            );
            final everyWeek = language == 'es'
                ? 'Todas las semanas'
                : 'Every week';
            await tester.ensureVisible(find.text(everyWeek));
            if (onlyThisWeek) {
              await tester.tap(find.text(everyWeek));
              await tester.pumpAndSettle();
              await tester.tap(
                find
                    .text(
                      language == 'es' ? 'Solo esta semana' : 'This week only',
                    )
                    .last,
              );
              await tester.pumpAndSettle();
            }
            await tester.tap(find.text(language == 'es' ? 'Guardar' : 'Save'));
            await tester.pumpAndSettle();
            final task = (await repo.tasks()).single;
            expect(task.repeat, Repeat.weekly);
            expect(task.endDate, onlyThisWeek ? sunday : null);
            expect(
              (await service.day(DateTime(2026, 11, 2))).items.isEmpty,
              onlyThisWeek,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            container.dispose();
            await db.close();
          }
        },
      );
    }
  }
}
