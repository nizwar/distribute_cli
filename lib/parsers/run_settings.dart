import 'duration.dart';

/// Controls how tasks are admitted to the worker pool.
class ParallelSettings {
  /// Maximum number of tasks in flight. A very large value means `auto`.
  final int tasks;

  /// Minimum time between two task starts across the whole run.
  final Duration gap;

  const ParallelSettings({this.tasks = 1, this.gap = Duration.zero});

  bool get isAuto => tasks >= autoTaskCount;

  static const int autoTaskCount = 1 << 20;

  static ParallelSettings parse(dynamic raw, String path) {
    if (raw == null) return const ParallelSettings();
    if (raw is bool) {
      return ParallelSettings(tasks: raw ? autoTaskCount : 1);
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final rawTasks = map['tasks'] ?? 1;
      final tasks = _parseTasks(rawTasks, path);
      final gap = map['gap'] == null
          ? Duration.zero
          : parseDuration(map['gap'], label: 'parallel.gap');
      return ParallelSettings(tasks: tasks, gap: gap);
    }
    return ParallelSettings(tasks: _parseTasks(raw, path));
  }

  static int _parseTasks(dynamic raw, String path) {
    if (raw is String && raw.trim().toLowerCase() == 'auto') {
      return autoTaskCount;
    }
    final count = raw is int ? raw : int.tryParse(raw.toString().trim());
    if (count == null || count < 1) {
      throw ArgumentError(
        "'parallel' in '$path' must be true, false, auto, a count of 1 or "
        "more, or a {tasks, gap} mapping; got '$raw'.",
      );
    }
    return count;
  }
}

/// Global reaction to a fatal task failure.
enum ErrorPolicy {
  /// Other independent tasks may still run.
  continueRun,

  /// Do not start new tasks after the first fatal failure.
  stop;

  static ErrorPolicy parse(dynamic raw, {String label = 'on-error'}) {
    switch (raw?.toString().trim().toLowerCase()) {
      case null:
      case '':
      case 'continue':
        return ErrorPolicy.continueRun;
      case 'stop':
      case 'fail-fast':
        return ErrorPolicy.stop;
      default:
        throw ArgumentError(
          "$label must be 'continue' or 'stop', got '$raw'.",
        );
    }
  }
}
