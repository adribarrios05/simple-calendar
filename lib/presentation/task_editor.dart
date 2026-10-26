import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../application/controller.dart';
import '../domain/model.dart';
import 'tags.dart';

List<String> kindLabels(BuildContext context) => [
  context.strings.text('Fixed'),
  context.strings.text('Automatic flexible'),
  context.strings.text('Manual flexible'),
];
List<String> repeatLabels(BuildContext context) => [
  context.strings.text('Once'),
  context.strings.text('Daily'),
  context.strings.text('Weekdays'),
  context.strings.text('Weekly'),
  context.strings.text('Selected weekdays'),
];
List<String> weekdayLabels(BuildContext context) => [
  context.strings.text('Mon'),
  context.strings.text('Tue'),
  context.strings.text('Wed'),
  context.strings.text('Thu'),
  context.strings.text('Fri'),
  context.strings.text('Sat'),
  context.strings.text('Sun'),
];
List<String> priorityLabels(BuildContext context) => [
  context.strings.text('Low'),
  context.strings.text('Normal'),
  context.strings.text('High'),
];

Future<void> openTaskEditor(
  BuildContext context,
  CalendarController controller, {
  Task? task,
  Occurrence? occurrence,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TaskEditor(
      controller: controller,
      original: task ?? occurrence?.task,
      occurrence: occurrence,
    ),
  );
}

class TaskEditor extends StatefulWidget {
  final CalendarController controller;
  final Task? original;
  final Occurrence? occurrence;
  const TaskEditor({
    super.key,
    required this.controller,
    this.original,
    this.occurrence,
  });
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  var _form = GlobalKey<FormState>();
  late final TextEditingController title, description, duration, sub;
  late final TextEditingController startTime, finishTime;
  late final TextEditingController windowStart, windowEnd;
  bool limitSchedulingHours = false;
  late TaskKind kind;
  late Repeat repeat;
  late DateTime date;
  DateTime? endDate, removedFrom;
  bool thisWeekOnly = false;
  late int start, priority, color;
  late Set<int> weekdays;
  late List<String> tagIds;
  bool single = false, saving = false, archived = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final t = widget.original;
    title = TextEditingController(text: t?.title ?? '');
    description = TextEditingController(text: t?.description ?? '');
    duration = TextEditingController(text: '${t?.duration ?? 60}');
    sub = TextEditingController(text: t?.subtasks.join('\n') ?? '');
    kind = t?.kind ?? TaskKind.strict;
    repeat = t?.repeat ?? Repeat.weekly;
    date = t?.date ?? widget.controller.date;
    start = t?.start ?? 540;
    startTime = TextEditingController(text: timeLabel(start));
    finishTime = TextEditingController(
      text: timeLabel(start + (t?.duration ?? 60)),
    );
    priority = t?.priority ?? 1;
    limitSchedulingHours = t?.autoWindow != null;
    windowStart = TextEditingController(
      text: timeLabel(t?.autoWindow?.start ?? 540),
    );
    windowEnd = TextEditingController(
      text: timeLabel(t?.autoWindow?.end ?? 840),
    );
    color = t?.color ?? 0xff5269cc;
    weekdays = (t?.weekdays ?? [date.weekday]).toSet();
    archived = t?.archived ?? false;
    endDate = t?.endDate;
    removedFrom = t?.removedFrom;
    thisWeekOnly = endDate != null;
    tagIds = [...?t?.tagIds];
    single = widget.occurrence != null;
  }

  void changeScope(bool onlyOccurrence) {
    if (onlyOccurrence == single) return;
    final task = onlyOccurrence
        ? widget.occurrence?.task
        : widget.controller.tasks
              .where((t) => t.id == widget.original?.id)
              .firstOrNull;
    if (task == null) {
      setState(
        () => error = context.strings.text(
          'The definition is no longer available. Close and reopen the editor.',
        ),
      );
      return;
    }
    setState(() {
      single = onlyOccurrence;
      title.text = task.title;
      description.text = task.description;
      duration.text = '${task.duration}';
      sub.text = task.subtasks.join('\n');
      kind = task.kind;
      repeat = task.repeat;
      date = task.date;
      start = task.start;
      startTime.text = timeLabel(task.start);
      finishTime.text = timeLabel(task.start + task.duration);
      priority = task.priority;
      limitSchedulingHours = task.autoWindow != null;
      windowStart.text = timeLabel(task.autoWindow?.start ?? 540);
      windowEnd.text = timeLabel(task.autoWindow?.end ?? 840);
      color = task.color;
      weekdays = task.weekdays.toSet();
      archived = task.archived;
      endDate = task.endDate;
      removedFrom = task.removedFrom;
      thisWeekOnly = endDate != null;
      tagIds = [...task.tagIds];
      error = null;
      // Recreate FormField state so dropdowns display the loaded values too.
      _form = GlobalKey<FormState>();
    });
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    duration.dispose();
    sub.dispose();
    startTime.dispose();
    finishTime.dispose();
    windowStart.dispose();
    windowEnd.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!_form.currentState!.validate()) return;
    if (kind == TaskKind.strict) {
      start = parseTime(startTime.text)!;
      duration.text = '${parseTime(finishTime.text, end: true)! - start}';
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final t = Task(
        id: widget.original?.id ?? Uuid().v4(),
        title: title.text.trim(),
        description: description.text.trim(),
        kind: kind,
        autoWindow: kind == TaskKind.automatic && limitSchedulingHours
            ? Span(
                parseTime(windowStart.text)!,
                parseTime(windowEnd.text, end: true)!,
              )
            : null,
        duration: int.parse(duration.text),
        start: start,
        priority: priority,
        color: color,
        date: date,
        endDate: endDate,
        removedFrom: removedFrom,
        repeat: repeat,
        weekdays: weekdays.toList()..sort(),
        subtasks: sub.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        archived: archived,
        tagIds: tagIds,
      );
      t.validate();
      final conflicts = await widget.controller.service.conflicts(
        t,
        onlyDay: single ? widget.occurrence?.day : null,
      );
      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(context.strings.text('Scheduling conflicts')),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Text(
                  context.strings.text(
                    'You can go back and change the time. Keeping this time will show warnings without moving protected blocks.\n\n{0}',
                    [conflicts.join('\n')],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(context.strings.text('Change time')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(context.strings.text('Keep with warning')),
              ),
            ],
          ),
        );
        if (proceed != true) {
          setState(() => saving = false);
          return;
        }
      }
      if (single && widget.occurrence != null) {
        final o = widget.occurrence!;
        await widget.controller.run(
          () => widget.controller.service.update(
            o.copy(
              task: t,
              checked: o.checkedForSubtasks(t.subtasks),
              clearAssignment:
                  kind != o.task.kind || t.duration != o.task.duration,
              locked: kind == o.task.kind && t.duration == o.task.duration
                  ? o.locked
                  : false,
              exception: true,
            ),
          ),
        );
      } else {
        await widget.controller.run(() => widget.controller.service.save(t));
      }
      if (widget.controller.error != null) {
        throw StateError(widget.controller.error!);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          saving = false;
        });
      }
    }
  }

  int? parseTime(String value, {bool end = false}) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (end && hour == 24 && minute == 0) return 1440;
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  void changeKind(TaskKind next) {
    setState(() {
      if (kind == TaskKind.strict && next != TaskKind.strict) {
        final from = parseTime(startTime.text);
        final to = parseTime(finishTime.text, end: true);
        if (from != null && to != null && to > from) {
          start = from;
          duration.text = '${to - from}';
        }
      } else if (kind != TaskKind.strict && next == TaskKind.strict) {
        startTime.text = timeLabel(start);
        final length = int.tryParse(duration.text) ?? 60;
        finishTime.text = timeLabel((start + length).clamp(start + 1, 1440));
      }
      kind = next;
      error = null;
    });
  }

  Widget clockField({required bool end, bool automaticWindow = false}) {
    final controller = automaticWindow
        ? (end ? windowEnd : windowStart)
        : (end ? finishTime : startTime);
    final label = automaticWindow
        ? (end ? 'Finish by' : 'Not before')
        : (end ? 'End time' : 'Start time');
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      enabled: !saving,
      decoration: InputDecoration(
        labelText: context.strings.text(label),
        hintText: 'HH:mm',
        helperText: end
            ? context.strings.text('Use 24:00 for the end of the day.')
            : null,
        helperMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: context.strings.text(
            end ? 'Choose end time' : 'Choose start time',
          ),
          icon: const Icon(Icons.schedule),
          onPressed: saving
              ? null
              : () async {
                  final minute =
                      parseTime(controller.text, end: end) ??
                      (end ? (start + 60).clamp(0, 1440) : start);
                  final time = await showTimePicker(
                    context: context,
                    helpText: context.strings.text(
                      end ? 'End time' : 'Start time',
                    ),
                    initialTime: TimeOfDay(
                      hour: (minute % 1440) ~/ 60,
                      minute: minute % 60,
                    ),
                    builder: (c, child) => MediaQuery(
                      data: MediaQuery.of(
                        c,
                      ).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                  );
                  if (time != null && mounted) {
                    final selected = time.hour * 60 + time.minute;
                    setState(
                      () => controller.text = timeLabel(
                        end && selected == 0 ? 1440 : selected,
                      ),
                    );
                  }
                },
        ),
      ),
      validator: (value) {
        final minute = parseTime(value ?? '', end: end);
        if (minute == null) {
          return context.strings.text('Enter a valid time in HH:mm format.');
        }
        final from = parseTime(
          automaticWindow ? windowStart.text : startTime.text,
        );
        if (end && from != null && minute <= from) {
          return context.strings.text(
            'The end time must be later than the start time.',
          );
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.original == null
          ? context.strings.text('New activity')
          : context.strings.text('Edit activity'),
    ),
    content: SizedBox(
      width: 530,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.occurrence != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<bool>(
                    initialValue: single,
                    decoration: InputDecoration(
                      labelText: context.strings.text('Apply changes to'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: true,
                        child: Text(
                          context.strings.text('Only this occurrence'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text(
                          context.strings.text('The definition, from today'),
                        ),
                      ),
                    ],
                    onChanged: saving ? null : (v) => changeScope(v!),
                  ),
                ),
              if (widget.occurrence != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    context.strings.text(
                      'Changing scope loads its saved data and discards unsaved changes. The definition uses its current values.',
                    ),
                  ),
                ),
              TextFormField(
                controller: title,
                autofocus: true,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: context.strings.text('Name'),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.strings.text('Enter a name.')
                    : null,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<TaskKind>(
                initialValue: kind,
                decoration: InputDecoration(
                  labelText: context.strings.text('Scheduling'),
                ),
                items: [
                  for (final k in TaskKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Text(kindLabels(context)[k.index]),
                    ),
                ],
                onChanged: saving ? null : (v) => changeKind(v!),
              ),
              SizedBox(height: 16),
              if (kind == TaskKind.strict)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: clockField(end: false)),
                    SizedBox(width: 12),
                    Expanded(child: clockField(end: true)),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: duration,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.strings.text('Duration (minutes)'),
                        ),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 1440
                              ? context.strings.text('Between 1 and 1440.')
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 16),
              if (kind == TaskKind.automatic) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.strings.text('Limit scheduling hours')),
                  value: limitSchedulingHours,
                  onChanged: saving
                      ? null
                      : (v) => setState(() => limitSchedulingHours = v),
                ),
                if (limitSchedulingHours) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: clockField(end: false, automaticWindow: true),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: clockField(end: true, automaticWindow: true),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      context.strings.text(
                        'The full duration must fit within this window and daily availability.',
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 16),
              ],
              if (!single) ...[
                OutlinedButton.icon(
                  icon: Icon(Icons.calendar_today),
                  label: Text(
                    context.strings.text('Start date: {0}', [dayKey(date)]),
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: firstCalendarDay,
                      lastDate: lastCalendarDay,
                    );
                    if (d != null) {
                      setState(() {
                        date = d;
                        if (thisWeekOnly) {
                          endDate = clampCalendarDay(
                            DateTime(d.year, d.month, d.day + 7 - d.weekday),
                          );
                        }
                      });
                    }
                  },
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<Repeat>(
                  initialValue: repeat,
                  decoration: InputDecoration(
                    labelText: context.strings.text('Repeat'),
                  ),
                  items: [
                    for (final r in Repeat.values)
                      DropdownMenuItem(
                        value: r,
                        child: Text(repeatLabels(context)[r.index]),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (v) => setState(() {
                          repeat = v!;
                          if (repeat == Repeat.once) {
                            thisWeekOnly = false;
                            endDate = null;
                          }
                        }),
                ),
                if (repeat != Repeat.once) ...[
                  SizedBox(height: 16),
                  DropdownButtonFormField<bool>(
                    initialValue: thisWeekOnly,
                    decoration: InputDecoration(
                      labelText: context.strings.text('Schedule scope'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: false,
                        child: Text(context.strings.text('Every week')),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text(context.strings.text('This week only')),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => setState(() {
                            thisWeekOnly = v!;
                            endDate = thisWeekOnly
                                ? clampCalendarDay(
                                    DateTime(
                                      date.year,
                                      date.month,
                                      date.day + 7 - date.weekday,
                                    ),
                                  )
                                : null;
                          }),
                  ),
                  if (endDate != null)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        context.strings.text(
                          'Ends on {0}, in the week of the start date.',
                          [dayKey(endDate!)],
                        ),
                      ),
                    ),
                ],
                if (repeat == Repeat.selected)
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 1; i <= 7; i++)
                        FilterChip(
                          label: Text(weekdayLabels(context)[i - 1]),
                          selected: weekdays.contains(i),
                          onSelected: (v) => setState(() {
                            v ? weekdays.add(i) : weekdays.remove(i);
                          }),
                        ),
                    ],
                  ),
                SizedBox(height: 16),
              ],
              DropdownButtonFormField<int>(
                initialValue: priority,
                decoration: InputDecoration(
                  labelText: context.strings.text('Priority'),
                ),
                items: [
                  for (var i = 0; i < 3; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(priorityLabels(context)[i]),
                    ),
                ],
                onChanged: (v) => setState(() => priority = v!),
              ),
              SizedBox(height: 16),
              TagSelector(
                controller: widget.controller,
                selected: tagIds,
                onChanged: (ids) => setState(() => tagIds = ids),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: description,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.strings.text('Description (optional)'),
                ),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: sub,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.strings.text('Subtasks (one per line)'),
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in [
                    0xff5269cc,
                    0xff187d70,
                    0xffac5b22,
                    0xff9b4285,
                    0xff52606b,
                  ])
                    IconButton(
                      tooltip: context.strings.text('Color'),
                      style: IconButton.styleFrom(
                        backgroundColor: Color(c),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => setState(() => color = c),
                      icon: Icon(
                        color == c ? Icons.check : Icons.circle_outlined,
                      ),
                    ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    context.strings.error(error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(context.strings.text('Cancel')),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(
          saving
              ? context.strings.text('Saving…')
              : context.strings.text('Save'),
        ),
      ),
    ],
  );
}
