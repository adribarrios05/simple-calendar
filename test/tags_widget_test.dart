import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/domain/tag.dart';
import 'package:simple_calendar/main.dart';
import 'package:simple_calendar/presentation/tags.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CalendarDatabase db;
  late DriftCalendarRepository repo;
  late ProviderContainer container;
  final today = DateTime(2026, 10, 23);
  Future<CalendarController> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    db = CalendarDatabase(NativeDatabase.memory());
    repo = DriftCalendarRepository(db);
    container = ProviderContainer(
      overrides: [
        serviceProvider.overrideWithValue(
          CalendarService(repo, planner: Planner(clock: FixedClock(today))),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CalendarApp(),
      ),
    );
    await tester.pumpAndSettle();
    final controller = container.read(calendarProvider);
    await controller.refresh();
    return controller;
  }

  testWidgets(
    'compact selector searches, creates inline, assigns and removes tags',
    (tester) async {
      await open(tester);
      try {
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'),
          'Piano',
        );
        await tester.ensureVisible(find.text('Choose'));
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Study'));
        await tester.enterText(
          find.widgetWithText(TextField, 'Search tags'),
          'Música',
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(CheckboxListTile, 'Work'), findsNothing);
        await tester.tap(find.text('Create tag'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save tag'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(find.byType(InputChip), findsNWidgets(2));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final saved = (await repo.tasks()).single;
        expect(saved.tagIds.length, 2);
        expect(saved.tagIds, contains('tag-estudio'));
        final created = (await repo.tags()).singleWhere(
          (t) => t.name == 'Música',
        );
        expect(saved.tagIds, contains(created.id));
        final c = container.read(calendarProvider);
        c.navigate(3);
        await c.refresh();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Piano'));
        await tester.pumpAndSettle();
        final chip = tester.widget<InputChip>(find.byType(InputChip).first);
        chip.onDeleted!();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect((await repo.tasks()).single.tagIds.length, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      }
    },
  );

  testWidgets(
    'task and routine tag filters compose with search, untagged and clearing',
    (tester) async {
      final c = await open(tester);
      try {
        for (final (id, title, repeat, tags) in [
          ('one', 'Leer trabajo', Repeat.once, ['tag-trabajo']),
          ('daily', 'Leer rutina', Repeat.daily, ['tag-estudio']),
          ('empty', 'Paseo', Repeat.daily, <String>[]),
        ]) {
          await c.service.save(
            Task(
              id: id,
              title: title,
              date: today,
              repeat: repeat,
              tagIds: tags,
            ),
          );
        }
        c.navigate(3);
        await c.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Leer trabajo'), findsOneWidget);
        Future<void> filter(String label) async {
          await tester.tap(find.byKey(const ValueKey('tag-filter')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await filter('Study');
        expect(find.text('Leer rutina'), findsOneWidget);
        expect(find.text('Leer trabajo'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, 'Search activities'),
          'Paseo',
        );
        await tester.pumpAndSettle();
        expect(find.text('Leer rutina'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, 'Search activities'),
          '',
        );
        await filter('Untagged');
        expect(find.text('Paseo'), findsOneWidget);
        expect(find.text('Leer rutina'), findsNothing);
        await tester.tap(find.byTooltip('Clear tag filter'));
        await tester.pumpAndSettle();
        c.navigate(4);
        await c.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Leer trabajo'), findsNothing);
        expect(find.text('Leer rutina'), findsOneWidget);
        await filter('Study');
        expect(find.text('Paseo'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      }
    },
  );

  testWidgets(
    'settings confirms removing an associated custom tag and protects defaults',
    (tester) async {
      final c = await open(tester);
      try {
        const tag = Tag(id: 'custom', name: 'Viajes', color: 0xff91c7b1);
        await repo.saveTag(tag);
        await c.service.save(
          Task(id: 'travel', title: 'Viajar', date: today, tagIds: [tag.id]),
        );
        c.navigate(5);
        await c.refresh();
        await tester.pumpAndSettle();
        expect(find.byTooltip('Retire Work'), findsNothing);
        await tester.ensureVisible(find.byTooltip('Retire Viajes'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Retire Viajes'));
        await tester.pumpAndSettle();
        expect(find.textContaining('This tag is used'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect((await repo.tags()).last.archived, false);
        await tester.tap(find.byTooltip('Retire Viajes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retire'));
        await tester.pumpAndSettle();
        expect((await repo.tags()).last.archived, true);
        expect((await repo.tasks()).single.tagIds, [tag.id]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('tag chips use explicit readable foreground in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: TagChips(defaultTags.map((t) => t.id).toList(), defaultTags),
          ),
        ),
      );
      for (final tag in defaultTags) {
        final text = tester.widget<Text>(
          find.text(tagName(tester.element(find.byType(TagChips).first), tag)),
        );
        final fg = text.style!.color!.computeLuminance();
        final bg = Color(tag.color).computeLuminance();
        expect((bg + .05) / (fg + .05), greaterThanOrEqualTo(4.5));
      }
    });
  }
}
