import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/presentation/task_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (returnToSingle, archived) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    testWidgets(
      'scope loads the correct definition and keeps historical progress (single=$returnToSingle, archived=$archived)',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = CalendarDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = DriftCalendarRepository(db);
        final service = CalendarService(
          repo,
          planner: Planner(clock: FixedClock(DateTime(2026, 10, 21, 12, 30))),
        );
        final original = Task(
          id: 'routine',
          title: 'Antigua',
          date: DateTime(2026, 10, 20),
          repeat: Repeat.daily,
          subtasks: const ['Leer'],
          tagIds: const ['tag-estudio'],
        );
        await service.save(original);
        final old = (await service.day(
          original.date,
        )).items.single.copy(checked: [0]);
        await service.update(old);
        final current = Task.fromJson({
          ...original.toJson(),
          'title': 'Vigente',
          'duration': 90,
          'kind': 'manual',
          'repeat': 'weekly',
          'priority': 2,
          'subtasks': ['Practicar'],
          'tagIds': ['tag-trabajo'],
          'archived': archived,
        });
        await service.save(current);
        final controller = CalendarController(service);
        try {
          await controller.refresh();
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openTaskEditor(context, controller, occurrence: old),
                    child: const Text('Abrir editor'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir editor'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Only this occurrence'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('The definition, from today').last);
          await tester.pumpAndSettle();
          TextFormField field(String label) => tester.widget<TextFormField>(
            find.widgetWithText(TextFormField, label),
          );
          expect(field('Name').controller!.text, 'Vigente');
          expect(find.text('Work'), findsOneWidget);
          expect(find.text('Study'), findsNothing);
          expect(field('Duration (minutes)').controller!.text, '90');
          expect(find.text('Manual flexible'), findsOneWidget);
          expect(find.text('Weekly'), findsOneWidget);
          if (returnToSingle) {
            await tester.tap(find.text('The definition, from today'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Only this occurrence').last);
            await tester.pumpAndSettle();
            expect(field('Name').controller!.text, 'Antigua');
            expect(find.text('Study'), findsOneWidget);
            expect(find.text('Work'), findsNothing);
            expect(field('Duration (minutes)').controller!.text, '60');
            expect(find.text('Automatic flexible'), findsOneWidget);
          }
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Name'),
            'Nombre editado',
          );
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          final expected = {
            ...current.toJson(),
            if (!returnToSingle) 'title': 'Nombre editado',
          };
          expect((await repo.tasks()).single.toJson(), expected);
          if (archived) {
            expect((await service.day(DateTime(2026, 10, 27))).items, isEmpty);
          }
          final history = (await repo.occurrences(old.day)).single;
          expect(history.checked, [0]);
          expect(history.task.duration, 60);
          expect(
            history.task.title,
            returnToSingle ? 'Nombre editado' : 'Antigua',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          controller.dispose();
        }
      },
    );
  }
}
