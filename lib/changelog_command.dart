import 'dart:io';

import 'package:args/args.dart';

import 'ai/ai_config.dart';
import 'ai/ai_provider.dart';
import 'ai/providers.dart';
import 'command.dart';
import 'logger.dart';
import 'parsers/changelog.dart';
import 'parsers/builtin_variables.dart';
import 'parsers/config_parser.dart';

/// Turns the git history into release notes.
///
/// The output is meant to be pasted into a store listing or a GitHub release,
/// which is why the default range is "since the previous tag" rather than the
/// whole history: that is what one release actually contains.
///
/// The same generator backs the `${{CHANGELOG}}` variable, so a pipeline can
/// feed it straight into `release-notes` or `release-body` without a wrapper
/// script — see `ChangelogSettings`.
class ChangelogCommand extends Commander {
  /// Overrides the provider for tests.
  AiProvider Function(AiConfig config)? providerFactory;

  /// Creates the changelog command.
  ChangelogCommand({this.providerFactory});

  @override
  String get description => "Generate release notes from the git history.";

  @override
  String get name => "changelog";

  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    )
    ..addOption(
      'from',
      help: 'Start of the range, exclusive. Defaults to the previous tag.',
    )
    ..addOption(
      'to',
      help: 'End of the range, inclusive.',
      defaultsTo: 'HEAD',
    )
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ['markdown', 'plain'],
      help: 'How to render the notes.',
      allowedHelp: {
        'markdown': 'Headed sections and bullets, for a GitHub release.',
        'plain': 'A flat bullet list, for stores that show plain text.',
      },
    )
    ..addFlag(
      'group',
      defaultsTo: true,
      help: 'Group markdown output by conventional commit type.',
    )
    ..addFlag(
      'shas',
      negatable: false,
      defaultsTo: false,
      help: 'Append the short commit hash to every line.',
    )
    ..addOption(
      'limit',
      help: 'Stop after this many commits.',
    )
    ..addFlag(
      'merges',
      negatable: false,
      defaultsTo: false,
      help: 'Include merge commits.',
    )
    ..addFlag(
      'ai',
      negatable: false,
      defaultsTo: false,
      help: 'Rewrite the notes with the configured model before printing.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Write to this file instead of stdout.',
    );

  @override
  Future<int> run() async {
    // The configuration is optional here: reading the git history does not
    // need one, and `distribute changelog` is useful before `init` has run.
    ChangelogSettings settings = const ChangelogSettings();
    Map<String, dynamic> aiSection = const {};

    final file = File(configPath);
    if (!file.existsSync() && _configWasTyped) {
      // A default that is not there is fine — the history does not need one.
      // A path the user typed is different: silently ignoring it would read as
      // if the settings had been applied.
      logger.logError("Configuration file '$configPath' not found.");
      return 1;
    }
    if (file.existsSync()) {
      try {
        final config = await ConfigParser.distributeYaml(
          configPath,
          globalResults,
        );
        settings = ChangelogSettings.fromYaml(config.changelog);
        // The key is commonly stored as `${{OPENAI_API_KEY}}`, so it has to be
        // resolved before it reaches the provider — otherwise the placeholder
        // itself is sent as the credential.
        aiSection = {
          for (final entry in config.ai.entries)
            entry.key: entry.value is String
                ? await config.variables.process(entry.value as String)
                : entry.value,
        };
      } on ConfigException catch (e) {
        logger.logError(e.message);
        return 1;
      } on ArgumentError catch (e) {
        logger.logError('${e.message}');
        logger.logDetail('check the `changelog:` section of $configPath');
        return 1;
      }
    }

    final limit = _parsedLimit();
    if (!limit.ok) return 64;

    final Changelog changelog;
    try {
      changelog = await Changelog.fromGit(
        from: (argResults!['from'] as String?) ?? settings.from,
        to: argResults!['to'] as String,
        limit: limit.value ?? settings.limit,
        includeMerges:
            (argResults!['merges'] as bool) || settings.includeMerges,
      );
    } on ChangelogException catch (e) {
      logger.logError(e.message);
      return 1;
    }

    if (changelog.shallow) {
      ColorizeLogger.reserveStdout = true;
      logger.logWarning(
        'this is a shallow clone, so the notes may be missing older commits',
      );
      logger.logDetail(
        'fetch the full history first — `git fetch --unshallow`, or '
        '`fetch-depth: 0` on a CI checkout',
      );
    }

    if (changelog.isEmpty) {
      ColorizeLogger.reserveStdout = true;
      logger.logWarning('no commits in ${changelog.range}');
      logger.logDetail(
        'pass --from to widen the range, or tag the previous release',
      );
      // An empty range must not leave whatever `-o` pointed at in place: a
      // stale file next to a successful exit reads as "these are the notes".
      final target = argResults!['output'] as String?;
      if (target != null && target.isNotEmpty && File(target).existsSync()) {
        logger.logWarning('$target still holds the notes from an earlier run');
      }
      return 0;
    }

    final format = argResults!.wasParsed('format')
        ? ChangelogFormat.parse(argResults!['format'] as String)
        : settings.format;

    var rendered = changelog.render(
      format: format,
      group: argResults!.wasParsed('group')
          ? argResults!['group'] as bool
          : settings.group,
      includeShas: (argResults!['shas'] as bool) || settings.includeShas,
    );

    final output = argResults!['output'] as String?;
    // Without `-o` the notes are the command's stdout, so every log line has
    // to move aside — otherwise `distribute changelog --ai > NOTES.md` writes
    // the progress line into the notes.
    if (output == null || output.isEmpty) {
      ColorizeLogger.reserveStdout = true;
      ColorizeLogger.retargetColors();
    }

    if ((argResults!['ai'] as bool) || settings.ai) {
      final polished = await _polish(rendered, aiSection, settings);
      if (polished == null) return 1;
      rendered = polished;
    }

    if (output == null || output.isEmpty) {
      // The notes are the product of this command, so they go to stdout on
      // their own; everything else the command said went to stderr.
      stdout.writeln(rendered);
      return 0;
    }

    try {
      final target = File(output);
      await target.parent.create(recursive: true);
      await target.writeAsString('$rendered\n');
      logger.logSuccess(
        'wrote ${changelog.entries.length} entr'
        '${changelog.entries.length == 1 ? 'y' : 'ies'} to $output',
      );
      logger.logDetail('range: ${changelog.range}');
      return 0;
    } on FileSystemException catch (e) {
      logger.logError('could not write $output: ${e.message}');
      return 1;
    }
  }

  /// Whether `--config` was typed rather than left at its default.
  bool get _configWasTyped =>
      (argResults?.wasParsed('config') ?? false) ||
      (globalResults?.wasParsed('config') ?? false);

  /// Validates `--limit`.
  ///
  /// `(ok: false, …)` means the value was unusable and the error has already
  /// been reported; a bare null would be indistinguishable from "not given".
  ({bool ok, int? value}) _parsedLimit() {
    final raw = argResults!['limit'] as String?;
    if (raw == null || raw.isEmpty) return (ok: true, value: null);
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      logger.logError("--limit must be a positive whole number, got '$raw'");
      return (ok: false, value: null);
    }
    return (ok: true, value: parsed);
  }

  /// Sends [notes] to the model for an editorial pass.
  ///
  /// Returns null when the request failed, having already reported why; the
  /// command then exits non-zero rather than printing the unpolished notes.
  /// Asking for edited notes and silently getting raw commit subjects is the
  /// one outcome nobody wants at publish time.
  Future<String?> _polish(
    String notes,
    Map<String, dynamic> aiSection,
    ChangelogSettings settings,
  ) async {
    final AiConfig ai;
    try {
      ai = AiConfig.resolve(yaml: aiSection);
    } on ArgumentError catch (e) {
      logger.logError('${e.message}');
      return null;
    }

    if (!ai.hasApiKey) {
      logger.logError('no API key configured for ${ai.provider.name}');
      logger.logDetail(
        'run `distribute ai --setup`, or set '
        '${ai.provider.apiKeyEnvironmentVariable}',
      );
      return null;
    }
    ColorizeLogger.registerSecret(ai.apiKey);

    if (ai.redirectsForeignKey) {
      // Same rule as `distribute ai`: the project file naming the endpoint
      // while the key comes from elsewhere means a cloned repository decides
      // where your credential goes.
      logger.logWarning(
        '$configPath points the endpoint at ${ai.baseUrl}, '
        'but the API key comes from elsewhere',
      );
    }

    final sep = LogSymbols.separator;
    logger.logInfo(
      ColorizeLogger.dim(
        ['polishing with', ai.provider.name, ai.model, ai.baseUrl]
            .join('  $sep  '),
      ),
    );

    try {
      final provider = (providerFactory ?? createProvider)(ai);
      final result = await provider.rewrite(
        instruction: settings.prompt ?? defaultPrompt,
        text: notes,
      );
      // The reply is displayed and may be written to a file, so it gets the
      // same treatment as any other model output: no control characters.
      return sanitize(result);
    } on AiException catch (e) {
      logger.logError(e.message);
      logger.logDetail('the unpolished notes are still available without --ai');
      return null;
    }
  }

  /// Strips everything that could make the printed notes differ from the
  /// written ones.
  ///
  /// A carriage return rewrites the line on a terminal while surviving into a
  /// file, and DEL is invisible in both — so what the user reviews would not be
  /// what gets published.
  static String sanitize(String value) => ColorizeLogger.stripAnsi(value)
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
      .trim();

  /// What the model is told to do with the generated notes.
  ///
  /// Deliberately conservative: an invented feature in a store listing is worse
  /// than an awkward sentence, so the instruction forbids adding anything.
  static const String defaultPrompt = '''
You are editing release notes that were generated from git commit subjects.

Rewrite them so they read well to someone using the app, and return only the
rewritten notes.

Rules:
- Never invent a change. Every line must correspond to one you were given.
- Never drop a change. If two lines describe the same thing, merge them.
- Keep the existing section headings and list structure.
- Drop commit-message noise: ticket ids, branch names, "wip", "misc fixes".
- Write in the present tense, without a trailing full stop.
- Reply with the notes alone: no preamble, no explanation, no code fence.''';
}

/// Installs the `${{CHANGELOG}}` polisher when `changelog: ai:` asks for one.
///
/// Called by whoever loaded the configuration. Kept here, next to the prompt
/// and the provider wiring, so `BuiltinVariables` stays free of any dependency
/// on the AI adapters.
void installChangelogPolisher({
  required Map<String, dynamic> changelogSection,
  required Map<String, dynamic> aiSection,
  AiProvider Function(AiConfig config)? providerFactory,
}) {
  final settings = ChangelogSettings.fromYaml(changelogSection);
  if (!settings.ai) return;

  BuiltinVariables.changelogPolisher = (notes) async {
    final ai = AiConfig.resolve(yaml: aiSection);
    if (!ai.hasApiKey) {
      throw ChangelogException(
        'changelog.ai is on but no API key is configured for '
        '${ai.provider.name}; run `distribute ai --setup`, set '
        '${ai.provider.apiKeyEnvironmentVariable}, or turn changelog.ai off',
      );
    }
    ColorizeLogger.registerSecret(ai.apiKey);

    final provider = (providerFactory ?? createProvider)(ai);
    try {
      final result = await provider.rewrite(
        instruction: settings.prompt?.trim().isNotEmpty == true
            ? settings.prompt!
            : ChangelogCommand.defaultPrompt,
        text: notes,
      );
      return ChangelogCommand.sanitize(result);
    } on AiException catch (e) {
      // Publishing raw commit subjects when edited notes were asked for is a
      // surprise at the worst possible moment, so this fails the job.
      throw ChangelogException('could not polish the changelog: ${e.message}');
    }
  };
}

/// The `changelog:` section of `distribution.yaml`.
///
/// Defaults chosen so that `${{CHANGELOG}}` is useful with no configuration at
/// all: markdown, grouped, since the previous tag.
class ChangelogSettings {
  /// Start of the range. Null means "the previous tag".
  final String? from;

  /// How the notes are rendered.
  final ChangelogFormat format;

  /// Whether markdown output is grouped by conventional commit type.
  final bool group;

  /// Whether each line carries its short commit hash.
  final bool includeShas;

  /// Whether merge commits are listed.
  final bool includeMerges;

  /// Cap on the number of commits read.
  final int? limit;

  /// Whether `${{CHANGELOG}}` is polished by the model.
  ///
  /// Off by default: it sends commit subjects to a third party and costs a
  /// request on every publish, which is not a decision to make for the user.
  final bool ai;

  /// Overrides the instruction sent with `--ai`.
  final String? prompt;

  /// Creates the settings.
  const ChangelogSettings({
    this.from,
    this.format = ChangelogFormat.markdown,
    this.group = true,
    this.includeShas = false,
    this.includeMerges = false,
    this.limit,
    this.ai = false,
    this.prompt,
  });

  /// Reads the settings from the raw `changelog:` mapping.
  ///
  /// Throws [ArgumentError] with an actionable message for an unusable value,
  /// which the caller re-labels with the file it came from.
  factory ChangelogSettings.fromYaml(Map<String, dynamic> yaml) {
    int? readLimit() {
      final raw = yaml['limit'];
      if (raw == null) return null;
      final parsed = raw is int ? raw : int.tryParse(raw.toString().trim());
      if (parsed == null || parsed <= 0) {
        throw ArgumentError(
          "changelog.limit must be a positive whole number, got '$raw'.",
        );
      }
      return parsed;
    }

    bool readFlag(String key, {bool defaultValue = false}) {
      final raw = yaml[key];
      if (raw == null) return defaultValue;
      if (raw is bool) return raw;
      switch (raw.toString().toLowerCase().trim()) {
        case 'true':
        case 'yes':
          return true;
        case 'false':
        case 'no':
          return false;
      }
      throw ArgumentError(
        "changelog.$key must be true or false, got '$raw'.",
      );
    }

    final from = yaml['from']?.toString().trim();

    return ChangelogSettings(
      from: from == null || from.isEmpty ? null : from,
      format: ChangelogFormat.parse(yaml['format']?.toString()),
      group: readFlag('group', defaultValue: true),
      includeShas: readFlag('shas'),
      includeMerges: readFlag('merges'),
      limit: readLimit(),
      ai: readFlag('ai'),
      prompt: yaml['prompt']?.toString(),
    );
  }
}
