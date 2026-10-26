import '../l10n/app_strings.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../application/controller.dart';
import '../data/repository.dart';
import '../data/storage_errors.dart';
import '../domain/model.dart';
import 'task_editor.dart';
import 'tags.dart';

class SettingsView extends StatefulWidget {
  final CalendarController controller;
  const SettingsView({super.key, required this.controller});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String? message;
  bool busy = false;
  Future<void> action(Future<String?> Function() fn) async {
    final strings = context.strings;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await fn();
      if (mounted) setState(() => message = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => message = strings.text('Could not complete: {0}', [
            strings.error(storageErrorMessage(e) ?? e),
          ]),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> availability(int weekday, bool start) async {
    final c = widget.controller;
    final span = c.preferences.availability[weekday]!;
    final minute = start ? span.start : span.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: minute == 1440 ? 23 : minute ~/ 60,
        minute: minute == 1440 ? 59 : minute % 60,
      ),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final n = picked.hour * 60 + picked.minute;
    final updated = start ? Span(n, span.end) : Span(span.start, n);
    if (updated.end < updated.start) {
      setState(
        () => message = context.strings.text(
          'The end must not be earlier than the start.',
        ),
      );
      return;
    }
    await c.run(
      () => c.service.repository.savePreferences(
        Preferences(
          theme: c.preferences.theme,
          language: c.preferences.language,
          availability: {...c.preferences.availability, weekday: updated},
        ),
      ),
    );
  }

  Future<String?> export() async {
    final strings = context.strings;
    final location = await getSaveLocation(
      suggestedName: 'simple-calendar-${dayKey(DateTime.now())}.json',
      acceptedTypeGroups: [
        XTypeGroup(
          label: strings.text('Calendar backup'),
          extensions: ['json'],
        ),
      ],
    );
    if (location == null) return null;
    final data = await widget.controller.service.repository.exportBackup();
    final file = File(location.path);
    final temporary = File('${location.path}.tmp');
    await temporary.writeAsString(data, flush: true);
    await temporary.rename(file.path);
    return strings.text('Backup saved to {0}', [file.path]);
  }

  Future<String?> import() async {
    final strings = context.strings;
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: strings.text('Calendar backup'),
          extensions: ['json'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > 50 * 1024 * 1024) {
      throw const FormatException('The backup exceeds 50 MB.');
    }
    final contents = await file.readAsString();
    DriftCalendarRepository.validateBackup(contents);
    if (!mounted) return null;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.strings.text('Restore validated backup')),
        content: Text(
          context.strings.text(
            'All local data will be replaced. You can export a backup from this screen before continuing.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(context.strings.text('Replace data')),
          ),
        ],
      ),
    );
    if (yes != true) return null;
    await widget.controller.run(
      () => widget.controller.service.repository.importBackup(contents),
    );
    if (widget.controller.error != null) {
      throw StateError(widget.controller.error!);
    }
    if (!mounted) return null;
    return context.strings.text('Backup restored successfully.');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListView(
      padding: EdgeInsets.all(24),
      children: [
        Text(
          context.strings.text('Language'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('language-${c.preferences.language}'),
          initialValue: c.preferences.language,
          decoration: InputDecoration(
            labelText: context.strings.text('Language'),
          ),
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'es', child: Text('Español')),
          ],
          onChanged: c.loading
              ? null
              : (language) {
                  if (language == null) return;
                  setState(() => message = null);
                  c.run(
                    () => c.service.repository.savePreferences(
                      Preferences(
                        theme: c.preferences.theme,
                        availability: c.preferences.availability,
                        language: language,
                      ),
                    ),
                  );
                },
        ),
        const SizedBox(height: 32),
        Text(
          context.strings.text('Appearance'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'system',
              label: Text(context.strings.text('System')),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: 'light',
              label: Text(context.strings.text('Light')),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: 'dark',
              label: Text(context.strings.text('Dark')),
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {c.preferences.theme},
          onSelectionChanged: (v) => c.run(
            () => c.service.repository.savePreferences(
              Preferences(
                theme: v.single,
                language: c.preferences.language,
                availability: c.preferences.availability,
              ),
            ),
          ),
        ),
        SizedBox(height: 32),
        Text(
          context.strings.text('Weekly availability'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 8),
        Text(
          context.strings.text(
            'The scheduler places flexible blocks within these hours. Fixed activities keep their time. Equal start and end times close that day.',
          ),
        ),
        SizedBox(height: 12),
        for (var i = 1; i <= 7; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 70, child: Text(weekdayLabels(context)[i - 1])),
                OutlinedButton(
                  onPressed: c.loading ? null : () => availability(i, true),
                  child: Text(timeLabel(c.preferences.availability[i]!.start)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(context.strings.text('to')),
                ),
                OutlinedButton(
                  onPressed: c.loading ? null : () => availability(i, false),
                  child: Text(timeLabel(c.preferences.availability[i]!.end)),
                ),
              ],
            ),
          ),
        SizedBox(height: 32),
        TagSettings(c),
        SizedBox(height: 32),
        Text(
          context.strings.text('Backups'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 8),
        Text(
          context.strings.text(
            'Your data stays on this computer. Export a backup to keep it safe or move it to another Windows computer.',
          ),
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: busy || c.loading ? null : () => action(export),
              icon: Icon(Icons.file_upload_outlined),
              label: Text(context.strings.text('Export backup')),
            ),
            OutlinedButton.icon(
              onPressed: busy || c.loading ? null : () => action(import),
              icon: Icon(Icons.file_download_outlined),
              label: Text(context.strings.text('Import backup')),
            ),
          ],
        ),
        if (busy)
          Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (message != null)
          Padding(
            padding: EdgeInsets.only(top: 16),
            child: SelectableText(message!),
          ),
        SizedBox(height: 32),
        Text(
          context.strings.text(
            'Shortcuts: Ctrl+N creates an activity · Ctrl+T opens today.\nDrag a flexible block onto the timeline to lock it in 15-minute steps. You can also choose an exact time from its details.\n\nSimple Calendar · No accounts or Internet connection.',
          ),
        ),
      ],
    );
  }
}
