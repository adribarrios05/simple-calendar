import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/l10n/app_strings.dart';
import 'package:simple_calendar/presentation/task_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CalendarDatabase db;
  late DriftCalendarRepository repo;
  late CalendarService service;
  late CalendarController controller;
  var controllerReady = false;
  setUp(() async {
    db = CalendarDatabase(NativeDatabase.memory());
    repo = DriftCalendarRepository(db);
    service = CalendarService(
      repo,
      planner: Planner(clock: FixedClock(DateTime(2026, 10, 26, 6))),
    );
    controllerReady = false;
  });
  tearDown(() async {
    if (controllerReady) controller.dispose();
    await db.close();
  });

  Future<void> open(
    WidgetTester tester, {
    Task? task,
    Occurrence? occurrence,
    String language = 'en',
  }) async {
    controller = CalendarController(service);
    controllerReady = true;
    await controller.refresh();
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openTaskEditor(
                context,
                controller,
                task: task,
                occurrence: occurrence,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    if (task == null && occurrence == null) {
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          language == 'es' ? 'Nombre' : 'Name',
        ),
        'Work',
      );
    }
  }

  TextFormField field(WidgetTester tester, String name) =>
      tester.widget<TextFormField>(find.widgetWithText(TextFormField, name));

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    controllerReady = false;
  }

  Future<void> submit(WidgetTester tester, {String language = 'en'}) async {
    await tester.tap(
      find.widgetWithText(FilledButton, language == 'es' ? 'Guardar' : 'Save'),
    );
    await tester.pump();
    final saving = language == 'es' ? 'Guardando\u2026' : 'Saving\u2026';
    // SQLite/conflict queries complete outside the widget test's fake clock.
    // Drive frames until the real form action completes, without a fixed sleep.
    for (
      var attempt = 0;
      attempt < 200 && find.text(saving).evaluate().isNotEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
    expect(find.text(saving), findsNothing);
  }

  for (final language in ['en', 'es']) {
    testWidgets('$language automatic activity saves optional same-day hours', (
      tester,
    ) async {
      await open(
        tester,
        language: language,
        task: Task(
          id: 'window-editor',
          title: 'Study',
          date: DateTime(2026, 10, 26),
        ),
      );
      final toggle = language == 'es'
          ? 'Limitar horario de planificación'
          : 'Limit scheduling hours';
      await tester.ensureVisible(find.text(toggle));
      await tester.tap(find.text(toggle));
      await tester.pumpAndSettle();
      final from = language == 'es' ? 'No antes de' : 'Not before';
      final to = language == 'es' ? 'Terminar antes de' : 'Finish by';
      await tester.enterText(find.widgetWithText(TextFormField, from), '09:00');
      await tester.enterText(find.widgetWithText(TextFormField, to), '14:00');
      await submit(tester, language: language);
      final saved = (await repo.tasks()).single;
      expect(saved.autoWindow!.start, 540);
      expect(saved.autoWindow!.end, 840);
      expect(saved.duration, 60);
      await close(tester);
    });

    testWidgets(
      '$language automatic window validates end and can be disabled',
      (tester) async {
        final original = Task(
          id: 'window-edit',
          title: 'Study',
          date: DateTime(2026, 10, 26),
          autoWindow: const Span(540, 840),
        );
        await service.save(original);
        await open(tester, language: language, task: original);
        final from = language == 'es' ? 'No antes de' : 'Not before';
        final to = language == 'es' ? 'Terminar antes de' : 'Finish by';
        expect(field(tester, from).controller!.text, '09:00');
        expect(field(tester, to).controller!.text, '14:00');
        await tester.enterText(find.widgetWithText(TextFormField, to), '08:00');
        await submit(tester, language: language);
        expect(
          find.text(
            language == 'es'
                ? 'La hora de fin debe ser posterior a la hora de inicio.'
                : 'The end time must be later than the start time.',
          ),
          findsOneWidget,
        );
        expect((await repo.tasks()).single.autoWindow!.end, 840);
        final toggle = language == 'es'
            ? 'Limitar horario de planificación'
            : 'Limit scheduling hours';
        await tester.ensureVisible(find.text(toggle));
        await tester.tap(find.text(toggle));
        await tester.pumpAndSettle();
        await submit(tester, language: language);
        expect((await repo.tasks()).single.autoWindow, isNull);
        await close(tester);
      },
    );

    testWidgets(
      '$language fixed creation stores start and calculated duration',
      (tester) async {
        await open(tester, language: language);
        final start = language == 'es' ? 'Hora de inicio' : 'Start time';
        final end = language == 'es' ? 'Hora de fin' : 'End time';
        expect(find.text('Duration (minutes)'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextFormField, start),
          '07:00',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, end),
          '15:00',
        );
        await submit(tester, language: language);
        final task = (await repo.tasks()).single;
        expect(task.start, 420);
        expect(task.duration, 480);
        expect(task.kind, TaskKind.strict);
        await close(tester);
      },
    );
  }

  for (final end in ['07:00', '06:59', '24:01', 'not a time']) {
    testWidgets('invalid fixed end $end cannot save an activity', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Start time'),
        '07:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'End time'),
        end,
      );
      await submit(tester);
      expect(await repo.tasks(), isEmpty);
      expect(find.text('New activity'), findsOneWidget);
      await close(tester);
    });
  }

  testWidgets('24:00 cannot be used as a start time', (tester) async {
    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Start time'),
      '24:00',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'End time'),
      '24:00',
    );
    await submit(tester);
    expect(await repo.tasks(), isEmpty);
    expect(find.text('Enter a valid time in HH:mm format.'), findsOneWidget);
    await close(tester);
  });

  for (final start in ['00:00', '23:59']) {
    testWidgets('fixed $start to 24:00 respects the last supported minute', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Start time'),
        start,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'End time'),
        '24:00',
      );
      await tester.tap(find.byTooltip('Choose end time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(field(tester, 'End time').controller!.text, '24:00');
      await submit(tester);
      final task = (await repo.tasks()).single;
      expect(task.start + task.duration, 1440);
      expect(task.duration, start == '00:00' ? 1440 : 1);
      await close(tester);
    });
  }

  testWidgets(
    'existing fixed data and weekly bound round-trip through the form unchanged',
    (tester) async {
      final task = Task(
        id: 'existing',
        title: 'Existing',
        date: DateTime(2026, 10, 26),
        kind: TaskKind.strict,
        start: 420,
        duration: 480,
        repeat: Repeat.weekdays,
        endDate: DateTime(2026, 11, 1),
      );
      await service.save(task);
      await open(tester, task: task);
      expect(field(tester, 'Start time').controller!.text, '07:00');
      expect(field(tester, 'End time').controller!.text, '15:00');
      await submit(tester);
      expect((await repo.tasks()).single.toJson(), task.toJson());
      await close(tester);
    },
  );

  testWidgets(
    'switching fixed/flexible scheduling preserves the displayed interval and duration',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Start time'),
        '07:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'End time'),
        '15:00',
      );
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatic flexible').last);
      await tester.pumpAndSettle();
      expect(field(tester, 'Duration (minutes)').controller!.text, '480');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Duration (minutes)'),
        '90',
      );
      await tester.tap(find.text('Automatic flexible'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixed').last);
      await tester.pumpAndSettle();
      expect(field(tester, 'Start time').controller!.text, '07:00');
      expect(field(tester, 'End time').controller!.text, '08:30');
      await submit(tester);
      expect((await repo.tasks()).single.duration, 90);
      await close(tester);
    },
  );

  testWidgets('changing edit scope reloads the correct fixed interval', (
    tester,
  ) async {
    final old = Task(
      id: 'scope',
      title: 'Old',
      date: DateTime(2026, 10, 25),
      kind: TaskKind.strict,
      start: 420,
      duration: 30,
    );
    await service.save(old);
    final occurrence = Occurrence(task: old, day: old.date);
    await repo.saveOccurrences([occurrence]);
    await service.save(
      Task.fromJson({...old.toJson(), 'start': 600, 'duration': 90}),
    );
    await open(tester, occurrence: occurrence);
    expect(field(tester, 'End time').controller!.text, '07:30');
    await tester.tap(find.text('Only this occurrence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The definition, from today').last);
    await tester.pumpAndSettle();
    expect(field(tester, 'Start time').controller!.text, '10:00');
    expect(field(tester, 'End time').controller!.text, '11:30');
    await close(tester);
  });

  testWidgets(
    'changing scope loads the saved automatic window instead of unsaved values',
    (tester) async {
      final old = Task(
        id: 'window-scope',
        title: 'Study',
        date: DateTime(2026, 10, 25),
        autoWindow: const Span(540, 840),
      );
      await service.save(old);
      final occurrence = Occurrence(task: old, day: old.date);
      await repo.saveOccurrences([occurrence]);
      await service.save(
        Task.fromJson({
          ...old.toJson(),
          'autoWindow': [600, 900],
        }),
      );
      await open(tester, occurrence: occurrence);
      expect(field(tester, 'Not before').controller!.text, '09:00');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Not before'),
        '11:00',
      );
      await tester.ensureVisible(find.text('Only this occurrence'));
      await tester.tap(find.text('Only this occurrence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('The definition, from today').last);
      await tester.pumpAndSettle();
      expect(field(tester, 'Not before').controller!.text, '10:00');
      expect(field(tester, 'Finish by').controller!.text, '15:00');
      await close(tester);
    },
  );

  testWidgets('switching to manual does not persist an automatic window', (
    tester,
  ) async {
    final original = Task(
      id: 'window-kind',
      title: 'Study',
      date: DateTime(2026, 10, 26),
      autoWindow: const Span(540, 840),
    );
    await service.save(original);
    await open(tester, task: original);
    await tester.tap(find.text('Automatic flexible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual flexible').last);
    await tester.pumpAndSettle();
    expect(find.text('Limit scheduling hours'), findsNothing);
    await submit(tester);
    expect((await repo.tasks()).single.kind, TaskKind.manual);
    expect((await repo.tasks()).single.autoWindow, isNull);
    await close(tester);
  });
}
