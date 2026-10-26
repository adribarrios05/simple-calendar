import '../l10n/app_strings.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/model.dart';
import '../domain/planner.dart';
import 'task_editor.dart';
import 'tags.dart';
import '../domain/tag.dart';

/// One shared scroll and minute scale keep all seven days aligned.
class WeeklyCalendar extends StatefulWidget {
  final List<DateTime> days;
  final Map<String, Plan> plans;
  final List<Tag> tags;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<Occurrence> onSelect;
  const WeeklyCalendar({
    super.key,
    required this.days,
    required this.plans,
    this.tags = const [],
    required this.onOpenDay,
    required this.onSelect,
  });
  @override
  State<WeeklyCalendar> createState() => _WeeklyCalendarState();
}

class _WeeklyCalendarState extends State<WeeklyCalendar> {
  final scroll = ScrollController(initialScrollOffset: 420);
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  List<Occurrence> items(DateTime d) => widget.plans[dayKey(d)]?.items ?? [];
  bool timed(Occurrence o) => o.start != null && o.status != TaskStatus.skipped;
  bool listed(Occurrence o) => !timed(o) || o.task.duration < 34;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor.withValues(alpha: .25);
    final hasUnscheduled = widget.days.any((d) => items(d).any(listed));
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(box.maxWidth, 64 + widget.days.length * 140.0);
        final columnWidth = (width - 64) / widget.days.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Text(context.strings.text('Time')),
                        ),
                      ),
                      for (final d in widget.days)
                        SizedBox(
                          width: columnWidth,
                          child: TextButton(
                            onPressed: isCalendarDay(d)
                                ? () => widget.onOpenDay(d)
                                : null,
                            child: Text(
                              '${weekdayLabels(context)[d.weekday - 1]} ${d.day}/${d.month}',
                              style: TextStyle(
                                fontWeight: dayKey(d) == dayKey(DateTime.now())
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasUnscheduled)
                  SizedBox(
                    height: 112,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 64,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Text(
                              context.strings.text(
                                'Unscheduled / skipped / short',
                              ),
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        for (final d in widget.days)
                          SizedBox(
                            width: columnWidth,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: divider),
                                ),
                              ),
                              child: ListView(
                                padding: EdgeInsets.all(4),
                                children: [
                                  for (final o in [
                                    ...items(d).where((o) => !timed(o)),
                                    ...items(
                                      d,
                                    ).where((o) => timed(o) && listed(o)),
                                  ])
                                    Tooltip(
                                      message:
                                          '${o.task.title} · ${o.task.duration} min${o.status == TaskStatus.skipped ? context.strings.text(' · Skipped') : ''}',
                                      child: TextButton(
                                        key: ValueKey('week-list-${o.id}'),
                                        onPressed: () => widget.onSelect(o),
                                        child: Text(
                                          '${timed(o)
                                              ? '${timeLabel(o.start!)} ·'
                                              : o.status == TaskStatus.skipped
                                              ? '−'
                                              : '○'} ${o.task.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: SizedBox(
                      height: 1456,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 64,
                            child: Stack(
                              children: [
                                for (var h = 0; h <= 24; h++)
                                  Positioned(
                                    top: h * 60.0,
                                    left: 8,
                                    child: Text(
                                      timeLabel(h * 60),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (final d in widget.days)
                            SizedBox(
                              width: columnWidth,
                              height: 1440,
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    dayColumn(d, constraints.maxWidth, divider),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget dayColumn(DateTime day, double width, Color divider) {
    final scheduled = items(day).where(timed).toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    final lanes = <List<Occurrence>>[];
    final laneFor = <String, int>{};
    for (final o in scheduled) {
      final span = Span(o.start!, o.start! + o.task.duration);
      var lane = 0;
      while (lane < lanes.length &&
          lanes[lane].any(
            (other) => span.overlaps(
              Span(other.start!, other.start! + other.task.duration),
            ),
          )) {
        lane++;
      }
      if (lane == lanes.length) lanes.add([]);
      lanes[lane].add(o);
      laneFor[o.id] = lane;
    }
    final laneWidth = width / math.max(1, lanes.length);
    final now = DateTime.now();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: divider)),
      ),
      child: Stack(
        children: [
          for (var half = 0; half < 48; half++)
            Positioned(
              top: half * 30.0,
              left: 0,
              right: 0,
              child: Divider(
                height: 1,
                color: divider.withValues(alpha: half.isEven ? .35 : .12),
              ),
            ),
          for (final o in scheduled)
            Positioned(
              key: ValueKey('week-block-${o.id}'),
              top: o.start!.toDouble(),
              left: laneFor[o.id]! * laneWidth + 2,
              width: laneWidth - 4,
              height: o.task.duration.toDouble(),
              child: block(o),
            ),
          if (dayKey(day) == dayKey(now))
            Positioned(
              top: (now.hour * 60 + now.minute).toDouble(),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget block(Occurrence o) {
    final suggested =
        o.task.kind == TaskKind.automatic &&
        !o.locked &&
        o.status == TaskStatus.pending;
    final warning =
        widget.plans[dayKey(o.day)]?.issues.containsKey(o.id) ?? false;
    final color = Color(o.task.color);
    final label =
        '${o.task.title}\n${timeLabel(o.start!)}–${timeLabel(o.start! + o.task.duration)} · ${o.task.duration} min\n${suggested ? context.strings.text('Suggested') : kindLabels(context)[o.task.kind.index]}${warning ? context.strings.text('\nThere is a conflict. Open the details.') : ''}\n${tagNames(context, o.task.tagIds, widget.tags)}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: Material(
          color: color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .3 : .14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(
              color: warning ? Theme.of(context).colorScheme.error : color,
              width: suggested ? 1 : 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onSelect(o),
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  // Clip content without enlarging short tasks or overflowing their slot.
                  if (box.maxHeight >= 18)
                    Positioned(
                      top: 3,
                      left: 5,
                      right: 4,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${o.status == TaskStatus.completed
                                  ? '✓ '
                                  : o.locked
                                  ? '▣ '
                                  : ''}${o.task.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: o.status == TaskStatus.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (box.maxWidth >= 80 && o.task.tagIds.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(left: 3),
                              child: TagMarker(o.task.tagIds, widget.tags),
                            ),
                        ],
                      ),
                    ),
                  if (box.maxHeight >= 42)
                    Positioned(
                      top: 23,
                      left: 5,
                      right: 4,
                      child: Text(
                        '${timeLabel(o.start!)}–${timeLabel(o.start! + o.task.duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (box.maxHeight >= 65)
                    Positioned(
                      top: 43,
                      left: 5,
                      right: 4,
                      child: Text(
                        suggested
                            ? context.strings.text('Suggested')
                            : kindLabels(context)[o.task.kind.index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
