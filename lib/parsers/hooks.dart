import 'duration.dart';

/// When a post hook should run.
enum HookOn {
  always,
  success,
  failure;

  static HookOn parse(dynamic raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case null:
      case '':
      case 'always':
        return HookOn.always;
      case 'success':
        return HookOn.success;
      case 'failure':
        return HookOn.failure;
      default:
        throw ArgumentError(
          "hook.on must be always, success, or failure; got '$raw'.",
        );
    }
  }

  bool shouldRun(bool succeeded) => switch (this) {
        HookOn.always => true,
        HookOn.success => succeeded,
        HookOn.failure => !succeeded,
      };
}

/// One custom command executed before or after a run scope.
class HookStep {
  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final Duration? timeout;
  final HookOn on;
  final bool continueOnError;

  const HookStep({
    required this.command,
    this.arguments = const [],
    this.workingDirectory,
    this.environment = const {},
    this.timeout,
    this.on = HookOn.always,
    this.continueOnError = false,
  });

  factory HookStep.parse(dynamic raw, String label) {
    if (raw is String) {
      if (raw.trim().isEmpty) {
        throw ArgumentError('$label command cannot be empty.');
      }
      return HookStep(command: raw.trim());
    }
    if (raw is! Map) {
      throw ArgumentError('$label must be a command string or a mapping.');
    }
    final map = Map<String, dynamic>.from(raw);
    final command = map['command']?.toString().trim() ?? '';
    if (command.isEmpty) throw ArgumentError("$label requires 'command'.");

    final rawArguments = map['arguments'] ?? map['args'];
    if (rawArguments != null && rawArguments is! List) {
      throw ArgumentError('$label.arguments must be a list.');
    }
    final rawEnvironment = map['environment'] ?? map['env'];
    if (rawEnvironment != null && rawEnvironment is! Map) {
      throw ArgumentError('$label.environment must be a mapping.');
    }

    return HookStep(
      command: command,
      arguments: [
        for (final value in (rawArguments as List?) ?? const [])
          value.toString(),
      ],
      workingDirectory: map['working-directory']?.toString(),
      environment: {
        for (final entry in (rawEnvironment as Map? ?? const {}).entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      },
      timeout: map['timeout'] == null
          ? null
          : parseDuration(
              map['timeout'],
              label: '$label.timeout',
              allowZero: false,
            ),
      on: HookOn.parse(map['on']),
      continueOnError: _bool(
        map['continue-on-error'],
        '$label.continue-on-error',
      ),
    );
  }

  static bool _bool(dynamic raw, String label) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw.toString().toLowerCase() == 'true') return true;
    if (raw.toString().toLowerCase() == 'false') return false;
    throw ArgumentError("$label must be true or false, got '$raw'.");
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        if (arguments.isNotEmpty) 'arguments': arguments,
        if (workingDirectory != null) 'working-directory': workingDirectory,
        if (environment.isNotEmpty) 'environment': environment,
        if (timeout != null) 'timeout': formatDurationValue(timeout!),
        'on': on.name,
        if (continueOnError) 'continue-on-error': true,
      };
}

/// Hooks attached to one run, task, or job scope.
class HookSet {
  final List<HookStep> pre;
  final List<HookStep> post;

  const HookSet({this.pre = const [], this.post = const []});

  bool get isEmpty => pre.isEmpty && post.isEmpty;

  static HookSet parse(Map<String, dynamic> map, String label) => HookSet(
        pre: _steps(map['pre'], '$label.pre'),
        post: _steps(map['post'], '$label.post'),
      );

  static List<HookStep> _steps(dynamic raw, String label) {
    if (raw == null) return const [];
    final values = raw is List ? raw : [raw];
    return [
      for (var index = 0; index < values.length; index++)
        HookStep.parse(values[index], '$label[$index]'),
    ];
  }
}
