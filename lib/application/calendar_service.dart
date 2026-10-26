import '../data/repository.dart';
import '../domain/model.dart';
import '../domain/planner.dart';

class CalendarService {
  final CalendarRepository repository;
  final Planner planner;
  CalendarService(this.repository, {this.planner = const Planner()});
  Future<void> removeActivity(String taskId) =>
      repository.removeActivity(taskId, planner.clock.now());
  Future<Plan> day(DateTime day) async {
    if (!isCalendarDay(day)) {
      throw const FormatException('The date must be between 2000 and 2100.');
    }
    final tasks = await repository.tasksForDay(day);
    final stored = await repository.occurrences(day);
    final ids = stored.map((o) => o.task.id).toSet();
    final items = [
      ...stored,
      for (final t in tasks)
        if (!ids.contains(t.id) && t.occurs(day))
          Occurrence(task: t, day: dateOnly(day)),
    ];
    final prefs = await repository.preferences();
    final plan = planner.plan(day, prefs.availability[day.weekday]!, items);
    // Materialize only visited days; past snapshots and per-date states are stable.
    await repository.saveOccurrences(plan.items);
    return plan;
  }

  Future<void> save(Task task) async {
    task.validate();
    await repository.saveTask(task, planner.clock.now());
  }

  Future<void> update(Occurrence o) => repository.saveOccurrences([o]);
  Future<void> assign(Occurrence o, int start) async {
    if (o.task.kind == TaskKind.strict) {
      throw StateError('Edit the fixed activity\'s time.');
    }
    final span = Span(start, start + o.task.duration);
    if (o.task.autoWindow != null && !o.task.autoWindow!.contains(span)) {
      throw StateError('The block must fit within the activity time window.');
    }
    final prefs = await repository.preferences();
    if (!prefs.availability[o.day.weekday]!.contains(span)) {
      throw StateError('The block must fit within availability.');
    }
    final plan = await day(o.day);
    final now = planner.clock.now();
    for (final other in plan.items) {
      if (other.id != o.id &&
          other.status != TaskStatus.skipped &&
          other.isProtectedAt(now) &&
          other.start != null &&
          span.overlaps(
            Span(other.start!, other.start! + other.task.duration),
          )) {
        throw StateError(
          'This time overlaps with ${other.task.title}. Choose another slot.',
        );
      }
    }
    await update(o.copy(assigned: start, locked: true, exception: true));
  }

  Future<List<String>> conflicts(Task task, {DateTime? onlyDay}) async {
    if (task.kind != TaskKind.strict) return [];
    final found = <String>{};
    final all = await repository.tasks();
    final now = planner.clock.now();
    final first =
        onlyDay ?? (task.date.isAfter(now) ? task.date : dateOnly(now));
    // Every supported rule repeats within seven days. Also inspect the start
    // of later definitions and all materialized manual exceptions.
    final dates = <String, DateTime>{dayKey(first): first};
    if (onlyDay == null) {
      for (final t in all.where((t) => !t.archived)) {
        final anchor = t.date.isAfter(first) ? t.date : first;
        for (var i = 0; i < 7; i++) {
          final d = DateTime(anchor.year, anchor.month, anchor.day + i);
          dates[dayKey(d)] = d;
        }
      }
      for (final o in await repository.allOccurrences()) {
        if (!o.day.isBefore(first)) dates[dayKey(o.day)] = o.day;
      }
    }
    for (final d in dates.values) {
      if (onlyDay == null && !task.occurs(d)) continue;
      final saved = await repository.occurrences(d);
      final items = [
        ...saved,
        for (final t in all)
          if (t.id != task.id &&
              t.occurs(d) &&
              !saved.any((o) => o.task.id == t.id))
            Occurrence(task: t, day: d),
      ];
      for (final o in items) {
        if (o.task.id != task.id &&
            o.status != TaskStatus.skipped &&
            o.isProtectedAt(now) &&
            o.start != null &&
            Span(
              task.start,
              task.start + task.duration,
            ).overlaps(Span(o.start!, o.start! + o.task.duration))) {
          found.add('${dayKey(d)} · ${o.task.title}');
        }
      }
    }
    return found.toList();
  }
}
