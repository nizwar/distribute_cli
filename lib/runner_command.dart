import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'parsers/config_parser.dart';

import 'command.dart';
import 'logger.dart';
import 'parsers/artifact_report.dart';
import 'parsers/job_arguments.dart';
import 'parsers/notification_config.dart';
import 'parsers/task_arguments.dart';
import 'version.dart';

/// The outcome of a single executed job, used to build the final summary.
class JobResult {
  /// Key of the task the job belongs to.
  final String taskKey;

  /// Human readable job label, used in notifications and the JSON report.
  final String jobLabel;

  /// Operation key of the job, e.g. `android.publish`.
  ///
  /// Shown in the summary so a failed row can be pasted straight back into
  /// `distribute run -o <ref>` to retry just that job.
  final String ref;

  /// Exit code of the last attempt. `0` means success.
  final int exitCode;

  /// Wall clock time spent on the job, including retries.
  final Duration duration;

  /// Number of attempts performed (1 when the job succeeded immediately).
  final int attempts;

  /// Whether the failure was tolerated because of `continue-on-error`.
  final bool ignored;

  /// Binaries produced by this job. Empty for publish jobs.
  final List<Artifact> artifacts;

  /// Creates a job outcome record.
  JobResult({
    required this.taskKey,
    required this.jobLabel,
    required this.ref,
    required this.exitCode,
    required this.duration,
    required this.attempts,
    required this.ignored,
    this.artifacts = const [],
  });

  /// Whether the job completed successfully.
  bool get succeeded => exitCode == 0;

  /// Whether the job failed in a way that must fail the whole run.
  bool get isFatal => !succeeded && !ignored;

  /// Machine readable form used by `distribute run --json`.
  Map<String, dynamic> toJson() => {
        'task': taskKey,
        'job': jobLabel,
        'ref': ref,
        'status': succeeded
            ? 'success'
            : ignored
                ? 'failed-ignored'
                : 'failed',
        'exit-code': exitCode,
        'duration-ms': duration.inMilliseconds,
        'attempts': attempts,
        if (artifacts.isNotEmpty)
          'artifacts': artifacts.map((a) => a.toJson()).toList(),
      };
}

/// A command to execute distribution tasks defined in the configuration file.
///
/// The `RunnerCommand` class is responsible for parsing the configuration file,
/// filtering tasks and jobs based on the provided operation key, and executing
/// the specified build and publish operations. It supports running individual
/// jobs or entire task workflows.
///
/// The command returns the process exit code: `0` when every job succeeded (or
/// failed with `continue-on-error`), `1` otherwise.
class RunnerCommand extends Commander {
  /// The description of the run command shown in help text
  @override
  String get description =>
      "Run the tasks and jobs declared in the configuration.";

  /// The name of the command used in CLI
  @override
  String get name => "run";

  /// Argument parser for the run command with configuration and operation options.
  ///
  /// Available options:
  /// - `--config` or `-c` - Path to the configuration file (defaults to "distribution.yaml")
  /// - `--operation` or `-o` - Key of the operation to run (use "TaskKey.JobKey" for specific jobs)
  /// - `--dry-run` - Resolve and print every command without executing it
  /// - `--fail-fast` - Stop as soon as a task fails
  /// - `--list` - Print the available tasks and jobs, then exit
  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    )
    ..addOption(
      'operation',
      abbr: 'o',
      help: 'Run a single task ("android") or a single job ("android.build").',
      defaultsTo: '',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      defaultsTo: false,
      help: 'Resolve and print every command without executing it.',
    )
    ..addFlag(
      'fail-fast',
      negatable: false,
      defaultsTo: false,
      help: 'Stop the run as soon as a task fails.',
    )
    ..addFlag(
      'list',
      abbr: 'l',
      negatable: false,
      defaultsTo: false,
      help: 'List the available tasks and jobs, then exit.',
    )
    ..addFlag(
      'json',
      negatable: false,
      defaultsTo: false,
      help: 'Print a machine readable run report to stdout. '
          'The human readable log moves to stderr.',
    )
    ..addOption(
      'json-file',
      help: 'Write the machine readable run report to the given path.',
    )
    ..addFlag(
      'no-notify',
      negatable: false,
      defaultsTo: false,
      help: 'Skip the notifications declared in the configuration.',
    );

  /// The operation key used to filter which tasks or jobs to execute.
  ///
  /// Supports the following formats:
  /// - Empty string - Runs all tasks
  /// - "TaskKey" - Runs all jobs in the specified task
  /// - "TaskKey.JobKey" - Runs only the specific job within the task
  String get operationKey => argResults!['operation'] as String;

  /// Whether `--operation` named a single job rather than a whole task.
  bool _explicitJob = false;

  /// Whether the run should only print the resolved commands.
  bool get isDryRun => argResults!['dry-run'] as bool;

  /// Whether the run stops at the first failing task.
  bool get failFast => argResults!['fail-fast'] as bool;

  /// Executes the run command to process distribution tasks.
  ///
  /// This method performs the following operations:
  /// - Parses the configuration file specified by `--config` option
  /// - Filters tasks and jobs based on the `--operation` key
  /// - Executes build and publish operations for each selected job
  /// - Prints a summary and returns a matching exit code
  ///
  /// A job that fails aborts the remaining jobs of its task, because a publish
  /// step must never run on the artifact of a build that did not succeed.
  @override
  Future<int> run() async {
    // Claim stdout for the report before anything is printed, so even a
    // configuration error lands on stderr and leaves stdout parseable.
    if (argResults!['json'] as bool) {
      ColorizeLogger.reserveStdout = true;
      ColorizeLogger.retargetColors();
    }

    final ConfigParser configParser;
    try {
      configParser = await _buildConfigParser();
    } on ConfigException catch (e) {
      logger.logError(e.message);
      return 1;
    }

    if (argResults!['list'] as bool) {
      _printCatalog(configParser);
      return 0;
    }

    JobArguments.dryRun = isDryRun;

    _printBanner(configParser);

    final results = <JobResult>[];
    final stopwatch = Stopwatch()..start();

    for (final task in configParser.tasks) {
      final jobs = _resolveJobs(task);
      if (jobs.isEmpty) {
        logger.logWarning("${task.name} has no job to run, skipping");
        continue;
      }

      logger.logGroup(task.name);
      if (task.description != null) logger.logDetail(task.description!);

      var taskFailed = false;
      await ColorizeLogger.group(() async {
        for (final job in jobs) {
          logger.logEmpty();
          final result = await _runJob(task, job);
          results.add(result);

          if (result.isFatal) {
            taskFailed = true;
            final remaining = jobs.length - jobs.indexOf(job) - 1;
            if (remaining > 0) {
              logger.logWarning(
                "skipped $remaining remaining job(s) after ${job.label} failed",
              );
            }
            break;
          }
        }
      });

      logger.logEmpty();
      if (taskFailed && failFast) {
        logger.logWarning("stopping early (--fail-fast)");
        break;
      }
    }

    stopwatch.stop();
    final summary = _renderSummary(results, stopwatch.elapsed);
    _printSummary(results, stopwatch.elapsed);

    // A run that executed nothing is not a success. Reporting 0 here let a
    // pipeline "pass" while shipping nothing, which is the worst possible way
    // to find out a job was excluded by its task's `workflows`.
    final failed = results.isEmpty || results.any((result) => result.isFatal);

    await _writeJsonReport(results, stopwatch.elapsed, succeeded: !failed);

    if (!(argResults!['no-notify'] as bool) && !isDryRun) {
      await Notifier(logger, configParser.variables).dispatch(
        configParser.notifications,
        succeeded: !failed,
        summary: summary,
      );
    }

    return failed ? 1 : 0;
  }

  /// Prints the one line run header.
  ///
  /// Everything the user needs to identify the run - version, config file, mode
  /// - on a single de-emphasised line, instead of the previous banner rows.
  void _printBanner(ConfigParser configParser) {
    final jobCount =
        configParser.tasks.fold<int>(0, (sum, task) => sum + task.jobs.length);
    final sep = LogSymbols.separator;
    final parts = [
      'distribute $packageVersion',
      _configPath,
      '${configParser.tasks.length} task(s), $jobCount job(s)',
      if (isDryRun) 'dry run',
    ];
    logger.logInfo(ColorizeLogger.dim(parts.join('  $sep  ')));
    logger.logEmpty();
  }

  /// Writes the `--json` run report, if requested.
  ///
  /// `--json` and `--json-file` are independent: a pipeline can stream the
  /// report to a parser and keep a copy on disk in the same run.
  Future<void> _writeJsonReport(
    List<JobResult> results,
    Duration total, {
    required bool succeeded,
  }) async {
    final toStdout = argResults!['json'] as bool;
    final target = argResults!['json-file'] as String?;
    if (!toStdout && (target == null || target.isEmpty)) return;

    final report = {
      'version': packageVersion,
      'config': _configPath,
      'dry-run': isDryRun,
      'succeeded': succeeded,
      'duration-ms': total.inMilliseconds,
      'jobs': results.map((result) => result.toJson()).toList(),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(report);

    if (toStdout) stdout.writeln(encoded);
    if (target == null || target.isEmpty) return;
    if (target == '-') {
      // `--json-file -` reads as "write it to stdout"; silently producing
      // nothing is the one thing it cannot mean.
      if (!toStdout) stdout.writeln(encoded);
      return;
    }

    try {
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded);
      logger.logInfo("Run report written to $target");
    } on FileSystemException catch (e) {
      logger.logWarning(
          "Could not write the run report to $target: ${e.message}");
    }
  }

  /// Runs a single job, honouring its `retry` and `continue-on-error` settings.
  Future<JobResult> _runJob(Task task, Job job) async {
    final kind = job.builder != null ? 'build' : 'publish';
    final ref = job.key == null ? task.key : "${task.key}.${job.key}";

    logger.logStep("${job.name}  ${ColorizeLogger.dim(kind)}");
    if (job.description != null) logger.logDetail(job.description!);

    final stopwatch = Stopwatch()..start();
    var attempts = 0;
    var exitCode = 1;

    while (attempts <= job.retry) {
      attempts++;
      if (attempts > 1) {
        logger.logWarning("retry $attempts/${job.retry + 1}");
      }

      exitCode = await ColorizeLogger.group(
        () => job.builder != null
            ? _runBuilder(job.builder!)
            : _runPublisher(job.publisher!),
      );

      if (exitCode == 0) break;
    }

    stopwatch.stop();

    final artifacts = exitCode == 0 && job.builder != null && !isDryRun
        ? await _collectArtifacts(job.builder!)
        : const <Artifact>[];

    final elapsed = ColorizeLogger.dim(_formatDuration(stopwatch.elapsed));
    await ColorizeLogger.group(() async {
      if (exitCode == 0) {
        logger.logSuccess("done  $elapsed");
        for (final artifact in artifacts) {
          logger.logDetail(
            "${artifact.name}  ${artifact.readableSize}  ${artifact.shortHash}",
          );
        }
      } else if (job.continueOnError) {
        logger.logWarning(
          "$ref failed (exit $exitCode)  $elapsed  "
          "${ColorizeLogger.dim("ignored via continue-on-error")}",
        );
      } else {
        // Naming the ref here keeps the line self-contained, which matters
        // under --quiet where the surrounding context is not printed.
        logger.logError("$ref failed (exit $exitCode)  $elapsed");
        if (!logger.isVerbose) {
          // `--log-file ""` disables file logging, and pointing at a file that
          // is not there is worse than not mentioning one.
          logger.logDetail(
            ColorizeLogger.fileLoggingEnabled
                ? "re-run with --verbose, or see ${ColorizeLogger.logFilePath}"
                : "re-run with --verbose to see the tool's output",
          );
        }
      }
    });

    return JobResult(
      taskKey: task.key,
      jobLabel: job.label,
      ref: ref,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      attempts: attempts,
      ignored: exitCode != 0 && job.continueOnError,
      artifacts: artifacts,
    );
  }

  /// Collects the binaries a builder job wrote to its output directories.
  ///
  /// Failures are swallowed on purpose: the report is a convenience, and an
  /// unreadable output directory must not fail a build that already succeeded.
  Future<List<Artifact>> _collectArtifacts(BuilderJob builder) async {
    final directories = <String>{
      if (builder.android?.output != null) builder.android!.output!,
      if (builder.ios?.output != null) builder.ios!.output!,
    };

    final artifacts = <Artifact>[];
    for (final directory in directories) {
      try {
        artifacts.addAll(await Artifact.fromDirectory(directory));
      } catch (e) {
        logger.logDebug("Could not inspect artifacts in $directory: $e");
      }
    }
    return artifacts;
  }

  /// Renders the summary as plain text, for notifications and the JSON report.
  String _renderSummary(List<JobResult> results, Duration total) {
    final buffer = StringBuffer();
    final failedCount = results.where((result) => result.isFatal).length;
    buffer.writeln(
      "${results.length - failedCount}/${results.length} job(s) succeeded "
      "in ${_formatDuration(total)}",
    );
    for (final result in results) {
      final status = result.succeeded
          ? "OK"
          : result.ignored
              ? "FAILED (ignored)"
              : "FAILED (${result.exitCode})";
      buffer.writeln(
        "[$status] ${result.taskKey} > ${result.jobLabel} "
        "- ${_formatDuration(result.duration)}",
      );
      for (final artifact in result.artifacts) {
        buffer.writeln("    ${artifact.name} - ${artifact.readableSize}");
      }
    }
    return buffer.toString().trimRight();
  }

  /// Runs every platform configured on a builder job.
  ///
  /// Returns `0` only when all platforms succeeded; otherwise the exit code of
  /// the first failing platform, so the caller can report a meaningful status.
  Future<int> _runBuilder(BuilderJob builder) async {
    var failure = 0;

    if (builder.android != null) {
      final result = await _guard(
        () => builder.android!.build(),
        "Android build",
      );
      if (result != 0 && failure == 0) failure = result;
    }

    if (builder.ios != null) {
      final result = await _guard(() => builder.ios!.build(), "iOS build");
      if (result != 0 && failure == 0) failure = result;
    }

    return failure;
  }

  /// Runs every publisher configured on a publish job.
  ///
  /// All publishers are attempted even when one fails, because they target
  /// independent channels; the first non-zero exit code is returned.
  Future<int> _runPublisher(PublisherJob publisher) async {
    var failure = 0;

    Future<void> runOne(String label, Future<int> Function() action) async {
      final result = await _guard(action, "$label publish");
      if (result != 0 && failure == 0) failure = result;
    }

    if (publisher.fastlane != null) {
      await runOne("Fastlane", publisher.fastlane!.publish);
    }
    if (publisher.firebase != null) {
      await runOne("Firebase", publisher.firebase!.publish);
    }
    if (publisher.xcrun != null) {
      await runOne("Xcrun", publisher.xcrun!.publish);
    }
    if (publisher.github != null) {
      await runOne("Github", publisher.github!.publish);
    }

    return failure;
  }

  /// Runs [action], converting an unexpected exception into an exit code.
  Future<int> _guard(Future<int> Function() action, String label) async {
    try {
      return await action();
    } catch (error, stack) {
      logger.logEmpty();
      logger.logError("$label failed with error: $error");
      logger.logDebug(stack.toString());
      return 1;
    }
  }

  /// Returns the jobs of [task] in the order they should be executed.
  ///
  /// When the task declares `workflows`, that list defines both the selection
  /// and the ordering. Otherwise the declaration order is used. Filtering by a
  /// specific job key has already happened in [_buildConfigParser].
  List<Job> _resolveJobs(Task task) {
    final workflows = task.workflows;
    if (_explicitJob || workflows == null || workflows.isEmpty) {
      return List<Job>.from(task.jobs);
    }

    final ordered = <Job>[];
    for (final workflow in workflows) {
      final job = task.jobs.where((job) => job.key == workflow).firstOrNull;
      // Missing workflow keys are rejected during parsing; a null here means the
      // job was filtered out by --operation, which is expected.
      if (job != null) ordered.add(job);
    }
    return ordered;
  }

  /// Prints the tasks and jobs available in the configuration.
  void _printCatalog(ConfigParser configParser) {
    logger.logInfo(ColorizeLogger.dim(_configPath));
    for (final task in configParser.tasks) {
      logger.logEmpty();
      logger.logGroup("${task.name}  ${ColorizeLogger.dim(task.key)}");
      if (task.description != null) {
        logger.logDetail(task.description!);
      }
      final refWidth = task.jobs
          .map((job) => "${task.key}.${job.key}".length)
          .fold<int>(0, (a, b) => a > b ? a : b);

      final workflows = task.workflows;
      for (final job in task.jobs) {
        final type = job.builder != null ? "build" : "publish";
        final ref = "${task.key}.${job.key}".padRight(refWidth);
        // A job missing from a non-empty `workflows` is skipped by a whole-task
        // run. It is still reachable with `-o task.job`, but listing it with no
        // mark made it look like part of the pipeline when it is not.
        final excluded = workflows != null &&
            workflows.isNotEmpty &&
            !workflows.contains(job.key);
        logger.logDetail(
          "$ref  ${type.padRight(7)}  ${job.name}"
          "${excluded ? "  ${ColorizeLogger.dim('not in workflows')}" : ''}",
        );
      }
    }
  }

  /// Prints a per-job summary table and the total wall clock time.
  ///
  /// The job column is padded to a common width so the durations line up, which
  /// is what makes a slow step obvious at a glance.
  void _printSummary(List<JobResult> results, Duration total) {
    if (results.isEmpty) {
      logger.logError("no job was executed");
      logger.logDetail(
        "every selected task was empty or excluded by its `workflows`; "
        "run `distribute run --list` to see what is reachable",
      );
      return;
    }

    final width = results
        .map((result) => result.ref.length)
        .reduce((a, b) => a > b ? a : b);

    for (final result in results) {
      final trailing = <String>[
        _formatDuration(result.duration),
        if (result.attempts > 1) "${result.attempts} attempts",
        if (result.isFatal) "exit ${result.exitCode}",
        if (result.ignored) "ignored",
      ].join("  ");
      final line =
          "${result.ref.padRight(width)}  ${ColorizeLogger.dim(trailing)}";

      if (result.isFatal) {
        logger.logError(line);
      } else if (result.ignored) {
        logger.logWarning(line);
      } else {
        logger.logSuccess(line);
      }
    }

    final failedCount = results.where((result) => result.isFatal).length;
    final passed = results.length - failedCount;
    final sep = LogSymbols.separator;

    logger.logEmpty();
    final tally = "$passed/${results.length} job(s) succeeded  "
        "$sep  ${_formatDuration(total)}";
    if (failedCount > 0) {
      logger.logError(tally);
    } else {
      logger.logSuccess(tally);
    }
  }

  /// Formats a duration as `1m 12s` or `840ms` for short operations.
  static String _formatDuration(Duration duration) {
    if (duration.inSeconds < 1) return "${duration.inMilliseconds}ms";
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return minutes > 0 ? "${minutes}m ${seconds}s" : "${seconds}s";
  }

  /// The configuration path, preferring the command option over the global one.
  String get _configPath => super.configPath;

  /// Loads the configuration and applies the `--operation` filter.
  ///
  /// Throws a [ConfigException] when the file is invalid or when the requested
  /// operation key does not match any task or job.
  Future<ConfigParser> _buildConfigParser() async {
    final configParser = await ConfigParser.distributeYaml(
      _configPath,
      globalResults,
    );

    if (operationKey.isEmpty) return configParser;

    final parts = operationKey.split('.');
    final taskKey = parts.first;
    final jobKey = parts.length > 1 ? parts[1] : null;

    configParser.tasks.removeWhere((task) => task.key != taskKey);
    if (configParser.tasks.isEmpty) {
      throw ConfigException(
        "No task found with the key '$taskKey'. "
        "Run `distribute run --list` to see the available keys.",
      );
    }

    if (jobKey != null) {
      for (final task in configParser.tasks) {
        task.jobs.removeWhere((job) => job.key != jobKey);
      }
      if (configParser.tasks.every((task) => task.jobs.isEmpty)) {
        throw ConfigException(
          "No job found for the operation key '$operationKey'. "
          "Run `distribute run --list` to see the available keys.",
        );
      }
      // Asking for one job by name overrides the task's `workflows` ordering.
      // Without this a job that exists but is not listed in `workflows` was
      // filtered out again below, and the run reported success having done
      // nothing at all.
      _explicitJob = true;
    }

    return configParser;
  }

  /// Kept for backwards compatibility with external callers.
  ///
  /// Returns `null` instead of throwing when the configuration cannot be used.
  Future<ConfigParser?> configParserBuilder() async {
    try {
      return await _buildConfigParser();
    } on ConfigException catch (e) {
      logger.logError(e.message);
      return null;
    }
  }
}
