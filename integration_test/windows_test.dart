import 'dart:io';
import 'dart:ui' as ui;
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/data_directory.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows: SQLite native, calendar actions, backup and reopen', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp(
      'simple-calendar-windows-',
    );
    final legacy = File(
      '${dir.path}/local.calendario/calendario/calendario.sqlite',
    );
    await legacy.parent.create(recursive: true);
    final legacyDb = CalendarDatabase.file(legacy);
    await DriftCalendarRepository(legacyDb).preferences();
    await legacyDb.close();
    final file = await prepareDatabaseFile(dir);
    expect(
      file.parent.path,
      '${dir.path}${Platform.pathSeparator}Simple Calendar',
    );
    expect(await legacy.exists(), isTrue);
    final db = CalendarDatabase.file(file);
    final repo = DriftCalendarRepository(db);
    final service = CalendarService(repo);
    final container = ProviderContainer(
      overrides: [serviceProvider.overrideWithValue(service)],
    );
    final imageKey = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: imageKey, child: const CalendarApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Gym');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Start time'),
      '08:00',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'End time'),
      '08:45',
    );
    await tester.ensureVisible(find.text('Choose'));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Training'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repo.tasks()).single.title, 'Gym');
    expect((await repo.tasks()).single.start, 480);
    expect((await repo.tasks()).single.duration, 45);
    expect((await repo.tasks()).single.tagIds, ['tag-entrenamiento']);
    final c = container.read(calendarProvider);
    final d = DateTime(c.date.year, c.date.month, c.date.day + 1);
    await service.save(
      Task(
        id: 'strict',
        title: 'Focused work',
        date: d,
        kind: TaskKind.strict,
        start: 540,
        duration: 90,
        repeat: Repeat.daily,
        tagIds: const ['tag-trabajo'],
      ),
    );
    await service.save(
      Task(
        id: 'auto',
        title: 'Study programming',
        autoWindow: const Span(540, 840),
        date: d,
        duration: 120,
        priority: 2,
        subtasks: ['Read documentation', 'Practice exercises'],
        tagIds: const ['tag-estudio', 'tag-personal'],
      ),
    );
    await service.save(
      Task(
        id: 'manual',
        title: 'Read a book',
        date: d,
        kind: TaskKind.manual,
        duration: 45,
      ),
    );
    c.navigate(0, d);
    await c.refresh();
    await tester.pumpAndSettle();
    var plan = c.plans[dayKey(d)]!;
    expect(plan.items.singleWhere((o) => o.task.id == 'auto').assigned, 630);
    final manual = plan.items.singleWhere((o) => o.task.id == 'manual');
    await c.assign(manual, 480);
    await tester.pumpAndSettle();
    plan = c.plans[dayKey(d)]!;
    final auto = plan.items.singleWhere((o) => o.task.id == 'auto');
    c.select(auto);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read documentation'));
    await tester.pumpAndSettle();
    expect(
      (await repo.occurrences(
        d,
      )).singleWhere((o) => o.task.id == 'auto').checked,
      [0],
    );
    final boundary =
        imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final screenshot = File('artifacts/windows-day.png');
    await screenshot.parent.create(recursive: true);
    await screenshot.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    for (final view in [1, 2, 3, 4, 5]) {
      c.navigate(view, d);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (view == 1) {
        final weekImage = await boundary.toImage(pixelRatio: 1);
        final weekBytes = await weekImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await File(
          'artifacts/windows-week.png',
        ).writeAsBytes(weekBytes!.buffer.asUint8List());
        weekImage.dispose();
      }
    }
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();
    expect((await repo.preferences()).language, 'es');
    expect(find.text('Idioma'), findsWidgets);
    c.navigate(0, d);
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Tu día'), findsOneWidget);
    final spanishImage = await boundary.toImage(pixelRatio: 1);
    final spanishBytes = await spanishImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await File(
      'artifacts/windows-day-es.png',
    ).writeAsBytes(spanishBytes!.buffer.asUint8List());
    spanishImage.dispose();
    final weekEnd = clampCalendarDay(
      DateTime(d.year, d.month, d.day + 7 - d.weekday),
    );
    await service.save(
      Task(
        id: 'week-only',
        title: 'This week only',
        date: d,
        repeat: Repeat.daily,
        duration: 15,
        endDate: weekEnd,
      ),
    );
    final backup = await repo.exportBackup();
    await repo.importBackup(backup);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await db.close();
    final reopened = CalendarDatabase.file(file);
    final persisted = await DriftCalendarRepository(reopened).occurrences(d);
    expect(
      persisted.singleWhere((o) => o.task.id == 'auto').status,
      TaskStatus.completed,
    );
    expect(persisted.singleWhere((o) => o.task.id == 'manual').assigned, 480);
    expect(persisted.singleWhere((o) => o.task.id == 'auto').task.tagIds, [
      'tag-estudio',
      'tag-personal',
    ]);
    expect((await DriftCalendarRepository(reopened).tags()).length, 8);
    expect(
      (await DriftCalendarRepository(reopened).preferences()).language,
      'es',
    );
    final reopenedRepo = DriftCalendarRepository(reopened);
    expect(
      persisted.singleWhere((o) => o.task.id == 'auto').task.autoWindow!.start,
      540,
    );
    expect(
      persisted.singleWhere((o) => o.task.id == 'auto').task.autoWindow!.end,
      840,
    );
    final removalService = CalendarService(reopenedRepo);
    expect(
      (await reopenedRepo.tasks())
          .singleWhere((t) => t.id == 'week-only')
          .endDate,
      weekEnd,
    );
    expect(
      (await removalService.day(
        DateTime(weekEnd.year, weekEnd.month, weekEnd.day + 1),
      )).items.where((o) => o.task.id == 'week-only'),
      isEmpty,
    );
    final nextDay = DateTime(d.year, d.month, d.day + 1);
    final oldStrict = (await removalService.day(
      nextDay,
    )).items.singleWhere((o) => o.task.id == 'strict');
    await removalService.removeActivity('strict');
    expect(
      (await removalService.day(
        nextDay,
      )).items.where((o) => o.task.id == 'strict'),
      isEmpty,
    );
    await expectLater(removalService.update(oldStrict), throwsStateError);
    expect(
      (await reopenedRepo.tasks())
          .singleWhere((t) => t.id == 'strict')
          .archived,
      isTrue,
    );
    await reopened.close();
    await dir.delete(recursive: true);
  });
}
