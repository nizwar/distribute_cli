import 'ai_config.dart';

/// The command the assistant decided to run.
///
/// The model never emits a raw shell string — it fills in this constrained
/// shape, which the CLI then renders and (with permission) executes. Keeping
/// the surface this narrow is what makes `auto` mode defensible: the assistant
/// can only reach commands that already exist, with arguments the parser
/// validates.
class AiAction {
  /// Which sub-command to run: `run`, `validate`, or `doctor`.
  final String command;

  /// Operation key for `run` — `android` or `android.build`. Null runs all.
  final String? operation;

  /// Whether to pass `--dry-run`.
  final bool dryRun;

  /// One sentence explaining the choice, shown to the user before executing.
  final String reason;

  /// Creates an action.
  const AiAction({
    required this.command,
    required this.reason,
    this.operation,
    this.dryRun = false,
  });

  /// Builds an action from the model's tool arguments.
  ///
  /// Throws [FormatException] when the model produced something outside the
  /// declared schema, which the caller reports rather than executing.
  factory AiAction.fromJson(Map<String, dynamic> json) {
    final command = json['command']?.toString();
    if (command == null ||
        !const {'run', 'validate', 'doctor'}.contains(command)) {
      throw FormatException("Unsupported command '$command'");
    }

    final operation = json['operation']?.toString();
    return AiAction(
      command: command,
      operation: (operation == null || operation.isEmpty) ? null : operation,
      dryRun: json['dry_run'] == true || json['dry-run'] == true,
      reason: json['reason']?.toString() ?? 'no reason given',
    );
  }

  /// The argument vector to hand back to the CLI runner.
  List<String> toArguments() => [
        command,
        if (command == 'run' && operation != null) ...['-o', operation!],
        if (command == 'run' && dryRun) '--dry-run',
      ];

  /// How the command would be typed by hand.
  String get commandLine => 'distribute ${toArguments().join(' ')}';

  @override
  String toString() => commandLine;
}

/// What the model returned for one request.
class AiReply {
  /// Free text from the model. Present when it answered instead of acting.
  final String? text;

  /// The action it chose, when it called the tool.
  final AiAction? action;

  /// Set when the provider declined the request outright.
  final String? refusal;

  /// Creates a reply.
  const AiReply({this.text, this.action, this.refusal});

  /// Whether the model chose a command to run.
  bool get hasAction => action != null;
}

/// Raised when a provider cannot complete a request.
class AiException implements Exception {
  /// Message shown to the user.
  final String message;

  /// Creates an AI transport or protocol error.
  AiException(this.message);

  @override
  String toString() => message;
}

/// A model backend that can turn a natural-language request into an [AiAction].
///
/// Two implementations ship with the CLI — an OpenAI-compatible one covering
/// most hosted and local endpoints, and Anthropic's Messages API — because the
/// two speak different wire formats for the same idea. Everything above this
/// interface is provider-neutral.
abstract class AiProvider {
  /// Configuration this provider was built from.
  final AiConfig config;

  /// Creates a provider bound to [config].
  AiProvider(this.config);

  /// Human readable name, used in errors and in `doctor` output.
  String get name;

  /// Asks the model to map [prompt] to an action.
  ///
  /// [context] is the project-specific brief: the available task and job keys
  /// plus the command reference. Throws [AiException] on transport or protocol
  /// failure.
  Future<AiReply> complete({required String context, required String prompt});

  /// The tool the model is asked to call, as a JSON Schema.
  ///
  /// Shared verbatim by both providers — only the envelope around it differs.
  static Map<String, dynamic> get toolSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'enum': ['run', 'validate', 'doctor'],
            'description':
                'run executes build/publish tasks; validate checks the '
                    'configuration without building; doctor checks the tools '
                    'and credentials on this machine.',
          },
          'operation': {
            'type': 'string',
            'description':
                'For `run` only. A task key (e.g. "android") to run every job '
                    'in that task, or a task.job key (e.g. "android.build") to '
                    'run one job. Omit to run every task. Must be one of the '
                    'keys listed in the project context.',
          },
          'dry_run': {
            'type': 'boolean',
            'description':
                'For `run` only. Resolve and print the commands without '
                    'building or uploading anything.',
          },
          'reason': {
            'type': 'string',
            'description':
                'One short sentence explaining why this command answers the '
                    'request. Shown to the user before it runs.',
          },
        },
        'required': ['command', 'reason'],
        'additionalProperties': false,
      };

  /// Name of the tool exposed to the model.
  static const String toolName = 'run_distribute';

  /// Description of the tool exposed to the model.
  static const String toolDescription =
      'Run a distribute_cli command on the user\'s Flutter project. Call this '
      'whenever the user asks to build, publish, release, check, or validate '
      'anything. Prefer the most specific operation key that matches the '
      'request.';
}
