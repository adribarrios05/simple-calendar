import 'dart:convert';
import 'dart:io';
import 'package:simple_calendar/application/calendar_service.dart';
import 'package:simple_calendar/application/controller.dart';
import 'package:simple_calendar/data/database.dart';
import 'package:simple_calendar/data/repository.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/domain/tag.dart';
import 'package:simple_calendar/l10n/app_strings.dart';
import 'package:simple_calendar/main.dart';
import 'package:simple_calendar/presentation/tags.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'English defaults, legacy preferences and invalid locale validation',
    () {
      expect(Preferences().language, 'en');
      final legacy = Preferences(theme: 'dark').toJson()..remove('language');
      expect(Preferences.fromJson(legacy).language, 'en');
      expect(
        Preferences.fromJson({...legacy, 'language': 'es'}).language,
        'es',
      );
      expect(
        () => Preferences.fromJson({...legacy, 'language': 'xx'}),
        throwsFormatException,
      );
    },
  );

  test(
    'catalogue placeholders match and user text is substituted verbatim',
    () {
      final placeholders = RegExp(r'\{\d+\}');
      for (final entry in spanishMessages.entries) {
        expect(
          placeholders.allMatches(entry.value).map((m) => m[0]).toList()
            ..sort(),
          placeholders.allMatches(entry.key).map((m) => m[0]).toList()..sort(),
          reason: entry.key,
        );
      }
      const es = AppStrings('es');
      expect(es.text('Tags: {0}', ['Work {1}']), 'Etiquetas: Work {1}');
      expect(
        es.error(
          StateError('This time overlaps with My Study. Choose another slot.'),
        ),
        'Ese horario coincide con My Study. Elige otro hueco.',
      );
      expect(es.error('Conflict with Work.'), 'Conflicto con Work.');
      expect(
        es.error('Unsupported migration: 1 → 9'),
        'Migración no compatible: 1 → 9',
      );
      expect(
        es.error('Unknown technical failure'),
        'Unknown technical failure',
      );
    },
  );

  test(
    'language survives disk reopen, backup and legacy import without changing task data',
    () async {
      final dir = await Directory.systemTemp.createTemp('calendar-language-');
      var db = CalendarDatabase.file(File('${dir.path}/test.sqlite'));
      try {
        var repo = DriftCalendarRepository(db);
        await repo.saveTask(
          Task(
            id: 'user-task',
            title: 'Estudiar English',
            date: DateTime(2026, 10, 24),
          ),
          DateTime(2026, 10, 24),
        );
        await repo.savePreferences(Preferences(theme: 'dark', language: 'es'));
        final backup = await repo.exportBackup();
        await db.close();
        db = CalendarDatabase.file(File('${dir.path}/test.sqlite'));
        repo = DriftCalendarRepository(db);
        expect((await repo.preferences()).language, 'es');
        await repo.savePreferences(Preferences());
        await repo.importBackup(backup);
        expect((await repo.preferences()).language, 'es');
        expect((await repo.tasks()).single.title, 'Estudiar English');
        final legacy = jsonDecode(backup) as Map<String, dynamic>;
        (legacy['preferences'] as Map).remove('language');
        await repo.importBackup(jsonEncode(legacy));
        expect((await repo.preferences()).language, 'en');
        final before = await repo.exportBackup();
        (legacy['preferences'] as Map)['language'] = 'xx';
        await expectLater(
          repo.importBackup(jsonEncode(legacy)),
          throwsFormatException,
        );
        expect(await repo.exportBackup(), before);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'English default, Spanish switch and theme changes preserve locale and activity',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = CalendarDatabase(NativeDatabase.memory());
      final repo = DriftCalendarRepository(db);
      final now = DateTime(2026, 10, 24, 8);
      final service = CalendarService(
        repo,
        planner: Planner(clock: FixedClock(now)),
      );
      await service.save(
        Task(
          id: 'preserved',
          title: 'Mi tarea sin traducir',
          date: now,
          tagIds: const ['tag-trabajo'],
        ),
      );
      final container = ProviderContainer(
        overrides: [serviceProvider.overrideWithValue(service)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const CalendarApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('en'),
        );
        expect(find.text('Your day'), findsOneWidget);
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        expect(find.text('New activity'), findsOneWidget);
        expect(find.text('Start time'), findsOneWidget);
        expect(find.text('End time'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        final before =
            jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
        final controller = container.read(calendarProvider);
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Español').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('es'),
        );
        expect((await repo.preferences()).language, 'es');
        expect(find.text('Idioma'), findsWidgets);
        expect(find.text('Configuración'), findsWidgets);
        expect(controller.view, 5);
        await tester.tap(find.text('Oscuro'));
        await tester.pumpAndSettle();
        expect((await repo.preferences()).language, 'es');
        expect((await repo.preferences()).theme, 'dark');
        await tester.tap(find.text('Hoy').first);
        await tester.pumpAndSettle();
        expect(find.text('Mi tarea sin traducir'), findsWidgets);
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();
        expect(find.text('Nueva actividad'), findsOneWidget);
        expect(find.text('Hora de inicio'), findsOneWidget);
        expect(find.text('Hora de fin'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        final after =
            jsonDecode(await repo.exportBackup()) as Map<String, dynamic>;
        for (final key in ['tasks', 'revisions', 'occurrences', 'tags']) {
          expect(after[key], before[key], reason: key);
        }
        await tester.tap(find.text('Configuración'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English').last);
        await tester.pumpAndSettle();
        expect((await repo.preferences()).language, 'en');
        expect((await repo.preferences()).theme, 'dark');
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('en'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      }
    },
  );

  testWidgets(
    'editing an untouched built-in preserves its stored name and rejects a duplicate display name',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = CalendarDatabase(NativeDatabase.memory());
      final repo = DriftCalendarRepository(db);
      final container = ProviderContainer(
        overrides: [serviceProvider.overrideWithValue(CalendarService(repo))],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const CalendarApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Edit Work'));
        await tester.tap(find.byTooltip('Edit Work'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Work'), findsOneWidget);
        await tester.tap(find.text('Save tag'));
        await tester.pumpAndSettle();
        expect(
          (await repo.tags()).firstWhere((t) => t.id == 'tag-trabajo').name,
          'Trabajo',
        );
        await tester.ensureVisible(find.text('New tag'));
        await tester.tap(find.text('New tag'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.tap(find.text('Save tag'));
        await tester.pumpAndSettle();
        expect(
          find.text('A tag with this name already exists.'),
          findsOneWidget,
        );
        expect((await repo.tags()).length, 8);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      }
    },
  );

  testWidgets(
    'built-in display names translate, renamed and custom names do not',
    (tester) async {
      final renamed = defaultTags.first.copy(name: 'My Work');
      const custom = Tag(id: 'custom', name: 'Trabajo', color: 0xff9bafe5);
      for (final language in ['en', 'es']) {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: TagChips(
                [defaultTags[1].id, renamed.id, custom.id],
                [defaultTags[1], renamed, custom],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'en' ? 'Study' : 'Estudio'),
          findsOneWidget,
        );
        expect(find.text('My Work'), findsOneWidget);
        expect(find.text('Trabajo'), findsOneWidget);
        expect(defaultTags[1].name, 'Estudio');
      }
    },
  );
}
