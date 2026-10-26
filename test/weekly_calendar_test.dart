import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:simple_calendar/domain/model.dart';
import 'package:simple_calendar/domain/planner.dart';
import 'package:simple_calendar/presentation/weekly_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('weekly time grid aligns days and scales task durations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final days = List.generate(7, (i) => DateTime(2026, 10, 19 + i));
    Occurrence item(String id, int minute, int duration, {int day = 0}) =>
        Occurrence(
          task: Task(
            id: id,
            title: id,
            date: days[day],
            kind: TaskKind.strict,
            start: minute,
            duration: duration,
          ),
          day: days[day],
        );
    final morning = item('Mañana', 540, 60);
    final afternoon = item('Tarde', 1020, 120);
    final nextDay = item('Otro día', 540, 60, day: 1);
    final overlap = item('Solapada', 540, 30);
    final short = item('Breve', 660, 5);
    final pending = Occurrence(
      task: Task(
        id: 'pending',
        title: 'Sin asignar',
        date: days[0],
        kind: TaskKind.manual,
      ),
      day: days[0],
    );
    final skipped = item('Omitida', 600, 60).copy(status: TaskStatus.skipped);
    Occurrence? selected;
    DateTime? opened;
    final imageKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: imageKey,
        child: MaterialApp(
          home: Scaffold(
            body: WeeklyCalendar(
              days: days,
              plans: {
                dayKey(days[0]): Plan(
                  [morning, afternoon, overlap, short, pending, skipped],
                  {},
                  [],
                ),
                dayKey(days[1]): Plan([nextDay], {}, []),
              },
              onSelect: (o) => selected = o,
              onOpenDay: (d) => opened = d,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder block(Occurrence o) => find.byKey(ValueKey('week-block-${o.id}'));
    expect(
      tester.getTopLeft(block(afternoon)).dy -
          tester.getTopLeft(block(morning)).dy,
      480,
    );
    expect(tester.getSize(block(afternoon)).height, 120);
    expect(tester.getSize(block(morning)).height, 60);
    expect(tester.getSize(block(short)).height, 5);
    expect(
      tester.getTopLeft(block(nextDay)).dy,
      tester.getTopLeft(block(morning)).dy,
    );
    expect(
      tester.getTopLeft(block(overlap)).dx,
      greaterThanOrEqualTo(tester.getTopRight(block(morning)).dx),
    );
    expect(find.text('○ Sin asignar'), findsOneWidget);
    expect(find.text('− Omitida'), findsOneWidget);
    expect(block(skipped), findsNothing);
    await tester.runAsync(() async {
      final boundary =
          imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('artifacts/weekly-widget.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(block(morning));
    await tester.pumpAndSettle();
    expect(selected?.id, morning.id);
    await tester.tap(find.text('Tue 20/10'));
    expect(opened, days[1]);
    await tester.drag(find.byType(WeeklyCalendar), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(block(nextDay)).dy,
      tester.getTopLeft(block(morning)).dy,
    );
    expect(tester.takeException(), isNull);
  });
}
