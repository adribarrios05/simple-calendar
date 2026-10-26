import 'dart:convert';
import 'package:drift/drift.dart';
import '../domain/model.dart';
import '../domain/tag.dart';
import 'database.dart';

abstract interface class CalendarRepository {
  Future<List<Tag>> tags();
  Future<void> saveTag(Tag tag);
  Future<void> archiveTag(String id);
  Future<bool> tagInUse(String id);
  Future<List<Task>> tasks();
  Future<List<Task>> tasksForDay(DateTime day);
  Future<List<Occurrence>> allOccurrences();
  Future<List<Occurrence>> occurrences(DateTime day);
  // `from` includes the time of the edit; revisions are still effective by day.
  Future<void> saveTask(Task task, DateTime from);
  Future<void> removeActivity(String taskId, DateTime from);
  Future<void> saveOccurrences(List<Occurrence> occurrences);
  Future<Preferences> preferences();
  Future<void> savePreferences(Preferences preferences);
  Future<String> exportBackup();
  Future<void> importBackup(String contents);
}

class DriftCalendarRepository implements CalendarRepository {
  final CalendarDatabase db;
  DriftCalendarRepository(this.db);
  Map<String, dynamic> decode(String s) =>
      Map<String, dynamic>.from(jsonDecode(s));
  @override
  Future<List<Tag>> tags() async => (await db.select(db.tags).get())
      .map((r) => Tag.fromJson(decode(r.payload)))
      .toList();

  @override
  Future<void> saveTag(Tag tag) => db.transaction(() async {
    tag.validate();
    final all = await tags();
    final existing = all.where((t) => t.id == tag.id).firstOrNull;
    if ((existing == null && tag.id.startsWith('tag-')) ||
        existing?.archived == true ||
        tag.archived) {
      throw const FormatException('This tag cannot be saved.');
    }
    // Archived names stay reserved so historical references remain unambiguous.
    if (all.any(
      (t) => t.id != tag.id && t.normalizedName == tag.normalizedName,
    )) {
      throw const FormatException('A tag with this name already exists.');
    }
    await db
        .into(db.tags)
        .insertOnConflictUpdate(
          TagsCompanion.insert(id: tag.id, payload: encode(tag.toJson())),
        );
  });

  @override
  Future<void> archiveTag(String id) => db.transaction(() async {
    final tag = (await tags()).where((t) => t.id == id).firstOrNull;
    if (tag == null || tag.predefined) {
      throw const FormatException('Built-in tags cannot be retired.');
    }
    await db
        .into(db.tags)
        .insertOnConflictUpdate(
          TagsCompanion.insert(
            id: tag.id,
            payload: encode(tag.copy(archived: true).toJson()),
          ),
        );
  });

  @override
  Future<bool> tagInUse(String id) async {
    if ((await tasks()).any((t) => t.tagIds.contains(id))) return true;
    if ((await allOccurrences()).any((o) => o.task.tagIds.contains(id))) {
      return true;
    }
    return (await db.select(db.revisions).get()).any(
      (r) => Task.fromJson(decode(r.payload)).tagIds.contains(id),
    );
  }

  Future<void> _validateTags(Task task) async {
    final ids = (await tags()).map((t) => t.id).toSet();
    if (!task.tagIds.every(ids.contains)) {
      throw const FormatException('The activity contains unknown tags.');
    }
  }

  @override
  Future<List<Task>> tasks() async => (await db.select(db.definitions).get())
      .map((r) => Task.fromJson(decode(r.payload)))
      .toList();
  @override
  Future<List<Task>> tasksForDay(DateTime day) async {
    final rows =
        await (db.select(db.revisions)
              ..where((r) => r.effective.isSmallerOrEqualValue(dayKey(day)))
              ..orderBy([(r) => OrderingTerm.desc(r.effective)]))
            .get();
    final found = <String, Task>{};
    for (final r in rows) {
      found.putIfAbsent(r.taskId, () => Task.fromJson(decode(r.payload)));
    }
    return found.values.toList();
  }

  @override
  Future<List<Occurrence>> allOccurrences() async =>
      (await db.select(db.executions).get())
          .map((r) => Occurrence.fromJson(decode(r.payload)))
          .toList();
  @override
  Future<List<Occurrence>> occurrences(DateTime day) async {
    final query = db.select(db.executions).join([
      innerJoin(
        db.definitions,
        db.definitions.id.equalsExp(db.executions.taskId),
      ),
    ])..where(db.executions.day.equals(dayKey(day)));
    final rows = await query.get();
    return rows
        .where((row) {
          final task = Task.fromJson(
            decode(row.readTable(db.definitions).payload),
          );
          return task.removedFrom == null ||
              dateOnly(day).isBefore(task.removedFrom!);
        })
        .map(
          (row) =>
              Occurrence.fromJson(decode(row.readTable(db.executions).payload)),
        )
        .toList();
  }

  @override
  Future<void> saveTask(Task task, DateTime from) => db.transaction(() async {
    task.validate();
    await _validateTags(task);
    final existing = await (db.select(
      db.definitions,
    )..where((t) => t.id.equals(task.id))).getSingleOrNull();
    final previous = existing == null
        ? null
        : Task.fromJson(decode(existing.payload));
    if (previous?.removedFrom != null) {
      throw StateError(
        'This activity has been removed and cannot be restored.',
      );
    }
    final onlyTags =
        previous != null &&
        encode({...previous.toJson()}..remove('tagIds')) ==
            encode({...task.toJson()}..remove('tagIds'));
    await db
        .into(db.definitions)
        .insertOnConflictUpdate(
          DefinitionsCompanion.insert(
            id: task.id,
            payload: encode(task.toJson()),
          ),
        );
    if (existing != null) {
      await (db.delete(db.revisions)..where(
            (r) =>
                r.taskId.equals(task.id) &
                r.effective.isBiggerOrEqualValue(dayKey(from)),
          ))
          .go();
    }
    await db
        .into(db.revisions)
        .insertOnConflictUpdate(
          RevisionsCompanion.insert(
            taskId: task.id,
            effective: dayKey(existing == null ? task.date : from),
            payload: encode(task.toJson()),
          ),
        );
    // A removal hides records through a durable cutoff, never by rewriting or
    // discarding their saved states, history, locks or progress.
    if (task.removedFrom != null) return;
    final rows =
        await (db.select(db.executions)..where(
              (t) =>
                  t.taskId.equals(task.id) &
                  t.day.isBiggerOrEqualValue(dayKey(from)),
            ))
            .get();
    for (final row in rows) {
      final o = Occurrence.fromJson(decode(row.payload));
      // Archiving stops generation, but never removes a materialized fixed block.
      // Explicit definition edits may still update unstarted strict occurrences.
      final keepArchivedBlock = task.archived && o.reserved && o.start != null;
      if (o.status == TaskStatus.pending &&
          !o.exception &&
          !o.locked &&
          o.checked.isEmpty &&
          !o.hasStarted(from) &&
          !keepArchivedBlock) {
        if (onlyTags) {
          await db
              .into(db.executions)
              .insertOnConflictUpdate(
                ExecutionsCompanion.insert(
                  taskId: row.taskId,
                  day: row.day,
                  payload: encode(
                    o
                        .copy(
                          task: Task.fromJson({
                            ...o.task.toJson(),
                            'tagIds': task.tagIds,
                          }),
                        )
                        .toJson(),
                  ),
                ),
              );
          continue;
        }
        await (db.delete(db.executions)..where(
              (t) => t.taskId.equals(row.taskId) & t.day.equals(row.day),
            ))
            .go();
      }
    }
  });
  @override
  Future<void> removeActivity(String taskId, DateTime from) => db.transaction(
    () async {
      final row = await (db.select(
        db.definitions,
      )..where((t) => t.id.equals(taskId))).getSingleOrNull();
      if (row == null) throw StateError('The activity no longer exists.');
      // Details can contain an old occurrence snapshot. Archive the current
      // definition by ID instead of replacing it with that historical snapshot.
      final task = Task.fromJson(decode(row.payload));
      if (task.removedFrom != null) return;
      await saveTask(
        Task.fromJson({
          ...task.toJson(),
          'archived': true,
          'removedFrom': dayKey(from),
        }),
        from,
      );
    },
  );
  @override
  Future<void> saveOccurrences(List<Occurrence> occurrences) =>
      _saveOccurrences(occurrences);
  Future<void> _saveOccurrences(
    List<Occurrence> occurrences, {
    bool restoring = false,
  }) => db.transaction(() async {
    for (final o in occurrences) {
      Occurrence.fromJson(o.toJson());
      await _validateTags(o.task);
      if (!restoring) {
        final row = await (db.select(
          db.definitions,
        )..where((t) => t.id.equals(o.task.id))).getSingleOrNull();
        final removedFrom = row == null
            ? null
            : Task.fromJson(decode(row.payload)).removedFrom;
        if (removedFrom != null && !dateOnly(o.day).isBefore(removedFrom)) {
          throw StateError(
            'This activity has been removed and cannot be restored.',
          );
        }
      }
      await db
          .into(db.executions)
          .insertOnConflictUpdate(
            ExecutionsCompanion.insert(
              taskId: o.task.id,
              day: dayKey(o.day),
              payload: encode(o.toJson()),
            ),
          );
    }
  });
  @override
  Future<Preferences> preferences() async {
    final row = await (db.select(
      db.settings,
    )..where((t) => t.id.equals('preferences'))).getSingleOrNull();
    return row == null
        ? Preferences()
        : Preferences.fromJson(decode(row.payload));
  }

  @override
  Future<void> savePreferences(Preferences preferences) async {
    Preferences.fromJson(preferences.toJson());
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            id: 'preferences',
            payload: encode(preferences.toJson()),
          ),
        );
  }

  @override
  Future<String> exportBackup() => db.transaction(
    () async => const JsonEncoder.withIndent('  ').convert({
      // This wire identifier is intentionally stable across product renames.
      'format': 'calendario-local',
      'version': 4,
      'tags': (await tags()).map((t) => t.toJson()).toList(),
      'revisions': (await db.select(db.revisions).get())
          .map((r) => {'effective': r.effective, 'task': decode(r.payload)})
          .toList(),
      'tasks': (await tasks()).map((t) => t.toJson()).toList(),
      'occurrences': (await db.select(db.executions).get())
          .map((e) => decode(e.payload))
          .toList(),
      'preferences': (await preferences()).toJson(),
    }),
  );
  static void validateBackup(String contents) {
    if (contents.length > 50 * 1024 * 1024) {
      throw const FormatException('The backup exceeds 50 MB.');
    }
    final j = Map<String, dynamic>.from(jsonDecode(contents));
    if (j['format'] != 'calendario-local' ||
        ![1, 2, 3, 4].contains(j['version'])) {
      throw const FormatException('Unsupported backup format or version.');
    }
    final catalogue = j['version'] == 1
        ? defaultTags
        : (j['tags'] as List)
              .map((v) => Tag.fromJson(Map<String, dynamic>.from(v)))
              .toList();
    final tagIds = catalogue.map((t) => t.id).toSet();
    if (tagIds.length != catalogue.length ||
        catalogue.map((t) => t.normalizedName).toSet().length !=
            catalogue.length ||
        !defaultTags.every((t) => tagIds.contains(t.id)) ||
        catalogue.any((t) => t.id.startsWith('tag-') && !t.predefined)) {
      throw const FormatException('Duplicate or incomplete tag catalogue.');
    }
    void checkTags(Task task) {
      if (j['version'] < 4 && task.autoWindow != null) {
        throw const FormatException('This data requires backup version 4.');
      }
      if (j['version'] < 3 &&
          (task.endDate != null || task.removedFrom != null)) {
        throw const FormatException('This data requires backup version 3.');
      }
      if (!task.tagIds.every(tagIds.contains) ||
          (j['version'] == 1 && task.tagIds.isNotEmpty)) {
        throw const FormatException('Invalid tag references.');
      }
    }

    final tasks = (j['tasks'] as List)
        .map((v) => Task.fromJson(Map<String, dynamic>.from(v)))
        .toList();
    tasks.forEach(checkTags);
    final ids = tasks.map((t) => t.id).toSet();
    if (ids.length != tasks.length) {
      throw const FormatException('Duplicate tasks.');
    }
    final seen = <String>{};
    final revisions = <String>{};
    final latest = <String, Map<String, dynamic>>{};
    for (final r in j['revisions'] as List) {
      final t = Task.fromJson(Map<String, dynamic>.from(r['task']));
      checkTags(t);
      final date = r['effective'] as String;
      parseDay(date);
      if (!ids.contains(t.id) || !revisions.add('${t.id}/$date')) {
        throw const FormatException('Invalid revision.');
      }
      if (!latest.containsKey(t.id) ||
          date.compareTo(latest[t.id]!['effective'] as String) > 0) {
        latest[t.id] = Map<String, dynamic>.from(r);
      }
    }
    if (!tasks.every(
      (t) => (j['revisions'] as List).any((r) => r['task']['id'] == t.id),
    )) {
      throw const FormatException('Missing revisions.');
    }
    for (final t in tasks) {
      if (encode(
                Task.fromJson(
                  Map<String, dynamic>.from(latest[t.id]!['task']),
                ).toJson(),
              ) !=
              encode(t.toJson()) ||
          (t.removedFrom != null &&
              latest[t.id]!['effective'] != dayKey(t.removedFrom!))) {
        throw const FormatException(
          'The definition does not match its latest revision.',
        );
      }
    }
    for (final v in j['occurrences'] as List) {
      final o = Occurrence.fromJson(Map<String, dynamic>.from(v));
      checkTags(o.task);
      if (!ids.contains(o.task.id) || !seen.add(o.id)) {
        throw const FormatException(
          'Duplicate occurrences or occurrences without a task.',
        );
      }
    }
    Preferences.fromJson(Map<String, dynamic>.from(j['preferences']));
  }

  @override
  Future<void> importBackup(String contents) async {
    validateBackup(contents);
    final j = decode(contents);
    await db.transaction(() async {
      await db.delete(db.executions).go();
      await db.delete(db.revisions).go();
      await db.delete(db.definitions).go();
      await db.delete(db.settings).go();
      await db.delete(db.tags).go();
      final catalogue = j['version'] == 1
          ? defaultTags
          : (j['tags'] as List)
                .map((v) => Tag.fromJson(Map<String, dynamic>.from(v)))
                .toList();
      for (final tag in catalogue) {
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(id: tag.id, payload: encode(tag.toJson())),
            );
      }
      for (final t in j['tasks'] as List) {
        final task = Task.fromJson(Map<String, dynamic>.from(t));
        await db
            .into(db.definitions)
            .insert(
              DefinitionsCompanion.insert(
                id: task.id,
                payload: encode(task.toJson()),
              ),
            );
      }
      for (final r in j['revisions'] as List) {
        final t = Task.fromJson(Map<String, dynamic>.from(r['task']));
        await db
            .into(db.revisions)
            .insert(
              RevisionsCompanion.insert(
                taskId: t.id,
                effective: r['effective'],
                payload: encode(t.toJson()),
              ),
            );
      }
      await _saveOccurrences(
        (j['occurrences'] as List)
            .map((v) => Occurrence.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        restoring: true,
      );
      await savePreferences(
        Preferences.fromJson(Map<String, dynamic>.from(j['preferences'])),
      );
      if (j['version'] < 3) await db.upgradeLegacyRemovals();
    });
  }
}
