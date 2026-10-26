import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'application/calendar_service.dart';
import 'application/controller.dart';
import 'data/database.dart';
import 'data/data_directory.dart';
import 'data/repository.dart';
import 'data/storage_errors.dart';
import 'presentation/home.dart';
import 'l10n/app_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = CalendarDatabase.file(await applicationDatabaseFile());
    final repository = DriftCalendarRepository(db);
    final preferences = await repository.preferences();
    runApp(
      ProviderScope(
        overrides: [
          serviceProvider.overrideWithValue(CalendarService(repository)),
        ],
        child: CalendarApp(initialLanguage: preferences.language),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'The database could not be opened.\n${storageErrorMessage(e) ?? e}\n\nClose the app and check access to the data folder.',
            ),
          ),
        ),
      ),
    );
  }
}

class CalendarApp extends ConsumerWidget {
  final String initialLanguage;
  const CalendarApp({super.key, this.initialLanguage = 'en'});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(calendarProvider);
    final mode = controller.preferences.theme;
    final language = controller.loading && controller.plans.isEmpty
        ? initialLanguage
        : controller.preferences.language;
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff5269cc),
        brightness: brightness,
      ),
      fontFamily: 'Segoe UI',
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    );
    return MaterialApp(
      locale: Locale(language),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      title: 'Simple Calendar',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: mode == 'dark'
          ? ThemeMode.dark
          : mode == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      home: const CalendarHome(),
    );
  }
}
