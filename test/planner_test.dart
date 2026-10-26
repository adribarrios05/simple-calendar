import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';

void main() {
  final day = DateTime(2026, 10, 22);
  final planner = Planner(clock: FixedClock(DateTime(2026, 10, 21, 12)));
  Occurrence item(
    String id, {
    TaskKind kind = TaskKind.automatic,
    int duration = 60,
    int start = 540,
    int? assigned,
    bool locked = false,
    int priority = 1,
  }) => Occurrence(
    task: Task(
      id: id,
      title: id,
      date: day,
      kind: kind,
      duration: duration,
      start: start,
      priority: priority,
    ),
    day: day,
    assigned: assigned,
    locked: locked,
  );
  int? startOf(Plan p, String id) =>
      p.items.singleWhere((o) => o.task.id == id).start;
  test('free day and continuous first fit', () {
    final p = planner.plan(day, const Span(480, 1320), [
      item('a', duration: 120),
      item('b'),
    ]);
    expect(startOf(p, 'a'), 480);
    expect(startOf(p, 'b'), 600);
    expect(p.issues, isEmpty);
  });
  test('fully occupied day keeps unscheduled tasks', () {
    final p = planner.plan(day, const Span(480, 600), [
      item('fixed', kind: TaskKind.strict, start: 480, duration: 120),
      item('a'),
    ]);
    expect(startOf(p, 'a'), isNull);
    expect(p.items, hasLength(2));
    expect(p.issues, isNotEmpty);
  });
  test('end exclusive allows consecutive strict tasks', () {
    final p = planner.plan(day, const Span(480, 720), [
      item('x', kind: TaskKind.strict, start: 480),
      item('y', kind: TaskKind.strict, start: 540),
      item('a'),
    ]);
    expect(p.issues, isEmpty);
    expect(startOf(p, 'a'), 600);
  });
  test('protected overlap warns both and never moves', () {
    final p = planner.plan(day, const Span(480, 720), [
      item('x', kind: TaskKind.strict, start: 480, duration: 90),
      item('y', assigned: 540, locked: true),
    ]);
    expect(p.issues, hasLength(2));
    expect(startOf(p, 'y'), 540);
  });
  test('does not split across small gaps', () {
    final p = planner.plan(day, const Span(480, 660), [
      item('x', kind: TaskKind.strict, start: 540),
      item('a', duration: 120),
    ]);
    expect(startOf(p, 'a'), isNull);
    expect(p.free.map((s) => s.duration), [60, 60]);
  });
  test('priority then stable id order independent of input order', () {
    final tasks = [
      item('z', priority: 0),
      item('b', priority: 2),
      item('a', priority: 2),
    ];
    final a = planner.plan(day, const Span(480, 600), tasks);
    final b = planner.plan(day, const Span(480, 600), tasks.reversed.toList());
    expect(
      a.items.map((o) => o.toJson()).toList(),
      b.items.map((o) => o.toJson()).toList(),
    );
    expect(startOf(a, 'a'), 480);
    expect(startOf(a, 'b'), 540);
    expect(startOf(a, 'z'), isNull);
  });
  test('strict edit displaces only affected suggestions', () {
    final p = planner.plan(day, const Span(480, 900), [
      item('fixed', kind: TaskKind.strict, start: 480),
      item('a', assigned: 480),
      item('b', assigned: 660),
    ]);
    expect(startOf(p, 'a'), 540);
    expect(startOf(p, 'b'), 660);
  });
  test('manual and locked assignments preserved; manual unassigned stays', () {
    final p = planner.plan(day, const Span(480, 900), [
      item('m', kind: TaskKind.manual, assigned: 480),
      item('l', assigned: 540, locked: true),
      item('u', kind: TaskKind.manual),
      item('a'),
    ]);
    expect(startOf(p, 'm'), 480);
    expect(startOf(p, 'l'), 540);
    expect(startOf(p, 'u'), isNull);
    expect(startOf(p, 'a'), 600);
  });
  test('availability bounds and explicit manual warning', () {
    final p = planner.plan(day, const Span(600, 660), [
      item('m', kind: TaskKind.manual, assigned: 480),
      item('a', duration: 61),
      item('b', duration: 60),
    ]);
    expect(p.issues.keys, contains('${'m'}/${dayKey(day)}'));
    expect(startOf(p, 'a'), isNull);
    expect(startOf(p, 'b'), 600);
  });
  test('new assignments never start in the past today', () {
    final p = Planner(
      clock: FixedClock(DateTime(2026, 10, 22, 12, 13, 5)),
    ).plan(day, const Span(480, 1320), [item('a')]);
    expect(startOf(p, 'a'), 735);
  });
  test(
    'rounds availability and strict block ends up to five-minute starts',
    () {
      final p = planner.plan(day, const Span(483, 720), [
        item('fixed', kind: TaskKind.strict, start: 485, duration: 13),
        item('a', duration: 13),
        item('b', duration: 10),
      ]);
      expect(startOf(p, 'fixed'), 485);
      expect(startOf(p, 'a'), 500);
      expect(startOf(p, 'b'), 515);
    },
  );
  test('skips a gap when rounding leaves too little space', () {
    final p = planner.plan(day, const Span(483, 600), [
      item('fixed', kind: TaskKind.strict, start: 493, duration: 14),
      item('a', duration: 10),
    ]);
    expect(startOf(p, 'a'), 510);
    final full = planner.plan(day, const Span(483, 493), [
      item('a', duration: 10),
    ]);
    expect(startOf(full, 'a'), isNull);
    expect(full.issues, isNotEmpty);
  });
  test('today rounds 17:48 to 17:50 and respects exact boundaries', () {
    for (final (now, expected) in [
      (DateTime(2026, 10, 22, 17, 48), 1070),
      (DateTime(2026, 10, 22, 17, 45), 1065),
      (DateTime(2026, 10, 22, 17, 45, 0, 1), 1070),
      (DateTime(2026, 10, 22, 23, 59, 59), null),
    ]) {
      final p = Planner(
        clock: FixedClock(now),
      ).plan(day, const Span(480, 1440), [item('a')]);
      expect(startOf(p, 'a'), expected);
    }
  });
  test(
    'aligns future suggestions while preserving manual and locked times',
    () {
      final p = planner.plan(day, const Span(480, 1320), [
        item('a', assigned: 1068, duration: 30),
        item('m', kind: TaskKind.manual, assigned: 483),
        item('l', assigned: 603, locked: true),
      ]);
      expect(startOf(p, 'a'), 1070);
      expect(startOf(p, 'm'), 483);
      expect(startOf(p, 'l'), 603);
      expect(
        planner
            .plan(day, const Span(480, 1320), p.items)
            .items
            .map((o) => o.toJson()),
        p.items.map((o) => o.toJson()),
      );
    },
  );
  test('rounding an old suggestion cannot create a protected overlap', () {
    final p = planner.plan(day, const Span(483, 720), [
      item('fixed', kind: TaskKind.strict, start: 544, duration: 60),
      item('a', assigned: 483),
    ]);
    expect(startOf(p, 'a'), 605);
    expect(p.issues, isEmpty);
  });
  test('already-started off-grid suggestions preserve their position', () {
    final p = Planner(
      clock: FixedClock(DateTime(2026, 10, 22, 17, 49)),
    ).plan(day, const Span(480, 1320), [item('a', assigned: 1068)]);
    expect(startOf(p, 'a'), 1068);
  });
  test('existing valid ongoing block is not moved by the clock', () {
    final p = Planner(
      clock: FixedClock(DateTime(2026, 10, 22, 12, 13)),
    ).plan(day, const Span(480, 1320), [item('a', assigned: 720)]);
    expect(startOf(p, 'a'), 720);
  });
  test('past day never invents automatic assignments', () {
    final p = Planner(
      clock: FixedClock(DateTime(2026, 10, 23)),
    ).plan(day, const Span(480, 1320), [item('a'), item('b', assigned: 600)]);
    expect(startOf(p, 'a'), isNull);
    expect(startOf(p, 'b'), 600);
  });
  test('closed day and skipped activity', () {
    final p = planner.plan(day, const Span(480, 480), [
      item('a'),
      item('s', kind: TaskKind.strict).copy(status: TaskStatus.skipped),
    ]);
    expect(startOf(p, 'a'), isNull);
    expect(p.free, isEmpty);
  });
  test('500 deterministic randomized schedules preserve invariants', () {
    final random = Random(42);
    for (var trial = 0; trial < 500; trial++) {
      final input = List.generate(
        15,
        (i) => item(
          '$i',
          duration: 1 + random.nextInt(180),
          priority: random.nextInt(3),
        ),
      );
      final plan = planner.plan(day, const Span(480, 1320), input);
      final placed = plan.items.where((o) => o.start != null).toList();
      for (var i = 0; i < placed.length; i++) {
        final a = Span(
          placed[i].start!,
          placed[i].start! + placed[i].task.duration,
        );
        expect(const Span(480, 1320).contains(a), true);
        expect(a.start % 5, 0);
        for (var j = i + 1; j < placed.length; j++) {
          expect(
            a.overlaps(
              Span(
                placed[j].start!,
                placed[j].start! + placed[j].task.duration,
              ),
            ),
            false,
          );
        }
      }
      expect(plan.items, hasLength(input.length));
    }
  });
}
