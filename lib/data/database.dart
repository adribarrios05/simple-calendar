import 'dart:io';
import 'dart:convert';
import '../domain/tag.dart';
import '../domain/model.dart' show encode, Task;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
part 'database.g.dart';

// v5 protects automatic scheduling windows from older writers.
const calendarSchemaVersion = 5;

class Definitions extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Executions extends Table {
  TextColumn get taskId => text().references(Definitions, #id)();
  TextColumn get day => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {taskId, day};
}

class Settings extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Revisions extends Table {
  TextColumn get taskId => text().references(Definitions, #id)();
  TextColumn get effective => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {taskId, effective};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Definitions, Executions, Settings, Revisions, Tags])
class CalendarDatabase extends _$CalendarDatabase {
  CalendarDatabase(super.executor);
  factory CalendarDatabase.file(File file) =>
      CalendarDatabase(NativeDatabase.createInBackground(file));
  Future<void> seedTags() async {
    for (final tag in defaultTags) {
      await into(
        tags,
      ).insert(TagsCompanion.insert(id: tag.id, payload: encode(tag.toJson())));
    }
  }

  /// Older UI removals were stored as archived definitions. Give those a
  /// durable cutoff at their archival revision, without changing executions.
  Future<void> upgradeLegacyRemovals() async {
    for (final row in await select(definitions).get()) {
      final task = Task.fromJson(
        Map<String, dynamic>.from(jsonDecode(row.payload)),
      );
      if (!task.archived || task.removedFrom != null) continue;
      final latest =
          await (select(revisions)
                ..where((r) => r.taskId.equals(task.id))
                ..orderBy([(r) => OrderingTerm.desc(r.effective)])
                ..limit(1))
              .getSingleOrNull();
      if (latest == null) throw const FormatException('Missing revisions.');
      final revisionTask = Task.fromJson(
        Map<String, dynamic>.from(jsonDecode(latest.payload)),
      );
      if (encode(revisionTask.toJson()) != encode(task.toJson())) {
        throw const FormatException(
          'The definition does not match its latest revision.',
        );
      }
      final removed = Task.fromJson({
        ...task.toJson(),
        'removedFrom': latest.effective,
      });
      final payload = encode(removed.toJson());
      await (update(definitions)..where((d) => d.id.equals(task.id))).write(
        DefinitionsCompanion(payload: Value(payload)),
      );
      await (update(revisions)..where(
            (r) =>
                r.taskId.equals(task.id) & r.effective.equals(latest.effective),
          ))
          .write(RevisionsCompanion(payload: Value(payload)));
    }
  }

  @override
  int get schemaVersion => calendarSchemaVersion;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await seedTags();
    }),
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 4 || to != calendarSchemaVersion) {
        throw StateError('Unsupported migration: $from → $to');
      }
      await transaction(() async {
        if (from == 1) {
          await m.createTable(revisions);
          await customStatement(
            "INSERT INTO revisions(task_id, effective, payload) SELECT id, json_extract(payload, '\$.date'), payload FROM definitions",
          );
        }
        if (from < 3) {
          await m.createTable(tags);
          await seedTags();
        }
        if (from < 4) await upgradeLegacyRemovals();
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
