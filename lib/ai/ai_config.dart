import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// How much freedom the assistant has once it has chosen a command.
enum AiPermission {
  /// Show the plan and wait for a yes/no before running anything. The default.
  manual,

  /// Run the chosen command immediately, without asking.
  auto,

  /// Never execute. Print the command so it can be reviewed or copied.
  plan;

  /// Parses the `permission:` key, defaulting to [AiPermission.manual].
  static AiPermission parse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case null:
      case '':
      case 'manual':
        return AiPermission.manual;
      case 'auto':
        return AiPermission.auto;
      case 'plan':
        return AiPermission.plan;
      default:
        throw ArgumentError(
          "Invalid ai permission '$value'. Expected one of: manual, auto, plan.",
        );
    }
  }
}

/// Which wire protocol the configured endpoint speaks.
enum AiProviderKind {
  /// Anything exposing `POST {base-url}/chat/completions` — OpenAI, OpenRouter,
  /// Groq, Together, DeepSeek, a local Ollama, and most gateways.
  openai,

  /// Anthropic's Messages API (`POST {base-url}/v1/messages`).
  anthropic;

  /// Parses the `provider:` key.
  static AiProviderKind parse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'anthropic':
      case 'claude':
        return AiProviderKind.anthropic;
      case null:
      case '':
      case 'openai':
      case 'openai-compatible':
        return AiProviderKind.openai;
      default:
        throw ArgumentError(
          "Invalid ai provider '$value'. Expected 'openai' or 'anthropic'.",
        );
    }
  }

  /// Endpoint used when the configuration does not specify one.
  String get defaultBaseUrl => switch (this) {
        AiProviderKind.openai => 'https://api.openai.com/v1',
        AiProviderKind.anthropic => 'https://api.anthropic.com',
      };

  /// Model used when the configuration does not specify one.
  String get defaultModel => switch (this) {
        AiProviderKind.openai => 'gpt-4o-mini',
        AiProviderKind.anthropic => 'claude-opus-5',
      };

  /// Environment variable consulted for the API key.
  String get apiKeyEnvironmentVariable => switch (this) {
        AiProviderKind.openai => 'OPENAI_API_KEY',
        AiProviderKind.anthropic => 'ANTHROPIC_API_KEY',
      };
}

/// Which layer a resolved setting came from, least trusted last.
///
/// The order matters: `distribution.yaml` travels with a cloned repository, so
/// it is trusted less than the machine-wide store the user wrote themselves,
/// and less still than a flag they just typed.
enum AiSource {
  /// A command line flag typed for this invocation.
  flag,

  /// The `ai:` section of `distribution.yaml`, which ships with the repository.
  project,

  /// The machine-wide store at `~/.distribute/ai.json`.
  machine,

  /// Nothing supplied it; a default or the environment was used.
  none,
}

/// Everything needed to talk to a model.
///
/// Resolution order, most specific first: command line flags, the `ai:` section
/// of `distribution.yaml`, the machine-wide store, then the environment.
///
/// The API key is deliberately *not* expected in `distribution.yaml`: that file
/// belongs in version control. It lives in the machine-wide store written by
/// `distribute ai setup`, in an environment variable, or in the config as a
/// `${{VAR}}` placeholder that resolves at run time.
class AiConfig {
  /// Wire protocol of the endpoint.
  final AiProviderKind provider;

  /// Endpoint root, without the operation path.
  final String baseUrl;

  /// Model identifier passed through verbatim.
  final String model;

  /// Credential for the endpoint. Empty when none could be resolved.
  final String apiKey;

  /// How much the assistant may do on its own.
  final AiPermission permission;

  /// Ceiling on the model's response length.
  final int maxTokens;

  /// Where [baseUrl] was resolved from.
  final AiSource baseUrlSource;

  /// Where [apiKey] was resolved from.
  final AiSource apiKeySource;

  /// Whether `permission: auto` from the project file was reduced to `manual`.
  final bool permissionDemoted;

  /// Creates a resolved configuration.
  const AiConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.permission = AiPermission.manual,
    this.maxTokens = 2048,
    this.baseUrlSource = AiSource.none,
    this.apiKeySource = AiSource.none,
    this.permissionDemoted = false,
  });

  /// Whether a credential is available.
  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// Whether the project file is redirecting a credential it did not supply.
  ///
  /// Cloning a repository and running `distribute ai` would otherwise send the
  /// machine-wide key to whatever endpoint that repository names.
  bool get redirectsForeignKey =>
      baseUrlSource == AiSource.project && apiKeySource != AiSource.project;

  /// The machine-wide store, shared by every project on this machine.
  static File get globalStore => File(
        path.join(
          Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'] ??
              '.',
          '.distribute',
          'ai.json',
        ),
      );

  /// Builds a configuration from the layered sources.
  ///
  /// [yaml] is the `ai:` mapping from `distribution.yaml` (already
  /// variable-substituted); [overrides] are the command line flags.
  static AiConfig resolve({
    Map<String, dynamic>? yaml,
    Map<String, String?> overrides = const {},
    Map<String, dynamic>? global,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final stored = global ?? readGlobalStore();

    /// Where a resolved value came from. Ordered most to least trusted.
    AiSource sourceOf(String key) {
      final override = overrides[key];
      if (override != null && override.isNotEmpty) return AiSource.flag;
      final fromYaml = yaml?[key]?.toString();
      if (fromYaml != null && fromYaml.isNotEmpty) return AiSource.project;
      final fromGlobal = stored?[key]?.toString();
      if (fromGlobal != null && fromGlobal.isNotEmpty) return AiSource.machine;
      return AiSource.none;
    }

    String? pick(String key) {
      final override = overrides[key];
      if (override != null && override.isNotEmpty) return override;
      final fromYaml = yaml?[key]?.toString();
      if (fromYaml != null && fromYaml.isNotEmpty) return fromYaml;
      final fromGlobal = stored?[key]?.toString();
      if (fromGlobal != null && fromGlobal.isNotEmpty) return fromGlobal;
      return null;
    }

    final provider = AiProviderKind.parse(pick('provider'));

    /// Whether a layer's `base-url`, `model` and `api-key` still apply.
    ///
    /// They are provider-scoped: an Anthropic key and model left over from the
    /// machine-wide store, paired with `--ai-provider openai`, is not a
    /// configuration anyone asked for, and the 404 it produces blames settings
    /// the user never touched. A layer that names no provider inherits the
    /// resolved one and keeps its values, so pinning the provider in the
    /// project while keeping the key on the machine still works.
    bool agrees(Map<String, dynamic>? layer) {
      final declared = layer?['provider']?.toString();
      if (declared == null || declared.isEmpty) return true;
      try {
        return AiProviderKind.parse(declared) == provider;
      } on ArgumentError {
        return false;
      }
    }

    final yamlApplies = agrees(yaml);
    final globalApplies = agrees(stored);

    String? pickScoped(String key) {
      final override = overrides[key];
      if (override != null && override.isNotEmpty) return override;
      if (yamlApplies) {
        final fromYaml = yaml?[key]?.toString();
        if (fromYaml != null && fromYaml.isNotEmpty) return fromYaml;
      }
      if (globalApplies) {
        final fromGlobal = stored?[key]?.toString();
        if (fromGlobal != null && fromGlobal.isNotEmpty) return fromGlobal;
      }
      return null;
    }

    final permissionSource = sourceOf('permission');
    var permission = AiPermission.parse(pick('permission'));

    // `permission` is the trust decision, and `distribution.yaml` is the file
    // the assistant is being asked to reason about — a cloned repository must
    // not be able to pre-authorise its own builds and uploads. The project may
    // still restrict, which is always safe.
    var permissionDemoted = false;
    if (permissionSource == AiSource.project &&
        permission == AiPermission.auto) {
      permission = AiPermission.manual;
      permissionDemoted = true;
    }

    return AiConfig(
      provider: provider,
      baseUrl: _trimTrailingSlash(
        pickScoped('base-url') ?? provider.defaultBaseUrl,
      ),
      baseUrlSource: sourceOf('base-url'),
      model: pickScoped('model') ?? provider.defaultModel,
      apiKey: pickScoped('api-key') ??
          env[provider.apiKeyEnvironmentVariable] ??
          '',
      apiKeySource: sourceOf('api-key'),
      permission: permission,
      permissionDemoted: permissionDemoted,
      maxTokens: int.tryParse(pick('max-tokens') ?? '') ?? 2048,
    );
  }

  /// Reads the machine-wide store, or `null` when it is absent or unreadable.
  static Map<String, dynamic>? readGlobalStore() {
    final file = globalStore;
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [values] to the machine-wide store with owner-only permissions.
  ///
  /// Returns the path written, or `null` when the write failed.
  static String? writeGlobalStore(Map<String, dynamic> values) {
    final file = globalStore;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(values),
      );
      // The file holds an API key; keep it out of reach of other accounts.
      // A missing chmod is not a reason to fail — the file is already written.
      if (!Platform.isWindows) {
        try {
          Process.runSync('chmod', ['600', file.path]);
        } on ProcessException {
          // Nothing to do; the store is usable, just not locked down.
        }
      }
      return file.path;
    } on FileSystemException {
      return null;
    }
  }

  /// Renders the configuration as the `ai:` section of `distribution.yaml`.
  ///
  /// [apiKey] is written only when given. Pass a `${{VAR}}` placeholder to keep
  /// the secret out of version control while still overriding the machine-wide
  /// store, or a literal value when the file is known not to be committed.
  Map<String, dynamic> toYamlSection({String? apiKey}) => {
        'provider': provider.name,
        'base-url': baseUrl,
        'model': model,
        'permission': permission.name,
        if (apiKey != null && apiKey.isNotEmpty) 'api-key': apiKey,
      };

  /// Whether [value] is a literal secret rather than a `${{VAR}}` placeholder.
  ///
  /// Used to warn when a key is about to be written into a file that is
  /// normally committed.
  static bool looksLikeLiteralSecret(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return !value.contains(r'${') && !value.contains('%{');
  }

  /// Removes a trailing `/` so path joining stays predictable.
  static String _trimTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
