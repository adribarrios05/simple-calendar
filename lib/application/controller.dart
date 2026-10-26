import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/model.dart';
import '../domain/tag.dart';
import '../domain/planner.dart';
import '../data/storage_errors.dart';
import 'calendar_service.dart';

final serviceProvider = Provider<CalendarService>(
  (ref) => throw UnimplementedError(),
);
final calendarProvider = ChangeNotifierProvider<CalendarController>(
  (ref) => CalendarController(ref.watch(serviceProvider)),
);

class CalendarController extends ChangeNotifier {
  final CalendarService service;
  DateTime date;
  int view = 0;
  Preferences preferences = Preferences();
  List<Task> tasks = [];
  List<Tag> tags = [];
  Map<String, Plan> plans = {};
  bool loading = true;
  String? error;
  Occurrence? selected;
  Timer? _timer;
  Future<void> _queue = Future.value();
  CalendarController(this.service)
    : date = clampCalendarDay(service.planner.clock.now()) {
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }
  DateTime get weekStart =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);
  DateTime get today => clampCalendarDay(service.planner.clock.now());
  List<DateTime> get visibleDays {
    if (view == 3 || view == 4) return [today];
    if (view == 1) {
      return List.generate(
        7,
        (i) => DateTime(weekStart.year, weekStart.month, weekStart.day + i),
      );
    }
    if (view == 2) {
      final first = DateTime(date.year, date.month, 1);
      return List.generate(
        42,
        (i) => DateTime(first.year, first.month, 2 - first.weekday + i),
      );
    }
    return [date];
  }

  Future<void> run(Future<void> Function() action) {
    final done = _queue.then((_) async {
      loading = true;
      error = null;
      notifyListeners();
      try {
        await action();
        await _load();
      } catch (e) {
        error = storageErrorMessage(e) ?? e.toString();
      }
      loading = false;
      notifyListeners();
    });
    _queue = done.catchError((Object _) {});
    return done;
  }

  Future<void> _load() async {
    preferences = await service.repository.preferences();
    tasks = await service.repository.tasks();
    tags = await service.repository.tags();
    final next = <String, Plan>{};
    for (final d in visibleDays.where(isCalendarDay)) {
      next[dayKey(d)] = await service.day(d);
    }
    plans = next;
    if (selected != null) {
      final items = plans[dayKey(selected!.day)]?.items ?? [];
      selected = items.where((o) => o.id == selected!.id).firstOrNull;
    }
  }

  Future<void> refresh() => run(() async {});
  void navigate(int v, [DateTime? d]) {
    view = v;
    if (d != null) date = clampCalendarDay(d);
    selected = null;
    refresh();
  }

  DateTime _shiftedDate(int delta) => clampCalendarDay(
    view == 2
        ? DateTime(date.year, date.month + delta, 1)
        : DateTime(
            date.year,
            date.month,
            date.day + delta * (view == 1 ? 7 : 1),
          ),
  );
  bool canShift(int delta) {
    final next = _shiftedDate(delta);
    if (view == 2) return next.year != date.year || next.month != date.month;
    if (view == 1) {
      return DateTime(next.year, next.month, next.day - next.weekday + 1) !=
          weekStart;
    }
    return next != date;
  }

  void shift(int delta) {
    if (!canShift(delta)) return;
    date = _shiftedDate(delta);
    selected = null;
    refresh();
  }

  void select(Occurrence o) {
    selected = o;
    notifyListeners();
  }

  void deselect() {
    selected = null;
    notifyListeners();
  }

  Future<void> update(Occurrence o) => run(() => service.update(o));
  Future<void> assign(Occurrence o, int start) =>
      run(() => service.assign(o, start));
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
