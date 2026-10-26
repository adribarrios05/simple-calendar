import 'model.dart';

abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FixedClock implements Clock {
  final DateTime value;
  const FixedClock(this.value);
  @override
  DateTime now() => value;
}

class Plan {
  final List<Occurrence> items;
  final Map<String, List<String>> issues;
  final List<Span> free;
  const Plan(this.items, this.issues, this.free);
}

/// Stable first fit. Protected intervals are never moved, even if conflicting.
class Planner {
  static const startStepMinutes = 5;
  static int _roundStart(int minute) =>
      ((minute + startStepMinutes - 1) ~/ startStepMinutes) * startStepMinutes;
  final Clock clock;
  const Planner({this.clock = const SystemClock()});
  Plan plan(DateTime day, Span available, List<Occurrence> input) {
    final issues = <String, List<String>>{};
    void warn(Occurrence o, String message) =>
        issues.putIfAbsent(o.id, () => []).add(message);
    final now = clock.now();
    final today = dayKey(day) == dayKey(now);
    final past = dateOnly(day).isBefore(dateOnly(now));
    final floor = today
        ? now.hour * 60 +
              now.minute +
              (now.second > 0 || now.millisecond > 0 || now.microsecond > 0
                  ? 1
                  : 0)
        : available.start;
    final occupied = <Span>[];
    final result = <Occurrence>[];
    final active = input.where((o) => o.status != TaskStatus.skipped).toList();
    final protected = active
        .where((o) => o.isProtectedAt(now) || past)
        .toList();
    for (final o in protected) {
      result.add(o);
      if (o.start == null) continue;
      final span = Span(o.start!, o.start! + o.task.duration);
      if (o.task.autoWindow != null && !o.task.autoWindow!.contains(span)) {
        warn(o, 'Outside the activity time window. Move or unlock the block.');
      }
      if (o.task.kind != TaskKind.strict && !available.contains(span)) {
        warn(o, 'Outside availability. Move or unlock the block.');
      }
      for (final other in result.take(result.length - 1)) {
        if (other.start != null &&
            span.overlaps(
              Span(other.start!, other.start! + other.task.duration),
            )) {
          warn(o, 'Conflict with ${other.task.title}.');
          warn(other, 'Conflict with ${o.task.title}.');
        }
      }
      occupied.add(span);
    }
    List<Span> free() {
      var cursor = floor > available.start ? floor : available.start;
      final gaps = <Span>[];
      final sorted = [...occupied]..sort((a, b) => a.start.compareTo(b.start));
      for (final b in sorted) {
        if (b.end <= cursor) continue;
        if (b.start > cursor && cursor < available.end) {
          gaps.add(
            Span(cursor, b.start < available.end ? b.start : available.end),
          );
        }
        if (b.end > cursor) cursor = b.end;
      }
      if (cursor < available.end) gaps.add(Span(cursor, available.end));
      return gaps;
    }

    final autos = active.where((o) => !protected.contains(o)).toList()
      ..sort((a, b) {
        final p = b.task.priority.compareTo(a.task.priority);
        return p != 0 ? p : a.task.id.compareTo(b.task.id);
      });
    // Reserve all still-valid suggestions before placing displaced/new tasks.
    final displaced = <Occurrence>[];
    for (final o in autos) {
      // Started suggestions are already protected above, including off-grid ones.
      final start = o.assigned == null ? null : _roundStart(o.assigned!);
      final span = start == null ? null : Span(start, start + o.task.duration);
      if (span != null &&
          available.contains(span) &&
          (o.task.autoWindow == null || o.task.autoWindow!.contains(span)) &&
          !occupied.any(span.overlaps)) {
        result.add(o.copy(assigned: span.start));
        occupied.add(span);
      } else {
        displaced.add(o.copy(clearAssignment: true));
      }
    }
    for (final o in displaced) {
      final window = o.task.autoWindow;
      final gaps = free()
          .map(
            (s) => window == null
                ? s
                : Span(
                    s.start > window.start ? s.start : window.start,
                    s.end < window.end ? s.end : window.end,
                  ),
          )
          .where((s) => s.end > s.start)
          .map((s) => Span(_roundStart(s.start), s.end))
          .where((s) => s.duration >= o.task.duration);
      if (gaps.isEmpty) {
        result.add(o);
        warn(
          o,
          window == null
              ? 'There is no continuous slot long enough.'
              : 'No continuous slot fits within the activity time window.',
        );
      } else {
        final s = gaps.first.start;
        result.add(o.copy(assigned: s));
        occupied.add(Span(s, s + o.task.duration));
      }
    }
    result.addAll(input.where((o) => o.status == TaskStatus.skipped));
    result.sort((a, b) => (a.start ?? 1500).compareTo(b.start ?? 1500));
    return Plan(result, issues, free());
  }
}
