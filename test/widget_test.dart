import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging an unassigned manual task persists its time and lock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = CalendarDatabase(NativeDatabase.memory());
    final repo = DriftCalendarRepository(db);
    final today = dateOnly(DateTime.now());
    await repo.saveTask(
      Task(
        id: 'manual-drag',
        title: 'Leer manual',
        date: today,
        kind: TaskKind.manual,
        duration: 45,
      ),
      today,
    );
    final container = ProviderContainer(
      overrides: [serviceProvider.overrideWithValue(CalendarService(repo))],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CalendarApp(),
      ),
    );
    await tester.pumpAndSettle();
    final source = tester.getCenter(find.text('Leer manual'));
    final target = tester.getCenter(find.byKey(const ValueKey('slot-480')));
    final gesture = await tester.startGesture(source);
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final occurrence = (await repo.occurrences(today)).single;
    expect(occurrence.assigned, 480);
    expect(occurrence.locked, true);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await db.close();
  });
  testWidgets('create, edit and complete an activity and switch views', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = CalendarDatabase(NativeDatabase.memory());
    final repository = DriftCalendarRepository(db);
    final container = ProviderContainer(
      overrides: [
        serviceProvider.overrideWithValue(CalendarService(repository)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CalendarApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Gimnasio',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repository.tasks()).single.title, 'Gimnasio');
    final c = container.read(calendarProvider);
    c.select(c.plans[dayKey(c.date)]!.items.single);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(
      (await repository.occurrences(c.date)).single.status,
      TaskStatus.completed,
    );
    await tester.tap(find.text('Edit activity'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Gimnasio actualizado',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await repository.occurrences(c.date)).single.task.title,
      'Gimnasio actualizado',
    );
    for (final name in [
      'Week',
      'Month',
      'Tasks',
      'Routines',
      'Settings',
      'Today',
    ]) {
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await db.close();
  });
  testWidgets('all scheduling types have explicit visual labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = CalendarDatabase(NativeDatabase.memory());
    final repo = DriftCalendarRepository(db);
    final today = dateOnly(DateTime.now());
    for (final kind in TaskKind.values) {
      await repo.saveTask(
        Task(
          id: kind.name,
          title: kind.name,
          date: today,
          kind: kind,
          duration: 120,
        ),
        today,
      );
    }
    final container = ProviderContainer(
      overrides: [serviceProvider.overrideWithValue(CalendarService(repo))],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CalendarApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('◷ Fixed'), findsOneWidget);
    expect(find.text('◇ Suggested automatic'), findsOneWidget);
    expect(find.text('▣ Manual / locked'), findsOneWidget);
    expect(find.text('manual'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await db.close();
  });
}
