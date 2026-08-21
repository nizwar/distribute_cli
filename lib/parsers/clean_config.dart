/// Automatic cleanup performed after all jobs and run post-hooks finish.
class CleanConfig {
  final CleanOn on;
  final bool flutter;
  final bool outputs;

  const CleanConfig({
    this.on = CleanOn.success,
    this.flutter = true,
    this.outputs = true,
  });

  factory CleanConfig.parse(dynamic raw) {
    if (raw is bool) {
      if (!raw) {
        return const CleanConfig(on: CleanOn.never);
      }
      return const CleanConfig();
    }
    if (raw is! Map) {
      throw ArgumentError("'clean' must be true, false, or a mapping.");
    }
    final map = Map<String, dynamic>.from(raw);
    return CleanConfig(
      on: CleanOn.parse(map['on']),
      flutter: _bool(map['flutter'], 'clean.flutter', defaultValue: true),
      outputs: _bool(map['outputs'], 'clean.outputs', defaultValue: true),
    );
  }

  bool shouldRun(bool succeeded) => switch (on) {
        CleanOn.never => false,
        CleanOn.always => true,
        CleanOn.success => succeeded,
        CleanOn.failure => !succeeded,
      };

  static bool _bool(dynamic raw, String label, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    if (raw.toString().toLowerCase() == 'true') return true;
    if (raw.toString().toLowerCase() == 'false') return false;
    throw ArgumentError("$label must be true or false, got '$raw'.");
  }
}

enum CleanOn {
  never,
  success,
  failure,
  always;

  static CleanOn parse(dynamic raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case null:
      case '':
      case 'success':
        return CleanOn.success;
      case 'failure':
        return CleanOn.failure;
      case 'always':
        return CleanOn.always;
      case 'never':
        return CleanOn.never;
      default:
        throw ArgumentError(
          "clean.on must be never, success, failure, or always; got '$raw'.",
        );
    }
  }
}
