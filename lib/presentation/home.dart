import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/controller.dart';
import '../domain/model.dart';
import 'task_editor.dart';
import 'settings.dart';
import 'weekly_calendar.dart';
import 'tags.dart';
import '../domain/tag.dart';

class CalendarHome extends ConsumerStatefulWidget {
  const CalendarHome({super.key});
  @override
  ConsumerState<CalendarHome> createState() => _CalendarHomeState();
}

class _CalendarHomeState extends ConsumerState<CalendarHome> {
  final timelineScroll = ScrollController(initialScrollOffset: 435);
  @override
  void dispose() {
    timelineScroll.dispose();
    super.dispose();
  }

  String search = '';
  String? tagFilter;
  TaskKind? filter;
  TaskStatus? statusFilter;
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(calendarProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            openTaskEditor(context, c),
        SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
            c.navigate(0, c.today),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: MediaQuery.sizeOf(context).width > 900,
                  minExtendedWidth: 185,
                  selectedIndex: c.view,
                  leading: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/branding/app_icon.png',
                          width: 40,
                          height: 40,
                          semanticLabel: context.strings.text(
                            'Simple Calendar',
                          ),
                        ),
                        SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: () => openTaskEditor(context, c),
                          icon: Icon(Icons.add),
                          label: Text(context.strings.text('Create')),
                        ),
                      ],
                    ),
                  ),
                  destinations: [
                    NavigationRailDestination(
                      icon: Icon(Icons.today_outlined),
                      label: Text(context.strings.text('Today')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.view_week_outlined),
                      label: Text(context.strings.text('Week')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      label: Text(context.strings.text('Month')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.checklist),
                      label: Text(context.strings.text('Tasks')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.repeat),
                      label: Text(context.strings.text('Routines')),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune),
                      label: Text(context.strings.text('Settings')),
                    ),
                  ],
                  onDestinationSelected: (v) =>
                      c.navigate(v, v == 0 ? c.today : null),
                ),
                VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(24, 18, 20, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      context.strings.text('Your day'),
                                      context.strings.text('Your week'),
                                      context.strings.text('Your month'),
                                      context.strings.text('Tasks'),
                                      context.strings.text('Routines'),
                                      context.strings.text('Settings'),
                                    ][c.view],
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    c.view < 3
                                        ? dayKey(c.date)
                                        : context.strings.text(
                                            'Your time, your way',
                                          ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (c.view < 3) ...[
                              IconButton(
                                tooltip: context.strings.text('Previous'),
                                onPressed: c.canShift(-1)
                                    ? () => c.shift(-1)
                                    : null,
                                icon: Icon(Icons.chevron_left),
                              ),
                              TextButton(
                                onPressed: () => c.navigate(c.view, c.today),
                                child: Text(context.strings.text('Today')),
                              ),
                              IconButton(
                                tooltip: context.strings.text('Next'),
                                onPressed: c.canShift(1)
                                    ? () => c.shift(1)
                                    : null,
                                icon: Icon(Icons.chevron_right),
                              ),
                              IconButton(
                                tooltip: context.strings.text('Go to date'),
                                icon: Icon(Icons.event),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: c.date,
                                    firstDate: firstCalendarDay,
                                    lastDate: lastCalendarDay,
                                  );
                                  if (d != null) c.navigate(c.view, d);
                                },
                              ),
                            ],
                            IconButton(
                              tooltip: context.strings.text('Refresh schedule'),
                              onPressed: c.loading ? null : c.refresh,
                              icon: Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ),
                      if (c.loading)
                        LinearProgressIndicator(minHeight: 2)
                      else
                        Divider(height: 2),
                      if (c.error != null)
                        MaterialBanner(
                          content: Text(context.strings.error(c.error!)),
                          actions: [
                            TextButton(
                              onPressed: c.refresh,
                              child: Text(context.strings.text('Retry')),
                            ),
                          ],
                        ),
                      Expanded(
                        child: c.view == 5
                            ? SettingsView(controller: c)
                            : c.view >= 3
                            ? taskList(c)
                            : c.view == 2
                            ? month(c)
                            : c.view == 1
                            ? week(c)
                            : day(c),
                      ),
                    ],
                  ),
                ),
                if (c.selected != null && wide)
                  SizedBox(width: 300, child: details(c, c.selected!)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void select(CalendarController c, Occurrence o) {
    c.select(o);
    if (MediaQuery.sizeOf(context).width < 1100) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: Consumer(
            builder: (_, ref, _) {
              final current = ref.watch(calendarProvider);
              return details(
                current,
                current.selected ?? o,
                onClose: () {
                  current.deselect();
                  Navigator.pop(sheetContext);
                },
              );
            },
          ),
        ),
      );
    }
  }

  Widget activity(
    CalendarController c,
    Occurrence o, {
    bool compact = false,
    bool short = false,
  }) {
    final warnings = c.plans[dayKey(o.day)]?.issues[o.id] ?? [];
    final suggested =
        o.task.kind == TaskKind.automatic &&
        !o.locked &&
        o.status == TaskStatus.pending;
    final color = Color(o.task.color);
    return Draggable<Occurrence>(
      data: o,
      maxSimultaneousDrags:
          o.task.kind == TaskKind.strict || o.status != TaskStatus.pending
          ? 0
          : 1,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 200,
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(o.task.title),
          ),
        ),
      ),
      child: Card(
        color: color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? .23 : .10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: warnings.isNotEmpty
                ? Theme.of(context).colorScheme.error
                : color.withValues(alpha: suggested ? .4 : .9),
            width: suggested ? 1 : 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => select(c, o),
          child: short
              ? SizedBox.expand()
              : Padding(
                  padding: EdgeInsets.all(compact ? 6 : 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            o.status == TaskStatus.completed
                                ? Icons.check_circle
                                : o.status == TaskStatus.skipped
                                ? Icons.skip_next
                                : o.locked
                                ? Icons.lock_outline
                                : o.task.kind == TaskKind.strict
                                ? Icons.schedule
                                : o.task.kind == TaskKind.manual
                                ? Icons.pan_tool_outlined
                                : Icons.auto_awesome_mosaic_outlined,
                            size: 15,
                          ),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              o.task.title,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: o.status == TaskStatus.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (o.task.tagIds.isNotEmpty &&
                              (compact || o.task.duration < 120))
                            Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: TagMarker(o.task.tagIds, c.tags),
                            ),
                          if (warnings.isNotEmpty)
                            Icon(Icons.warning_amber, size: 16),
                        ],
                      ),
                      if (!compact) ...[
                        SizedBox(height: 4),
                        Text(
                          '${o.start == null ? context.strings.text('{0} min · unscheduled', [o.task.duration]) : '${timeLabel(o.start!)}–${timeLabel(o.start! + o.task.duration)}'} · ${suggested ? context.strings.text('Suggested') : kindLabels(context)[o.task.kind.index]}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (o.task.tagIds.isNotEmpty && o.task.duration >= 120)
                          SizedBox(
                            height: 18,
                            child: ClipRect(
                              child: TagChips(o.task.tagIds, c.tags),
                            ),
                          ),
                        if (o.task.subtasks.isNotEmpty)
                          Text(
                            context.strings.text('{0}/{1} subtasks', [
                              o.checked.length,
                              o.task.subtasks.length,
                            ]),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget day(CalendarController c) {
    final plan = c.plans[dayKey(c.date)];
    final items = plan?.items ?? [];
    final assigned = items
        .where((o) => o.start != null && o.status != TaskStatus.skipped)
        .toList();
    final pending = items
        .where((o) => o.start == null || o.status == TaskStatus.skipped)
        .toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: timelineScroll,
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    children: [
                      Text(context.strings.text('◷ Fixed')),
                      Text(context.strings.text('◇ Suggested automatic')),
                      Text(context.strings.text('▣ Manual / locked')),
                    ],
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    height: 1440,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Overlaps remain visible in separate columns so conflicts can be resolved.
                        final lanes = <List<Occurrence>>[];
                        final laneOf = <String, int>{};
                        for (final o in assigned) {
                          var lane = 0;
                          while (lane < lanes.length &&
                              lanes[lane].any(
                                (x) =>
                                    Span(
                                      o.start!,
                                      o.start! + o.task.duration,
                                    ).overlaps(
                                      Span(
                                        x.start!,
                                        x.start! + x.task.duration,
                                      ),
                                    ),
                              )) {
                            lane++;
                          }
                          if (lane == lanes.length) lanes.add([]);
                          lanes[lane].add(o);
                          laneOf[o.id] = lane;
                        }
                        final count = lanes.isEmpty ? 1 : lanes.length;
                        final width = (constraints.maxWidth - 62) / count;
                        final now = DateTime.now();
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var hour = 0; hour < 24; hour++)
                              Positioned(
                                top: hour * 60,
                                left: 0,
                                right: 0,
                                height: 60,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 54,
                                      child: Text(
                                        timeLabel(hour * 60),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          for (var q = 0; q < 4; q++)
                                            Expanded(
                                              child: DragTarget<Occurrence>(
                                                key: ValueKey(
                                                  'slot-${hour * 60 + q * 15}',
                                                ),
                                                onWillAcceptWithDetails: (d) =>
                                                    dayKey(d.data.day) ==
                                                    dayKey(c.date),
                                                onAcceptWithDetails: (d) =>
                                                    c.assign(
                                                      d.data,
                                                      hour * 60 + q * 15,
                                                    ),
                                                builder: (_, candidates, _) =>
                                                    Container(
                                                      decoration: BoxDecoration(
                                                        color:
                                                            candidates.isEmpty
                                                            ? null
                                                            : Theme.of(context)
                                                                  .colorScheme
                                                                  .primaryContainer,
                                                        border: Border(
                                                          top: BorderSide(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .dividerColor
                                                                    .withValues(
                                                                      alpha:
                                                                          q == 0
                                                                          ? .4
                                                                          : .12,
                                                                    ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            for (final o in assigned)
                              Positioned(
                                key: ValueKey('day-block-${o.id}'),
                                top: o.start!.toDouble(),
                                left: 60 + laneOf[o.id]! * width,
                                width: width - 6,
                                height: o.task.duration.toDouble(),
                                child: Tooltip(
                                  message:
                                      '${o.task.title} · ${timeLabel(o.start!)}–${timeLabel(o.start! + o.task.duration)} · ${o.task.duration} min · ${tagNames(context, o.task.tagIds, c.tags)}',
                                  child: Semantics(
                                    label: context.strings
                                        .text('{0}, {1} minutes, {2}', [
                                          o.task.title,
                                          o.task.duration,
                                          timeLabel(o.start!),
                                        ]),
                                    button: true,
                                    child: ClipRect(
                                      child: activity(
                                        c,
                                        o,
                                        compact: o.task.duration < 75,
                                        short: o.task.duration < 34,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (dayKey(now) == dayKey(c.date))
                              Positioned(
                                top: (now.hour * 60 + now.minute).toDouble(),
                                left: 48,
                                right: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    height: 2,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 235,
          child: ListView(
            padding: EdgeInsets.all(16),
            children: [
              Text(
                context.strings.text('Unscheduled / skipped'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: 12),
              if (pending.isEmpty)
                Text(context.strings.text('Everything is scheduled.')),
              for (final o in pending)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: activity(c, o),
                ),
              if (assigned.any((o) => o.task.duration < 34)) ...[
                SizedBox(height: 20),
                Text(
                  context.strings.text('Short blocks'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(height: 8),
                for (final o in assigned.where((o) => o.task.duration < 34))
                  Padding(
                    key: ValueKey('day-short-${o.id}'),
                    padding: EdgeInsets.only(bottom: 8),
                    child: activity(c, o),
                  ),
              ],
              SizedBox(height: 20),
              Text(
                context.strings.text('Available slots'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: 8),
              for (final s in plan?.free ?? <Span>[])
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${timeLabel(s.start)}–${timeLabel(s.end)} · ${s.duration} min',
                  ),
                ),
              if (plan != null && plan.issues.isNotEmpty) ...[
                SizedBox(height: 20),
                Text(
                  context.strings.text('Scheduling issues'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                for (final o in items.where(
                  (o) => plan.issues.containsKey(o.id),
                ))
                  TextButton(
                    onPressed: () => select(c, o),
                    child: Text(
                      '${o.task.title}: ${plan.issues[o.id]!.map(context.strings.error).join(' ')}',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget week(CalendarController c) => WeeklyCalendar(
    days: c.visibleDays,
    plans: c.plans,
    tags: c.tags,
    onOpenDay: (day) => c.navigate(0, day),
    onSelect: (occurrence) => select(c, occurrence),
  );
  Widget month(CalendarController c) => Column(
    children: [
      Row(
        children: [
          for (final label in weekdayLabels(context))
            Expanded(
              child: Center(
                child: Padding(padding: EdgeInsets.all(12), child: Text(label)),
              ),
            ),
        ],
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => GridView.count(
            crossAxisCount: 7,
            childAspectRatio: box.maxWidth / 7 / (box.maxHeight / 6),
            children: [
              for (final d in c.visibleDays)
                InkWell(
                  key: ValueKey('month-day-${dayKey(d)}'),
                  onTap: isCalendarDay(d) ? () => c.navigate(0, d) : null,
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dayKey(d) == dayKey(DateTime.now())
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: .2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: d.month == c.date.month
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                        SizedBox(height: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final o
                                    in (c.plans[dayKey(d)]?.items ??
                                            <Occurrence>[])
                                        .take(3))
                                  Row(
                                    children: [
                                      if (o.task.tagIds.isNotEmpty) ...[
                                        TagMarker(o.task.tagIds, c.tags),
                                        SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          '${o.status == TaskStatus.completed
                                              ? '✓'
                                              : o.status == TaskStatus.skipped
                                              ? '−'
                                              : '•'} ${o.task.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                if ((c.plans[dayKey(d)]?.items.length ?? 0) > 3)
                                  Text(
                                    context.strings.text('+{0} more', [
                                      c.plans[dayKey(d)]!.items.length - 3,
                                    ]),
                                  ),
                              ],
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
      ),
    ],
  );
  Widget taskList(CalendarController c) {
    final list =
        c.tasks
            .where(
              (t) =>
                  !t.archived &&
                  (c.view == 4 ? t.repeat != Repeat.once : true) &&
                  t.title.toLowerCase().contains(search.toLowerCase()) &&
                  (filter == null || t.kind == filter) &&
                  matchesTag(t.tagIds, tagFilter) &&
                  (statusFilter == null ||
                      (c.plans[dayKey(c.today)]?.items ?? []).any(
                        (o) => o.task.id == t.id && o.status == statusFilter,
                      )),
            )
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: context.strings.text('Search activities'),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
              ),
              SizedBox(width: 16),
              DropdownButton<TaskKind?>(
                value: filter,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.strings.text('All types')),
                  ),
                  for (final k in TaskKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Text(kindLabels(context)[k.index]),
                    ),
                ],
                onChanged: (v) => setState(() => filter = v),
              ),
              SizedBox(width: 12),
              DropdownButton<TaskStatus?>(
                value: statusFilter,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.strings.text('All statuses')),
                  ),
                  DropdownMenuItem(
                    value: TaskStatus.pending,
                    child: Text(context.strings.text('Pending today')),
                  ),
                  DropdownMenuItem(
                    value: TaskStatus.completed,
                    child: Text(context.strings.text('Completed today')),
                  ),
                  DropdownMenuItem(
                    value: TaskStatus.skipped,
                    child: Text(context.strings.text('Skipped today')),
                  ),
                ],
                onChanged: (v) => setState(() => statusFilter = v),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Icon(Icons.label_outline, size: 18),
              SizedBox(width: 8),
              DropdownButton<String>(
                key: ValueKey('tag-filter'),
                value: c.tags.any((t) => t.id == tagFilter) || tagFilter == ''
                    ? tagFilter
                    : null,
                hint: Text(context.strings.text('All tags')),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.strings.text('All tags')),
                  ),
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.strings.text('Untagged')),
                  ),
                  for (final tag in c.tags)
                    DropdownMenuItem(
                      value: tag.id,
                      child: Text(
                        '${tagName(context, tag)}${tag.archived ? context.strings.text(' (retired)') : ''}',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => tagFilter = v),
              ),
              if (tagFilter != null)
                IconButton(
                  tooltip: context.strings.text('Clear tag filter'),
                  onPressed: () => setState(() => tagFilter = null),
                  icon: Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    context.strings.text(
                      'No activities yet. Use Create to add your first one.',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(),
                  itemBuilder: (_, i) {
                    final t = list[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(t.color).withValues(alpha: .18),
                        child: Icon(
                          t.kind == TaskKind.strict
                              ? Icons.schedule
                              : Icons.repeat,
                          color: Color(t.color),
                        ),
                      ),
                      title: Text(t.title),
                      subtitle: Text(
                        '${kindLabels(context)[t.kind.index]} · ${t.duration} min · ${repeatLabels(context)[t.repeat.index]}',
                      ),
                      onTap: () => openTaskEditor(context, c, task: t),
                      trailing: IconButton(
                        tooltip: context.strings.text('Remove activity'),
                        icon: Icon(Icons.delete_outline),
                        onPressed: () => remove(c, t),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> remove(CalendarController c, Task task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.strings.text('Remove activity?')),
        content: Text(
          context.strings.text(
            'Remove this activity from today, including today? It will disappear from the calendar and cannot be reactivated. Earlier dates are kept. Saved execution data is preserved in backups, but removed dates cannot be edited.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(context.strings.text('Remove activity')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await c.run(() => c.service.removeActivity(task.id));
    }
  }

  Widget details(CalendarController c, Occurrence o, {VoidCallback? onClose}) {
    final warnings = c.plans[dayKey(o.day)]?.issues[o.id] ?? [];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.strings.text('Details'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: context.strings.text('Close details'),
                onPressed: () {
                  if (onClose != null) {
                    onClose();
                  } else {
                    c.deselect();
                  }
                },
                icon: Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(o.task.title, style: Theme.of(context).textTheme.headlineSmall),
          SizedBox(height: 8),
          Text(dayKey(o.day)),
          Text(kindLabels(context)[o.task.kind.index]),
          if (o.task.autoWindow != null)
            Text(
              context.strings.text('Scheduling window: {0}–{1}', [
                timeLabel(o.task.autoWindow!.start),
                timeLabel(o.task.autoWindow!.end),
              ]),
            ),
          Text(
            context.strings.text('{0} min · Priority {1}', [
              o.task.duration,
              priorityLabels(context)[o.task.priority],
            ]),
          ),
          if (o.start != null)
            Text(
              '${timeLabel(o.start!)}–${timeLabel(o.start! + o.task.duration)}',
            ),
          SizedBox(height: 16),
          if (o.task.description.isNotEmpty) Text(o.task.description),
          if (o.task.tagIds.isNotEmpty) ...[
            SizedBox(height: 8),
            TagChips(o.task.tagIds, c.tags),
          ],
          for (final w in warnings)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.strings.error(w),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.strings.text('Completed')),
            value: o.status == TaskStatus.completed,
            onChanged: c.loading
                ? null
                : (v) => c.update(
                    o.copy(
                      status: v! ? TaskStatus.completed : TaskStatus.pending,
                    ),
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.strings.text('Skip this occurrence')),
            value: o.status == TaskStatus.skipped,
            onChanged: c.loading
                ? null
                : (v) => c.update(
                    o.copy(status: v ? TaskStatus.skipped : TaskStatus.pending),
                  ),
          ),
          if (o.task.subtasks.isNotEmpty) ...[
            Divider(),
            Text(
              context.strings.text('Subtasks · {0}/{1}', [
                o.checked.length,
                o.task.subtasks.length,
              ]),
            ),
            for (var i = 0; i < o.task.subtasks.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(o.task.subtasks[i]),
                value: o.checked.contains(i),
                onChanged: c.loading
                    ? null
                    : (v) {
                        final checked = [...o.checked];
                        v! ? checked.add(i) : checked.remove(i);
                        c.update(o.copy(checked: checked));
                      },
              ),
          ],
          if (o.task.kind != TaskKind.strict) ...[
            Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.strings.text('Lock schedule')),
              subtitle: Text(
                context.strings.text('The scheduler will keep this position.'),
              ),
              value: o.locked,
              onChanged: o.start == null || c.loading
                  ? null
                  : (v) => c.update(
                      o.copy(locked: v, exception: v || o.exception),
                    ),
            ),
            OutlinedButton.icon(
              onPressed: () => assignDialog(c, o),
              icon: Icon(Icons.edit_calendar),
              label: Text(context.strings.text('Assign / move time')),
            ),
            if (o.start != null)
              TextButton(
                onPressed: () => c.update(
                  o.copy(clearAssignment: true, locked: false, exception: true),
                ),
                child: Text(
                  o.task.kind == TaskKind.automatic
                      ? context.strings.text('Unlock and reschedule suggestion')
                      : context.strings.text('Remove time'),
                ),
              ),
          ],
          SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => openTaskEditor(context, c, occurrence: o),
            icon: Icon(Icons.edit_outlined),
            label: Text(context.strings.text('Edit activity')),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: c.loading ? null : () => remove(c, o.task),
            child: Text(context.strings.text('Remove activity')),
          ),
        ],
      ),
    );
  }

  Future<void> assignDialog(CalendarController c, Occurrence o) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (o.start ?? 480) ~/ 60,
        minute: (o.start ?? 480) % 60,
      ),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null) await c.assign(o, time.hour * 60 + time.minute);
  }
}
