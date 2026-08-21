import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'command.dart';
import 'logger.dart';
import 'parsers/config_parser.dart';
import 'parsers/job_arguments.dart';

/// Validates `distribution.yaml` without building or uploading anything.
///
/// This is the cheap pre-flight check meant to run in CI (or in a git hook)
/// before a release pipeline burns minutes on a build that was going to fail on
/// a typo. It reports two classes of problems:
///
/// - **Errors** - the configuration cannot be executed at all (missing keys,
///   unknown workflow references, duplicate keys). These fail the command.
/// - **Warnings** - the configuration parses but looks suspicious (unresolved
///   `${{VAR}}` placeholders, missing credential files). These do not fail the
///   command unless `--strict` is passed.
class ValidateCommand extends Commander {
  @override
  String get description =>
      "Validate the distribution configuration without running any job.";

  @override
  String get name => "validate";

  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    )
    ..addFlag(
      'strict',
      negatable: false,
      defaultsTo: false,
      help: 'Treat warnings as errors.',
    );

  @override
  Future<int> run() async {
    final configPath = super.configPath;
    final strict = argResults!['strict'] as bool;

    final ConfigParser config;
    try {
      config = await ConfigParser.distributeYaml(configPath, globalResults);
    } on ConfigException catch (e) {
      logger.logError(e.message);
      return 1;
    }

    final warnings = <String>[];
    warnings.addAll(_inspectUnknownKeys(configPath, config));

    for (final task in config.tasks) {
      for (final job in task.jobs) {
        final where = "${task.key}.${job.key ?? job.name}";
        warnings.addAll(await _inspectJob(where, job));
      }
    }

    for (final notification in config.notifications) {
      final url = await config.variables.process(notification.webhookUrl);
      if (_hasUnresolvedPlaceholder(url)) {
        warnings.add(
          "notifications > ${notification.provider.name} webhook-url still "
          "contains an unresolved placeholder. Export the secret before running.",
        );
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        warnings.add(
          "notifications > ${notification.provider.name} webhook-url does not "
          "look like an HTTP endpoint.",
        );
      }
    }

    final jobCount =
        config.tasks.fold<int>(0, (sum, task) => sum + task.jobs.length);
    final sep = LogSymbols.separator;
    logger.logInfo(
      ColorizeLogger.dim(
        [
          configPath,
          '${config.tasks.length} task(s)',
          '$jobCount job(s)',
          '${config.notifications.length} notification(s)',
        ].join('  $sep  '),
      ),
    );
    logger.logEmpty();

    if (warnings.isEmpty) {
      logger.logSuccess("no problems found");
      return 0;
    }

    for (final warning in warnings) {
      logger.logWarning(warning);
    }
    logger.logEmpty();

    final tally = "${warnings.length} warning(s)";
    if (strict) {
      logger
          .logError("$tally  ${ColorizeLogger.dim("failing due to --strict")}");
      return 1;
    }
    logger.logWarning(tally);
    return 0;
  }

  /// Reports keys the parser does not recognise.
  ///
  /// A mistyped key is silently ignored everywhere else — `binary-typ: aab`
  /// parses fine and quietly builds an APK, which is exactly the sort of
  /// mistake that only shows up after the wrong artifact reaches a store. The
  /// comparison is done against the raw YAML because the parsed objects have
  /// already discarded anything unrecognised.
  ///
  /// Reported as warnings rather than errors so a configuration written for a
  /// newer version of the CLI still runs on an older one.
  List<String> _inspectUnknownKeys(String configPath, ConfigParser config) {
    final warnings = <String>[];

    final Map<String, dynamic> raw;
    try {
      raw = ConfigParser.readRawYaml(File(configPath));
    } on FileSystemException {
      return warnings;
    }

    void check(String where, Map<String, dynamic> map, Set<String> known) {
      for (final key in map.keys) {
        if (known.contains(key)) continue;
        final suggestion = _closestKey(key, known);
        warnings.add(
          "$where has an unknown key '$key'; it is ignored"
          "${suggestion == null ? '' : " — did you mean '$suggestion'?"}",
        );
      }
    }

    check(configPath, raw, const {
      'name',
      'description',
      'variables',
      'tasks',
      'notifications',
      'ai',
      'changelog',
      'parallel',
      'on-error',
      'pre',
      'post',
      'version',
      'clean',
      'arguments',
      'output',
    });

    final rawParallel = raw['parallel'];
    if (rawParallel is Map) {
      check('parallel', Map<String, dynamic>.from(rawParallel), const {
        'tasks',
        'gap',
      });
    }
    final rawVersion = raw['version'];
    if (rawVersion is Map) {
      check('version', Map<String, dynamic>.from(rawVersion), const {
        'name',
        'code',
        'write-back',
      });
    }
    final rawClean = raw['clean'];
    if (rawClean is Map) {
      check('clean', Map<String, dynamic>.from(rawClean), const {
        'on',
        'flutter',
        'outputs',
      });
    }

    final rawChangelog = raw['changelog'];
    if (rawChangelog is Map) {
      check('changelog', Map<String, dynamic>.from(rawChangelog), const {
        'from',
        'format',
        'group',
        'shas',
        'merges',
        'limit',
        'ai',
        'prompt',
      });
    }

    // Keys the parser tolerates but nothing acts on. Silently accepting them
    // is worse than rejecting them: the user believes the setting is doing
    // something.
    for (final inert in const ['arguments']) {
      if (raw.containsKey(inert)) {
        warnings.add(
          "$configPath declares '$inert', which nothing reads yet — "
          "it has no effect",
        );
      }
    }

    final rawAi = raw['ai'];
    if (rawAi is Map) {
      check('ai', Map<String, dynamic>.from(rawAi), const {
        'provider',
        'base-url',
        'model',
        'api-key',
        'permission',
        'max-tokens',
      });
    }

    final rawNotifications = raw['notifications'];
    if (rawNotifications is List) {
      for (var i = 0; i < rawNotifications.length; i++) {
        final entry = rawNotifications[i];
        if (entry is! Map) continue;
        check('notifications[$i]', Map<String, dynamic>.from(entry), const {
          'provider',
          'webhook-url',
          'on',
          'title',
          'message',
          'chat-id',
        });
      }
    }

    final rawTasks = raw['tasks'];
    if (rawTasks is! List) return warnings;

    for (final task in config.tasks) {
      final workflows = task.workflows;
      if (workflows == null) continue;
      final seen = <String>{};
      for (final entry in workflows) {
        if (!seen.add(entry)) {
          warnings.add(
            "task ${task.key} lists '$entry' in workflows more than once, "
            "so that job runs more than once",
          );
        }
      }
    }

    for (var t = 0; t < rawTasks.length && t < config.tasks.length; t++) {
      final rawTask = rawTasks[t];
      if (rawTask is! Map) continue;
      final task = config.tasks[t];

      check('task ${task.key}', Map<String, dynamic>.from(rawTask), const {
        'name',
        'key',
        'description',
        'workflows',
        'pre',
        'post',
        'jobs',
      });

      final rawJobs = rawTask['jobs'];
      if (rawJobs is! List) continue;

      for (var j = 0; j < rawJobs.length && j < task.jobs.length; j++) {
        final rawJob = rawJobs[j];
        if (rawJob is! Map) continue;
        final job = task.jobs[j];
        final where = '${task.key}.${job.key ?? job.name}';

        check(where, Map<String, dynamic>.from(rawJob), const {
          'name',
          'key',
          'description',
          'package_name',
          'continue-on-error',
          'retry',
          'retry-delay',
          'timeout',
          'pre',
          'post',
          'builder',
          'publisher',
        });

        // The leaf option names are whatever each argument class serialises,
        // so they stay in step automatically as options are added.
        final sections = <String, Map<String, JobArguments?>>{
          'builder': {
            'android': job.builder?.android,
            'ios': job.builder?.ios,
          },
          'publisher': {
            'fastlane': job.publisher?.fastlane,
            'firebase': job.publisher?.firebase,
            'xcrun': job.publisher?.xcrun,
            'github': job.publisher?.github,
            'huawei': job.publisher?.huawei,
          },
        };

        for (final section in sections.entries) {
          final rawSection = rawJob[section.key];
          if (rawSection is! Map) continue;

          check(
            '$where > ${section.key}',
            Map<String, dynamic>.from(rawSection),
            section.value.keys.toSet(),
          );

          for (final platform in section.value.entries) {
            final rawPlatform = rawSection[platform.key];
            final parsed = platform.value;
            if (rawPlatform is! Map || parsed == null) continue;
            check(
              '$where > ${section.key}.${platform.key}',
              Map<String, dynamic>.from(rawPlatform),
              parsed.toJson().keys.toSet(),
            );
          }
        }
      }
    }

    return warnings;
  }

  /// The known key closest to [key], when one is close enough to suggest.
  ///
  /// Bounded edit distance keeps the suggestion useful: `binary-typ` should
  /// point at `binary-type`, but an entirely unrelated key should not point
  /// anywhere at all.
  static String? _closestKey(String key, Set<String> known) {
    String? best;
    var bestDistance = 1 << 30;
    for (final candidate in known) {
      final distance = _editDistance(key, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    final limit = key.length <= 4 ? 1 : 3;
    return bestDistance <= limit ? best : null;
  }

  /// Levenshtein distance between [a] and [b].
  static int _editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  /// Collects warnings for a single job's resolved configuration.
  Future<List<String>> _inspectJob(String where, Job job) async {
    final warnings = <String>[];
    final sections = <String, JobArguments?>{
      'builder.android': job.builder?.android,
      'builder.ios': job.builder?.ios,
      'publisher.fastlane': job.publisher?.fastlane,
      'publisher.firebase': job.publisher?.firebase,
      'publisher.xcrun': job.publisher?.xcrun,
      'publisher.github': job.publisher?.github,
    };

    for (final entry in sections.entries) {
      final arguments = entry.value;
      if (arguments == null) continue;

      final raw = arguments.toJson();
      for (final key in raw.keys) {
        final value = raw[key];
        if (value is! String || value.isEmpty) continue;

        final resolved = await arguments.variables.process(value);
        if (_hasUnresolvedPlaceholder(resolved)) {
          warnings.add(
            "$where > ${entry.key}.$key still contains an unresolved "
            "placeholder: '$resolved'. Define it under `variables` or export it "
            "as an environment variable.",
          );
          continue;
        }

        if (_looksLikeRequiredPath(key) && !_pathExists(resolved)) {
          warnings.add(
            "$where > ${entry.key}.$key points to '$resolved', which does not exist yet.",
          );
        }
      }
    }

    return warnings;
  }

  /// Whether [value] still contains a `${{VAR}}`, `${VAR}` or `%{{CMD}}` token.
  static bool _hasUnresolvedPlaceholder(String value) =>
      RegExp(r'\$\{\{?\w+\}?\}').hasMatch(value);

  /// Configuration keys that must point at an existing file at run time.
  ///
  /// Output directories are deliberately excluded: they are created by the
  /// build step, so their absence before a run is normal.
  static bool _looksLikeRequiredPath(String key) => const {
        'json-key',
        'export-options-plist',
        'dart-defines-file',
        'release-notes-file',
        'testers-file',
        'groups-file',
        'credential-file',
      }.contains(key);

  /// Whether [value] resolves to an existing file or directory.
  static bool _pathExists(String value) {
    final normalized = path.normalize(value);
    return File(normalized).existsSync() || Directory(normalized).existsSync();
  }
}
