import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml_codec/yaml_codec.dart';

import 'ai/ai_config.dart';
import 'ai/ai_provider.dart';
import 'ai/ai_reference.dart';
import 'ai/providers.dart';
import 'command.dart';
import 'logger.dart';
import 'parsers/config_parser.dart';
import 'prompt.dart';

/// Natural-language front end for the CLI.
///
/// `distribute ai setup` configures a model; `distribute ai "<request>"` asks it
/// to pick a command. The assistant never composes a shell string — it fills in
/// a constrained schema listing only the commands and the operation keys that
/// exist in this project, which is what makes the `auto` permission defensible.
class AiCommand extends Commander {
  /// Runs an argument vector through the same CommandRunner as a typed command.
  ///
  /// Injected by `main` so the assistant executes real commands rather than
  /// re-implementing them or shelling out.
  Future<int> Function(List<String> arguments)? executor;

  /// Overrides the provider for tests.
  AiProvider Function(AiConfig config)? providerFactory;

  /// Creates the AI command.
  AiCommand({this.executor, this.providerFactory});

  @override
  String get description =>
      "Ask a model to pick the right distribute command for you.";

  @override
  String get name => "ai";

  @override
  // Trailing options stay enabled so `distribute ai "..." -p auto` works — the
  // natural way to write it. A prompt that genuinely starts with a dash can be
  // separated with `--`.
  ArgParser get argParser => ArgParser(allowTrailingOptions: true)
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    )
    ..addFlag(
      'setup',
      negatable: false,
      defaultsTo: false,
      help: 'Run the interactive setup wizard instead of asking a question.',
    )
    ..addOption(
      'ai-provider',
      help: 'Override the provider for this run (openai, anthropic).',
    )
    ..addOption('ai-url', help: 'Override the endpoint base URL for this run.')
    ..addOption('ai-key', help: 'Override the API key for this run.')
    ..addOption('ai-model', help: 'Override the model for this run.')
    ..addOption(
      'permission',
      abbr: 'p',
      allowed: ['manual', 'auto', 'plan'],
      help: 'Override how much the assistant may do on its own.',
      allowedHelp: {
        'manual': 'Show the command and ask before running it.',
        'auto': 'Run the chosen command without asking.',
        'plan': 'Print the command; never execute.',
      },
    );

  String get _configPath => super.configPath;

  @override
  Future<int> run() async {
    if (argResults!['setup'] as bool ||
        argResults!.rest.firstOrNull == 'setup') {
      return _runSetup();
    }

    final request = argResults!.rest.join(' ').trim();
    if (request.isEmpty) {
      logger.logError('nothing to ask');
      logger.logDetail('try: distribute ai "build the ios app"');
      logger.logDetail('or configure a model first: distribute ai --setup');
      return 64;
    }

    return _ask(request);
  }

  /// Loads the configuration and resolves the AI settings from every source.
  Future<(ConfigParser, AiConfig)?> _load() async {
    final ConfigParser config;
    try {
      config = await ConfigParser.distributeYaml(_configPath, globalResults);
    } on ConfigException catch (e) {
      logger.logError(e.message);
      return null;
    }

    // Resolve `${{VAR}}` in the ai section before it reaches the provider, so a
    // key stored as a placeholder in distribution.yaml works like any other.
    final section = <String, dynamic>{};
    for (final entry in config.ai.entries) {
      section[entry.key] = entry.value is String
          ? await config.variables.process(entry.value as String)
          : entry.value;
    }

    final AiConfig ai;
    try {
      ai = AiConfig.resolve(
        yaml: section,
        overrides: {
          'provider': argResults?['ai-provider'] as String?,
          'base-url': argResults?['ai-url'] as String?,
          'api-key': argResults?['ai-key'] as String?,
          'model': argResults?['ai-model'] as String?,
          'permission': argResults?['permission'] as String?,
        },
      );
    } on ArgumentError catch (e) {
      // The bad value could have come from any layer, so name them all rather
      // than guessing — otherwise the user edits the wrong file.
      logger.logError('${e.message}');
      logger.logDetail(
        'check the `ai:` section of $_configPath, '
        '${AiConfig.globalStore.path}, or the flag you passed',
      );
      return null;
    }

    ColorizeLogger.registerSecret(ai.apiKey);
    return (config, ai);
  }

  /// Answers one natural-language request.
  Future<int> _ask(String request) async {
    final loaded = await _load();
    if (loaded == null) return 1;
    final (config, ai) = loaded;

    if (!ai.hasApiKey) {
      logger.logError('no API key configured for ${ai.provider.name}');
      logger.logDetail(
        'run `distribute ai --setup`, set ${ai.provider.apiKeyEnvironmentVariable}, '
        'or pass --ai-key',
      );
      return 1;
    }

    final sep = LogSymbols.separator;
    // The endpoint is part of the header because the project file can set it:
    // the user has to be able to see where their key is about to be sent.
    logger.logInfo(
      ColorizeLogger.dim(
        [
          ai.provider.name,
          ai.model,
          ai.baseUrl,
          'permission: ${ai.permission.name}',
        ].join('  $sep  '),
      ),
    );

    if (ai.permissionDemoted) {
      logger.logWarning(
        '$_configPath asks for `permission: auto`; using manual instead',
      );
      logger.logDetail(
        'a configuration file travels with the repository, so it cannot grant '
        'itself the right to build and publish — pass -p auto, or set it in '
        '${AiConfig.globalStore.path}',
      );
    }

    if (ai.redirectsForeignKey) {
      logger.logWarning(
        '$_configPath points the endpoint at ${ai.baseUrl}, '
        'but the API key comes from elsewhere',
      );
      logger.logDetail(
        'that sends your key to an endpoint this repository chose; '
        'override it with --ai-url if that is not what you want',
      );
    }

    logger.logEmpty();

    final provider = (providerFactory ?? createProvider)(ai);

    final AiReply reply;
    try {
      reply = await provider.complete(
        context: AiReference.build(config),
        prompt: request,
      );
    } on AiException catch (e) {
      logger.logError(e.message);
      return 1;
    } on FormatException catch (e) {
      logger.logError('the model proposed something invalid: ${e.message}');
      return 1;
    }

    if (reply.refusal != null) {
      logger.logError(_sanitize(reply.refusal!, limit: 500));
      return 1;
    }

    final action = reply.action;
    if (action == null) {
      // No tool call: the model answered in prose instead of choosing a
      // command. Show it — usually it is explaining that nothing matched.
      logger.logInfo(reply.text == null
          ? 'the model did not propose a command'
          : _sanitize(reply.text!, limit: 2000));
      return 1;
    }

    // Everything below is model-supplied. Escape sequences in it would let the
    // response repaint the confirmation line the user is about to answer, so
    // they are stripped even when colours are on, and the text is capped.
    logger.logStep(_sanitize(action.commandLine, limit: 200));
    logger.logDetail(_sanitize(action.reason, limit: 500));
    logger.logEmpty();

    return _execute(action, ai.permission);
  }

  /// Renders model-supplied text so it cannot repaint the terminal.
  ///
  /// [ColorizeLogger] only strips escapes when colours are off, which is the
  /// right default for the CLI's own output but not for a string that came back
  /// over the network. Control characters are removed, newlines flattened and
  /// the result truncated, so a reply can describe a command but never redraw
  /// the confirmation the user is answering.
  static String _sanitize(String value, {required int limit}) {
    final flat = ColorizeLogger.stripAnsi(value)
        .replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'), '')
        .replaceAll('\n', ' ')
        .trim();
    if (flat.isEmpty) return '(nothing said)';
    return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
  }

  /// Runs [action] according to [permission].
  Future<int> _execute(AiAction action, AiPermission permission) async {
    switch (permission) {
      case AiPermission.plan:
        logger.logNote('plan mode — nothing was run');
        return 0;

      case AiPermission.manual:
        if (!Prompt.isInteractive) {
          logger.logError(
            'permission is `manual` but there is no terminal to confirm with',
          );
          logger.logDetail(
            'use --permission auto to run it, or --permission plan to only print it',
          );
          return 1;
        }
        if (!Prompt(logger).confirm('Run this command?')) {
          logger.logNote('cancelled');
          return 130;
        }

      case AiPermission.auto:
        logger.logNote('auto mode — running');
    }

    logger.logEmpty();
    final run = executor;
    if (run == null) {
      logger.logError('no executor wired up; cannot run the command');
      return 1;
    }

    // The nested invocation re-parses from scratch, so the configuration file
    // has to be carried across explicitly — otherwise a run started from a
    // non-default config silently executes against distribution.yaml.
    final arguments = [
      ...action.toArguments(),
      if (_configPath != 'distribution.yaml') ...['--config', _configPath],
    ];
    return run(arguments);
  }

  /// Interactive configuration.
  Future<int> _runSetup() async {
    if (!Prompt.isInteractive) {
      logger.logError('setup needs an interactive terminal');
      logger.logDetail(
        'configure it non-interactively with the `ai:` section of $_configPath',
      );
      return 1;
    }

    final prompt = Prompt(logger);
    logger.logInfo(ColorizeLogger.dim('distribute ai  ·  setup'));
    logger.logEmpty();

    final existing = AiConfig.resolve();

    final provider = prompt.select<AiProviderKind>(
      'Which API does your endpoint speak?',
      AiProviderKind.values,
      defaultIndex: AiProviderKind.values.indexOf(existing.provider),
      label: (kind) => switch (kind) {
        AiProviderKind.openai => 'OpenAI-compatible',
        AiProviderKind.anthropic => 'Anthropic',
      },
      describe: (kind) => switch (kind) {
        AiProviderKind.openai =>
          'OpenAI, OpenRouter, Groq, Together, DeepSeek, Ollama',
        AiProviderKind.anthropic => 'Claude, via the Messages API',
      },
    );
    logger.logEmpty();

    final baseUrl = prompt.text(
      'Base URL',
      defaultValue: existing.provider == provider
          ? existing.baseUrl
          : provider.defaultBaseUrl,
    );
    final model = prompt.text(
      'Model',
      defaultValue: existing.provider == provider
          ? existing.model
          : provider.defaultModel,
    );

    final envVar = provider.apiKeyEnvironmentVariable;
    final fromEnv = Platform.environment[envVar];
    final apiKey = prompt.secret(
      fromEnv == null
          ? 'API key'
          : 'API key ${ColorizeLogger.dim("(enter to use \$$envVar)")}',
      allowEmpty: fromEnv != null,
    );
    logger.logEmpty();

    final permission = prompt.select<AiPermission>(
      'How much may the assistant do on its own?',
      AiPermission.values,
      defaultIndex: AiPermission.values.indexOf(existing.permission),
      label: (value) => value.name,
      describe: (value) => switch (value) {
        AiPermission.manual => 'show the command, ask before running it',
        AiPermission.auto => 'run it straight away',
        AiPermission.plan => 'only print it, never run',
      },
    );
    logger.logEmpty();

    final config = AiConfig(
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey.isEmpty ? (fromEnv ?? '') : apiKey,
      permission: permission,
    );

    return _persist(config, typedKey: apiKey, prompt: prompt);
  }

  /// Writes the resolved settings where the user chooses.
  Future<int> _persist(
    AiConfig config, {
    required String typedKey,
    required Prompt prompt,
  }) async {
    final saveGlobally = prompt.confirm(
      'Save this for every project on this machine?',
    );

    if (saveGlobally) {
      final stored = AiConfig.writeGlobalStore({
        ...config.toYamlSection(),
        if (typedKey.isNotEmpty) 'api-key': typedKey,
      });
      if (stored == null) {
        logger.logError('could not write ${AiConfig.globalStore.path}');
        return 1;
      }
      logger.logSuccess('saved  ${ColorizeLogger.dim(stored)}');
    }

    final saveToProject = prompt.confirm(
      saveGlobally
          ? 'Also pin it in $_configPath for this project?'
          : 'Save it in $_configPath instead?',
      defaultValue: !saveGlobally,
    );

    if (saveToProject) {
      // The key is only offered here when it is not already stored globally,
      // and it is written as a placeholder unless the user insists, because
      // distribution.yaml is normally committed.
      String? projectKey;
      if (!saveGlobally && typedKey.isNotEmpty) {
        final inline = prompt.confirm(
          'Write the API key into $_configPath? '
          '${ColorizeLogger.dim("(this file is usually committed)")}',
          defaultValue: false,
        );
        projectKey = inline
            ? typedKey
            : '\${{${config.provider.apiKeyEnvironmentVariable}}}';
        if (!inline) {
          logger.logNote(
            'using \${{${config.provider.apiKeyEnvironmentVariable}}} — '
            'export that variable before running',
          );
        }
      }

      final written = await _writeSection(config, apiKey: projectKey);
      if (!written) return 1;
    }

    if (!saveGlobally && !saveToProject) {
      logger.logWarning('nothing saved; these settings apply to this run only');
    }

    logger.logEmpty();
    logger.logSuccess('ready');
    logger.logDetail('try: distribute ai "build the ios app"');
    return 0;
  }

  /// Merges the `ai:` section into the configuration file.
  Future<bool> _writeSection(AiConfig config, {String? apiKey}) async {
    final file = File(_configPath);
    if (!file.existsSync()) {
      logger.logError('$_configPath not found; run `distribute init` first');
      return false;
    }

    try {
      final original = file.readAsStringSync();
      // Re-encoding the document drops comments and reflows the formatting, so
      // say it out loud rather than letting the user discover it in a diff.
      if (original.contains('#')) {
        logger.logWarning(
          'rewriting $_configPath will drop its comments and reformat it',
        );
        if (!Prompt(logger).confirm('Continue?', defaultValue: false)) {
          logger.logNote('left $_configPath untouched');
          logger.logDetail(
            'add the section by hand:\n'
            '${yamlEncode({'ai': config.toYamlSection(apiKey: apiKey)})}',
          );
          return true;
        }
      }

      final json = ConfigParser.readRawYaml(file);
      json['ai'] = config.toYamlSection(apiKey: apiKey);
      await file.writeAsString(yamlEncode(json), flush: true);
      logger.logSuccess('saved  ${ColorizeLogger.dim(_configPath)}');
      if (AiConfig.looksLikeLiteralSecret(apiKey)) {
        logger.logWarning(
            '$_configPath now contains an API key — do not commit it');
      }
      return true;
    } on FileSystemException catch (e) {
      logger.logError('could not write $_configPath: ${e.message}');
      return false;
    }
  }
}
