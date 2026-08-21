/// Parses human-friendly durations used by run control settings.
///
/// Supported suffixes are `ms`, `s`, `m`, and `h`. A bare number is treated
/// as seconds for backwards compatibility with existing numeric timeouts.
Duration parseDuration(
  dynamic raw, {
  required String label,
  bool allowZero = true,
}) {
  if (raw is Duration) {
    if (raw.isNegative || (!allowZero && raw == Duration.zero)) {
      throw ArgumentError(
        '$label must be ${allowZero ? 'zero or greater' : 'greater than zero'}.',
      );
    }
    return raw;
  }

  final text = raw?.toString().trim().toLowerCase() ?? '';
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(ms|s|m|h)?$').firstMatch(text);
  if (match == null) {
    throw ArgumentError(
      "$label must be a duration such as 500ms, 15s, 2m, or 1h; got '$raw'.",
    );
  }

  final value = double.parse(match.group(1)!);
  if (!value.isFinite || value < 0 || (!allowZero && value == 0)) {
    throw ArgumentError(
      '$label must be ${allowZero ? 'zero or greater' : 'greater than zero'}.',
    );
  }

  final milliseconds = switch (match.group(2)) {
    'ms' => value,
    'm' => value * Duration.millisecondsPerMinute,
    'h' => value * Duration.millisecondsPerHour,
    _ => value * Duration.millisecondsPerSecond,
  };
  return Duration(milliseconds: milliseconds.round());
}

/// Short stable representation used in JSON and log output.
String formatDurationValue(Duration duration) {
  if (duration.inMilliseconds % Duration.millisecondsPerHour == 0) {
    return '${duration.inHours}h';
  }
  if (duration.inMilliseconds % Duration.millisecondsPerMinute == 0) {
    return '${duration.inMinutes}m';
  }
  if (duration.inMilliseconds % Duration.millisecondsPerSecond == 0) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMilliseconds}ms';
}
