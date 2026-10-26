import 'dart:convert';

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
final firstCalendarDay = DateTime(2000);
final lastCalendarDay = DateTime(2100, 12, 31);
bool isCalendarDay(DateTime d) => d.year >= 2000 && d.year <= 2100;
DateTime clampCalendarDay(DateTime d) {
  final day = dateOnly(d);
  if (day.isBefore(firstCalendarDay)) return firstCalendarDay;
  if (day.isAfter(lastCalendarDay)) return lastCalendarDay;
  return day;
}

DateTime parseDay(String value) {
  final date = DateTime.parse(value);
  if (dayKey(date) != value || !isCalendarDay(date)) {
    throw const FormatException('Invalid date.');
  }
  return dateOnly(date);
}

String timeLabel(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

enum TaskKind { strict, automatic, manual }

enum Repeat { once, daily, weekdays, weekly, selected }

enum TaskStatus { pending, completed, skipped }

class Task {
  final String id, title, description;
  final TaskKind kind;
  final int duration, start, priority, color;
  final DateTime date;
  final DateTime? endDate, removedFrom;
  final Span? autoWindow;
  final Repeat repeat;
  final List<int> weekdays;
  final List<String> subtasks;
  final List<String> tagIds;
  final bool archived;
  const Task({
    required this.id,
    required this.title,
    required this.date,
    this.endDate,
    this.removedFrom,
    this.autoWindow,
    this.description = '',
    this.kind = TaskKind.automatic,
    this.duration = 60,
    this.start = 540,
    this.priority = 1,
    this.color = 0xff5269cc,
    this.repeat = Repeat.once,
    this.weekdays = const [],
    this.subtasks = const [],
    this.tagIds = const [],
    this.archived = false,
  });
  bool occurs(DateTime d) {
    if (archived ||
        dateOnly(d).isBefore(dateOnly(date)) ||
        (endDate != null && dateOnly(d).isAfter(endDate!)) ||
        (removedFrom != null && !dateOnly(d).isBefore(removedFrom!))) {
      return false;
    }
    return switch (repeat) {
      Repeat.once => dayKey(d) == dayKey(date),
      Repeat.daily => true,
      Repeat.weekdays => d.weekday <= 5,
      Repeat.weekly => d.weekday == date.weekday,
      Repeat.selected => weekdays.contains(d.weekday),
    };
  }

  void validate() {
    if (id.isEmpty ||
        title.trim().isEmpty ||
        title.length > 200 ||
        duration <= 0 ||
        duration > 1440 ||
        start < 0 ||
        start > 1439 ||
        (kind == TaskKind.strict && start + duration > 1440) ||
        (autoWindow != null &&
            (kind != TaskKind.automatic ||
                autoWindow!.start < 0 ||
                autoWindow!.end > 1440 ||
                autoWindow!.end <= autoWindow!.start)) ||
        priority < 0 ||
        priority > 2 ||
        color < 0 ||
        color > 0xffffffff ||
        date.year < 2000 ||
        date.year > 2100 ||
        (endDate != null &&
            (!isCalendarDay(endDate!) ||
                endDate != dateOnly(endDate!) ||
                endDate!.isBefore(dateOnly(date)))) ||
        (removedFrom != null &&
            (!archived ||
                !isCalendarDay(removedFrom!) ||
                removedFrom != dateOnly(removedFrom!))) ||
        weekdays.toSet().length != weekdays.length ||
        weekdays.any((d) => d < 1 || d > 7) ||
        (repeat == Repeat.selected && weekdays.isEmpty) ||
        tagIds.toSet().length != tagIds.length ||
        tagIds.any((id) => !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) ||
        subtasks.length > 100 ||
        subtasks.any((s) => s.trim().isEmpty)) {
      throw const FormatException('The task contains invalid values.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'kind': kind.name,
    'duration': duration,
    'start': start,
    if (autoWindow != null) 'autoWindow': [autoWindow!.start, autoWindow!.end],
    'priority': priority,
    'color': color,
    'date': dayKey(date),
    if (endDate != null) 'endDate': dayKey(endDate!),
    if (removedFrom != null) 'removedFrom': dayKey(removedFrom!),
    'repeat': repeat.name,
    'weekdays': weekdays,
    'subtasks': subtasks,
    'tagIds': tagIds,
    'archived': archived,
  };
  factory Task.fromJson(Map<String, dynamic> j) {
    final t = Task(
      id: j['id'] as String,
      title: j['title'] as String,
      description: j['description'] as String,
      kind: TaskKind.values.byName(j['kind']),
      duration: j['duration'] as int,
      start: j['start'] as int,
      autoWindow: j['autoWindow'] == null
          ? null
          : _windowFromJson(j['autoWindow']),
      priority: j['priority'] as int,
      color: j['color'] as int,
      date: parseDay(j['date']),
      endDate: j['endDate'] == null ? null : parseDay(j['endDate']),
      removedFrom: j['removedFrom'] == null ? null : parseDay(j['removedFrom']),
      repeat: Repeat.values.byName(j['repeat']),
      weekdays: List<int>.from(j['weekdays']),
      subtasks: List<String>.from(j['subtasks']),
      tagIds: j.containsKey('tagIds')
          ? List<String>.from(j['tagIds'])
          : const [],
      archived: j['archived'] as bool,
    );
    t.validate();
    return t;
  }
  Task copy({bool? archived}) =>
      Task.fromJson({...toJson(), 'archived': archived ?? this.archived});

  static Span _windowFromJson(dynamic value) {
    if (value is! List ||
        value.length != 2 ||
        value[0] is! int ||
        value[1] is! int) {
      throw const FormatException('Invalid activity time window.');
    }
    return Span(value[0], value[1]);
  }
}

class Occurrence {
  final Task task;
  final DateTime day;
  final TaskStatus status;
  final List<int> checked;
  final int? assigned;
  final bool locked, exception;
  const Occurrence({
    required this.task,
    required this.day,
    this.status = TaskStatus.pending,
    this.checked = const [],
    this.assigned,
    this.locked = false,
    this.exception = false,
  });
  String get id => '${task.id}/${dayKey(day)}';
  int? get start => task.kind == TaskKind.strict ? task.start : assigned;
  bool get reserved =>
      task.kind == TaskKind.strict ||
      locked ||
      task.kind == TaskKind.manual ||
      status != TaskStatus.pending;
  bool hasStarted(DateTime now) {
    final minute = start;
    if (minute == null) return false;
    final date = dateOnly(day);
    final today = dateOnly(now);
    return date.isBefore(today) ||
        (date == today && minute <= now.hour * 60 + now.minute);
  }

  bool isProtectedAt(DateTime now) => reserved || hasStarted(now);
  List<int> checkedForSubtasks(List<String> next) {
    // Equal text is matched by occurrence order, including unchecked duplicates.
    final previous = <String, List<int>>{};
    for (var i = 0; i < task.subtasks.length; i++) {
      previous.putIfAbsent(task.subtasks[i], () => []).add(i);
    }
    final result = <int>[];
    for (var i = 0; i < next.length; i++) {
      final candidates = previous[next[i]];
      if (candidates != null &&
          candidates.isNotEmpty &&
          checked.contains(candidates.removeAt(0))) {
        result.add(i);
      }
    }
    return result;
  }

  Occurrence copy({
    Task? task,
    TaskStatus? status,
    List<int>? checked,
    int? assigned,
    bool clearAssignment = false,
    bool? locked,
    bool? exception,
  }) => Occurrence(
    task: task ?? this.task,
    day: day,
    status: status ?? this.status,
    checked: checked ?? this.checked,
    assigned: clearAssignment ? null : assigned ?? this.assigned,
    locked: locked ?? this.locked,
    exception: exception ?? this.exception,
  );
  Map<String, dynamic> toJson() => {
    'task': task.toJson(),
    'day': dayKey(day),
    'status': status.name,
    'checked': checked,
    'assigned': assigned,
    'locked': locked,
    'exception': exception,
  };
  factory Occurrence.fromJson(Map<String, dynamic> j) {
    final o = Occurrence(
      task: Task.fromJson(Map<String, dynamic>.from(j['task'])),
      day: parseDay(j['day']),
      status: TaskStatus.values.byName(j['status']),
      checked: List<int>.from(j['checked']),
      assigned: j['assigned'] as int?,
      locked: j['locked'] as bool,
      exception: j['exception'] as bool,
    );
    if (o.checked.toSet().length != o.checked.length ||
        o.checked.any((i) => i < 0 || i >= o.task.subtasks.length) ||
        (o.assigned != null &&
            (o.assigned! < 0 || o.assigned! + o.task.duration > 1440))) {
      throw const FormatException('Invalid occurrence.');
    }
    return o;
  }
}

class Span {
  final int start, end;
  const Span(this.start, this.end);
  int get duration => end - start;
  bool overlaps(Span b) => start < b.end && b.start < end;
  bool contains(Span b) => b.start >= start && b.end <= end;
}

class Preferences {
  final Map<int, Span> availability;
  final String theme;
  final String language;
  Preferences({
    Map<int, Span>? availability,
    this.theme = 'system',
    this.language = 'en',
  }) : availability =
           availability ??
           {for (var i = 1; i <= 7; i++) i: const Span(480, 1320)};
  Map<String, dynamic> toJson() => {
    'theme': theme,
    'language': language,
    'availability': {
      for (final e in availability.entries)
        '${e.key}': [e.value.start, e.value.end],
    },
  };
  factory Preferences.fromJson(Map<String, dynamic> j) {
    final map = (j['availability'] as Map).map(
      (k, v) => MapEntry(int.parse(k), Span(v[0] as int, v[1] as int)),
    );
    if (map.length != 7 ||
        !List.generate(7, (i) => i + 1).every(map.containsKey) ||
        map.values.any((s) => s.start < 0 || s.end > 1440 || s.end < s.start) ||
        !['system', 'light', 'dark'].contains(j['theme']) ||
        !['en', 'es'].contains(j['language'] ?? 'en')) {
      throw const FormatException('Invalid availability.');
    }
    return Preferences(
      availability: map,
      theme: j['theme'],
      language: j['language'] as String? ?? 'en',
    );
  }
}

String encode(Object value) => jsonEncode(value);
