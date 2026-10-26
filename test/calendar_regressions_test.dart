import 'dart:io';
import 'dart:ui' as ui;
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 10, 21);

class _MutableClock implements Clock {
  DateTime value;
  _MutableClock(this.value);
  @override
  DateTime now() => value;
}

class _Fixture {
  final imageKey = GlobalKey();
  final Clock clock;
  _Fixture({Clock? clock})
    : clock = clock ?? FixedClock(DateTime(2026, 10, 21, 12, 30));
  final CalendarDatabase db = CalendarDatabase(NativeDatabase.memory());
  late final repo = DriftCalendarRepository(db);
  late final service = CalendarService(repo, planner: Planner(clock: clock));
  late final container = ProviderContainer(
    overrides: [serviceProvider.overrideWithValue(service)],
  );
  CalendarController get controller => container.read(calendarProvider);

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: imageKey, child: const CalendarApp()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close([WidgetTester? tester]) async {
    if (tester != null) await tester.pumpWidget(const SizedBox());
    container.dispose();
    await db.close();
  }

  Future<void> screenshot(WidgetTester tester, String name) => tester.runAsync(
    () async {
      final boundary =
          imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final target = File('artifacts/audit/$name.png');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    },
  );
}

void main() {
  test('today views follow midnight without reusing yesterday state', () async {
    final clock = _MutableClock(DateTime(2026, 10, 21, 23, 59));
    final f = _Fixture(clock: clock);
    try {
      final task = Task(
        id: 'daily',
        title: 'Diaria',
        date: _today,
        repeat: Repeat.daily,
        kind: TaskKind.manual,
      );
      await f.service.save(task);
      await f.service.update(
        Occurrence(task: task, day: _today, status: TaskStatus.completed),
      );
      final c = f.controller;
      c.navigate(3);
      await c.refresh();
      expect(
        c.plans[dayKey(_today)]!.items.single.status,
        TaskStatus.completed,
      );
      clock.value = DateTime(2026, 10, 22, 0, 1);
      await c.refresh();
      expect(c.plans.keys, ['2026-10-22']);
      expect(c.plans.values.single.items.single.status, TaskStatus.pending);
      expect(
        (await f.repo.occurrences(_today)).single.status,
        TaskStatus.completed,
      );
    } finally {
      await f.close();
    }
  });

  test('duplicate subtask checks follow each occurrence of equal text', () {
    final task = Task(
      id: 'duplicate',
      title: 'Duplicadas',
      date: _today,
      subtasks: const ['Leer', 'Leer', 'Practicar'],
    );
    final o = Occurrence(task: task, day: _today, checked: const [1, 2]);
    expect(o.checkedForSubtasks(['Leer', 'Leer', 'Practicar']), [1, 2]);
    expect(o.checkedForSubtasks(['Practicar', 'Leer', 'Leer', 'Leer']), [0, 2]);
    expect(o.checkedForSubtasks(['Leer', 'Nueva']), isEmpty);
    expect(o.checkedForSubtasks([]), isEmpty);
  });

  test(
    'day, week and month navigation stop at the full supported range',
    () async {
      final f = _Fixture();
      try {
        final c = f.controller;
        await c.refresh();
        expect(c.date, _today);
        for (final view in [0, 1, 2]) {
          for (final (edge, delta) in [
            (firstCalendarDay, -1),
            (lastCalendarDay, 1),
          ]) {
            c.navigate(view, edge);
            await c.refresh();
            expect(c.error, isNull);
            expect(c.canShift(delta), false);
            c.shift(delta);
            await c.refresh();
            expect(c.date, edge);
            expect(
              c.plans.keys.every((key) => isCalendarDay(DateTime.parse(key))),
              true,
            );
            expect(
              c.visibleDays.length,
              view == 2
                  ? 42
                  : view == 1
                  ? 7
                  : 1,
            );
          }
        }
        c.navigate(2, DateTime(2100, 12, 1));
        await c.refresh();
        expect(c.canShift(1), false);
        c.navigate(0, DateTime(2200));
        await c.refresh();
        expect(c.date, lastCalendarDay);
        c.navigate(0, DateTime(1900));
        await c.refresh();
        expect(c.date, firstCalendarDay);
        await expectLater(f.service.day(DateTime(2101)), throwsFormatException);
        expect(await f.repo.allOccurrences(), isEmpty);
      } finally {
        await f.close();
      }
    },
  );

  testWidgets('today filters ignore the previously visited date', (
    tester,
  ) async {
    final f = _Fixture();
    try {
      final task = Task(
        id: 'routine',
        title: 'Rutina diaria',
        date: DateTime(2026, 10, 20),
        repeat: Repeat.daily,
        kind: TaskKind.manual,
      );
      await f.service.save(task);
      await f.repo.saveOccurrences([
        Occurrence(task: task, day: _today, status: TaskStatus.completed),
        Occurrence(task: task, day: task.date),
      ]);
      await f.mount(tester);
      final c = f.controller;
      c.navigate(0, task.date);
      await c.refresh();
      await tester.pumpAndSettle();
      for (final view in [3, 4]) {
        c.navigate(view);
        await c.refresh();
        await tester.pumpAndSettle();
        expect(c.plans.keys, [dayKey(_today)]);
        await tester.tap(find.text('All statuses'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Completed today').last);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Rutina diaria'), findsOneWidget);
        await tester.tap(find.text('Completed today'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All statuses').last);
        await tester.pumpAndSettle();
      }
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'saving an unchanged execution cannot multiply duplicate subtask checks',
    (tester) async {
      final f = _Fixture();
      try {
        final task = Task(
          id: 'duplicate',
          title: 'Duplicadas',
          date: _today,
          kind: TaskKind.manual,
          subtasks: const ['Leer', 'Leer'],
        );
        await f.service.save(task);
        final old = Occurrence(task: task, day: _today, checked: const [1]);
        await f.service.update(old);
        await f.mount(tester);
        f.controller.select(old);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit activity'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect((await f.repo.occurrences(_today)).single.checked, [1]);
        expect((await f.repo.tasks()).single.subtasks, ['Leer', 'Leer']);
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'brief day blocks keep exact heights and have readable alternative actions',
    (tester) async {
      final f = _Fixture();
      try {
        for (final (id, start, duration) in [
          ('Cinco', 540, 5),
          ('Uno', 545, 1),
          ('Veintiocho', 546, 28),
        ]) {
          await f.service.save(
            Task(
              id: id,
              title: id,
              date: _today,
              kind: TaskKind.strict,
              start: start,
              duration: duration,
            ),
          );
        }
        await f.mount(tester);
        Finder block(String id) =>
            find.byKey(ValueKey('day-block-$id/${dayKey(_today)}'));
        expect(tester.getSize(block('Cinco')).height, 5);
        expect(tester.getSize(block('Uno')).height, 1);
        await f.screenshot(tester, 'short-blocks-day');
        expect(
          tester.getTopRight(block('Cinco')).dx,
          tester.getTopRight(block('Uno')).dx,
        );
        expect(
          tester.getBottomLeft(block('Cinco')).dy,
          lessThanOrEqualTo(tester.getTopLeft(block('Uno')).dy),
        );
        final alternative = find.byKey(
          ValueKey('day-short-Uno/${dayKey(_today)}'),
        );
        await tester.ensureVisible(alternative);
        await tester.tap(alternative);
        await tester.pumpAndSettle();
        expect(f.controller.selected!.task.id, 'Uno');
        expect(tester.takeException(), isNull);
        f.controller.navigate(1);
        await f.controller.refresh();
        await tester.pumpAndSettle();
        final weeklyAlternative = find.byKey(
          ValueKey('week-list-Uno/${dayKey(_today)}'),
        );
        await f.screenshot(tester, 'short-blocks-week');
        await tester.ensureVisible(weeklyAlternative);
        await tester.tap(weeklyAlternative);
        await tester.pumpAndSettle();
        expect(f.controller.selected!.task.id, 'Uno');
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'December 2100 works in calendar and editor pickers; outside cells are disabled',
    (tester) async {
      final f = _Fixture();
      try {
        await f.mount(tester);
        final c = f.controller;
        c.navigate(0, lastCalendarDay);
        await c.refresh();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip('Go to date'));
        await tester.pumpAndSettle();
        var dialog = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(dialog.initialDate, lastCalendarDay);
        expect(dialog.lastDate, lastCalendarDay);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        c.navigate(2, lastCalendarDay);
        await c.refresh();
        await tester.pumpAndSettle();
        final outside = find.byKey(const ValueKey('month-day-2101-01-01'));
        expect(tester.widget<InkWell>(outside).onTap, isNull);
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start date: 2100-12-31'));
        await tester.pumpAndSettle();
        dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
        expect(dialog.initialDate, lastCalendarDay);
        expect(dialog.lastDate, lastCalendarDay);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );
}
