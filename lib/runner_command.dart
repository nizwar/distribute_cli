import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'clean_service.dart';
import 'files.dart';
import 'hooks_runner.dart';
import 'parsers/config_parser.dart';
import 'parsers/duration.dart';

import 'command.dart';
import 'logger.dart';
import 'parsers/artifact_report.dart';
import 'parsers/job_arguments.dart';
import 'parsers/notification_config.dart';
import 'parsers/run_settings.dart';
import 'parsers/run_state.dart';
import 'parsers/task_arguments.dart';
import 'parsers/variables.dart';
import 'parsers/version_config.dart';
import 'version.dart';

class _JobTimedOut {
  const _JobTimedOut();
}

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

  /// Whether this result was restored from a previous successful run.
  final bool resumed;

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
    this.resumed = false,
  });

  factory JobResult.fromJson(Map<String, dynamic> json, {bool resumed = true}) {
    final status = json['status']?.toString();
    return JobResult(
      taskKey: json['task'].toString(),
      jobLabel: json['job'].toString(),
      ref: json['ref'].toString(),
      exitCode: (json['exit-code'] as num?)?.toInt() ?? 0,
      duration: Duration(
        milliseconds: (json['duration-ms'] as num?)?.toInt() ?? 0,
      ),
      attempts: (json['attempts'] as num?)?.toInt() ?? 1,
      ignored: status == 'failed-ignored',
      artifacts: [
        for (final raw in (json['artifacts'] as List?) ?? const [])
          Artifact.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
      resumed: resumed,
    );
  }

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
        if (resumed) 'resumed': true,
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
    ..addOption(
      'jobs',
      abbr: 'j',
      help: 'Run up to this many tasks at once. '
          '1 keeps the current sequential behaviour; "auto" uses the core count.',
    )
    ..addOption(
      'gap',
      help: 'Minimum gap between task starts (for example 15s or 2m).',
    )
    ..addOption(
      'on-error',
      allowed: const ['continue', 'stop'],
      help: 'Continue independent tasks or stop starting new ones.',
    )
    ..addFlag(
      'resume',
      negatable: false,
      help: 'Resume the last compatible run from its state file.',
    )
    ..addFlag(
      'retry-failed',
      negatable: false,
      help: 'Resume and run failed/interrupted jobs while skipping successes.',
    )
    ..addOption(
      'state-file',
      defaultsTo: '.distribute/last-run.json',
      help: 'Path used to persist resumable run state.',
    )
    ..addFlag(
      'force-resume',
      negatable: false,
      help: 'Resume even when config, operation, or Git revision changed.',
    )
    ..addFlag(
      'status',
      negatable: false,
      help: 'Print the saved run status without executing jobs.',
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

  RunStateStore? _stateStore;
  ErrorPolicy _errorPolicy = ErrorPolicy.continueRun;
  Duration _taskGap = Duration.zero;
  bool _interrupted = false;
  bool _isResuming = false;
  bool _lifecycleFailed = false;
  ResolvedVersion? _resolvedVersion;
  StreamSubscription<ProcessSignal>? _signalSubscription;
  Future<void> _startGate = Future<void>.value();
  DateTime? _lastTaskStart;
  final Set<String> _invalidatedTasks = <String>{};
  final Completer<void> _interruptSignal = Completer<void>();
  final Completer<void> _stopSignal = Completer<void>();

  /// Whether the run should only print the resolved commands.
  bool get isDryRun => argResults!['dry-run'] as bool;

  /// Whether the run stops at the first failing task.
  bool get failFast =>
      argResults!['fail-fast'] as bool || _errorPolicy == ErrorPolicy.stop;

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

    if (argResults!['status'] as bool) return _printSavedStatus();

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

    try {
      _configureRunControl(configParser);
      await _prepareState(configParser);
      await _prepareVersion(configParser);
    } on Object catch (error) {
      logger.logError(error.toString());
      return 1;
    }

    if (!isDryRun) {
      _signalSubscription = ProcessSignal.sigint.watch().listen((_) async {
        if (_interrupted) return;
        _interrupted = true;
        if (!_interruptSignal.isCompleted) _interruptSignal.complete();
        logger.logWarning('interrupt received; saving state and stopping work');
        await _stateStore?.flush();
        await JobArguments.terminateAllProcesses();
      });
    }

    try {
      _printBanner(configParser);

      final results = <JobResult>[];
      final stopwatch = Stopwatch()..start();

      final hooksRunner = HooksRunner(
        logger,
        configParser.variables,
        dryRun: isDryRun,
      );
      final runPre = await hooksRunner.run(
        configParser.hooks.pre,
        phase: 'pre',
        scopeSucceeded: true,
        context: _hookContext(status: 'running'),
      );
      _lifecycleFailed = _hookFailed(runPre);

      if (!_lifecycleFailed && !_interrupted) {
        final concurrency = _concurrency(configParser);
        if (concurrency > 1) {
          results.addAll(await _runParallel(configParser, concurrency));
        } else {
          results.addAll(await _runSequential(configParser));
        }
      }

      final jobsSucceeded =
          results.isNotEmpty && !results.any((result) => result.isFatal);
      final runPost = await hooksRunner.run(
        configParser.hooks.post,
        phase: 'post',
        scopeSucceeded: jobsSucceeded && !_lifecycleFailed && !_interrupted,
        context: _hookContext(
          status: jobsSucceeded ? 'success' : 'failure',
          results: results,
        ),
        variableContext: _hookArtifactVariables(results: results),
      );
      if (_hookFailed(runPost)) _lifecycleFailed = true;

      var failed = results.isEmpty ||
          results.any((result) => result.isFatal) ||
          _lifecycleFailed ||
          _interrupted;
      if (!isDryRun && configParser.clean?.shouldRun(!failed) == true) {
        final cleanFailure = await _autoClean(configParser);
        if (cleanFailure != 0) {
          _lifecycleFailed = true;
          failed = true;
        }
      }

      stopwatch.stop();
      final summary = _renderSummary(results, stopwatch.elapsed);
      _printSummary(results, stopwatch.elapsed);

      await _writeJsonReport(results, stopwatch.elapsed, succeeded: !failed);

      if (!(argResults!['no-notify'] as bool) && !isDryRun) {
        await Notifier(logger, configParser.variables).dispatch(
          configParser.notifications,
          succeeded: !failed,
          summary: summary,
        );
      }

      return _interrupted
          ? 130
          : failed
              ? 1
              : 0;
    } on Object catch (error, stack) {
      logger.logError('Run aborted: $error');
      logger.logDebug(stack.toString());
      return _interrupted ? 130 : 1;
    } finally {
      try {
        await _stateStore?.flush();
      } on Object catch (error) {
        logger.logWarning('Could not save run state: $error');
      }
      try {
        await _signalSubscription?.cancel();
      } on Object catch (error) {
        logger.logDebug('Could not close signal listener: $error');
      }
    }
  }

  void _configureRunControl(ConfigParser config) {
    final rawPolicy = argResults!['on-error'] as String?;
    _errorPolicy = rawPolicy == null
        ? config.errorPolicy
        : ErrorPolicy.parse(rawPolicy, label: '--on-error');
    final rawGap = argResults!['gap'] as String?;
    _taskGap = rawGap == null || rawGap.trim().isEmpty
        ? config.parallelSettings.gap
        : parseDuration(rawGap, label: '--gap');
  }

  Future<void> _prepareState(ConfigParser config) async {
    if (isDryRun) return;
    final file = File(argResults!['state-file'] as String);
    final hash = RunStateStore.fingerprint(File(_configPath), operationKey);
    final resume =
        argResults!['resume'] as bool || argResults!['retry-failed'] as bool;
    _isResuming = resume;
    if (!resume) {
      _stateStore = await RunStateStore.create(
        file: file,
        configHash: hash,
        operation: operationKey,
      );
      return;
    }

    final store = await RunStateStore.load(file);
    if (store.state.configHash != hash &&
        !(argResults!['force-resume'] as bool)) {
      throw StateError(
        'The configuration, selected operation, or Git revision changed '
        'since the saved run. '
        'Use --force-resume only after verifying the difference.',
      );
    }
    _stateStore = store;
  }

  Future<void> _prepareVersion(ConfigParser config) async {
    final versionConfig = config.versionConfig;
    if (versionConfig == null) return;
    final saved = _stateStore?.state.version;
    final resuming =
        argResults!['resume'] as bool || argResults!['retry-failed'] as bool;
    _resolvedVersion = resuming && saved != null
        ? saved
        : await VersionResolver(config.variables).resolve(
            versionConfig,
            writeBack: !isDryRun,
          );
    config.variables.addVariables({
      'VERSION_NAME': _resolvedVersion!.name,
      'VERSION_CODE': _resolvedVersion!.code,
    });
    for (final task in config.tasks) {
      for (final job in task.jobs) {
        final builder = job.builder;
        if (builder?.android != null) {
          builder!.android!.buildName ??= _resolvedVersion!.name;
          builder.android!.buildNumber ??= _resolvedVersion!.code;
        }
        if (builder?.ios != null) {
          builder!.ios!.buildName ??= _resolvedVersion!.name;
          builder.ios!.buildNumber ??= _resolvedVersion!.code;
        }
      }
    }
    await _stateStore?.setVersion(_resolvedVersion!);
  }

  Future<int> _autoClean(ConfigParser config) async {
    final clean = config.clean!;
    final service = CleanService(
      logger,
      dryRun: false,
      protectedPaths: {
        ...config.protectedCredentialFiles(),
        if (_stateStore != null) _stateStore!.file.path,
      },
    );
    var failure = 0;
    if (clean.flutter) failure = await service.flutterClean();
    if (clean.outputs) {
      final outputFailure = await service.outputs(
        config.builderOutputDirectories(),
      );
      if (failure == 0) failure = outputFailure;
    }
    return failure;
  }

  int _printSavedStatus() {
    final file = File(argResults!['state-file'] as String);
    if (!file.existsSync()) {
      logger.logError('No saved run state at ${file.path}');
      return 1;
    }
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map;
      logger.logInfo('Saved run: ${json['updated-at']}');
      final jobs = json['jobs'] as Map? ?? const {};
      for (final entry in jobs.entries) {
        final value = entry.value as Map;
        logger.logDetail('${entry.key}  ${value['status']}');
      }
      return 0;
    } on Object catch (error) {
      logger.logError('Could not read ${file.path}: $error');
      return 1;
    }
  }

  bool _hookFailed(List<HookResult> results) =>
      results.any((result) => !result.succeeded && !result.ignored);

  Map<String, String> _hookContext({
    required String status,
    Task? task,
    Job? job,
    JobResult? result,
    List<JobResult> results = const [],
  }) {
    final reference = result?.ref ??
        (task == null
            ? ''
            : job == null
                ? task.key
                : '${task.key}.${job.key}');
    return {
      'DISTRIBUTE_TASK': task?.key ?? '',
      'DISTRIBUTE_JOB': job?.key ?? '',
      'DISTRIBUTE_REF': reference,
      'DISTRIBUTE_STATUS': status,
      'DISTRIBUTE_EXIT_CODE': result?.exitCode.toString() ?? '',
      'DISTRIBUTE_DURATION_MS':
          result?.duration.inMilliseconds.toString() ?? '',
      'DISTRIBUTE_ARTIFACTS': jsonEncode([
        ...results.expand((item) => item.artifacts),
        ...?result?.artifacts,
      ].map((artifact) => artifact.filePath).toList()),
    };
  }

  Map<String, String> _hookArtifactVariables({
    JobResult? result,
    List<JobResult> results = const [],
  }) {
    final paths = <String>[
      ...results.expand(
        (item) => item.artifacts.map((artifact) => artifact.filePath),
      ),
      ...?result?.artifacts.map((artifact) => artifact.filePath),
    ];
    final artifact = paths.isEmpty ? '' : paths.first;
    return {
      'ARTIFACT': artifact,
      'ARTIFACT_DIR': artifact.isEmpty ? '' : File(artifact).parent.path,
    };
  }

  /// How many tasks may run at once.
  ///
  /// `-j` wins over the configuration, which wins over one-at-a-time. Anything
  /// above the number of tasks is pointless, so it is clamped.
  int _concurrency(ConfigParser config) {
    final raw = (argResults!['jobs'] as String?)?.trim();
    final requested = raw == null || raw.isEmpty
        ? config.parallel
        : (raw.toLowerCase() == 'auto'
            ? Platform.numberOfProcessors
            : int.tryParse(raw));

    if (requested == null) {
      logger.logWarning("--jobs must be a number or \"auto\", got '$raw'");
      return 1;
    }
    if (requested <= 1) return 1;
    return requested < config.tasks.length ? requested : config.tasks.length;
  }

  Future<void> _waitForTaskStart() async {
    final previous = _startGate;
    final release = Completer<void>();
    _startGate = release.future;
    await previous;
    try {
      final last = _lastTaskStart;
      if (last != null && _taskGap > Duration.zero) {
        final remaining = _taskGap - DateTime.now().difference(last);
        if (remaining > Duration.zero) {
          await Future.any<void>([
            Future<void>.delayed(remaining),
            _interruptSignal.future,
            _stopSignal.future,
          ]);
        }
      }
      _lastTaskStart = DateTime.now();
    } finally {
      release.complete();
    }
  }

  Future<void> _waitOrInterrupt(Duration duration) => Future.any<void>([
        Future<void>.delayed(duration),
        _interruptSignal.future,
      ]);

  /// Runs every task one after another. Jobs inside a task are always ordered.
  Future<List<JobResult>> _runSequential(ConfigParser config) async {
    final results = <JobResult>[];

    for (final task in config.tasks) {
      if (_interrupted) break;
      final jobs = _resolveJobs(task);
      if (jobs.isEmpty) {
        logger.logWarning("${task.name} has no job to run, skipping");
        continue;
      }

      await _waitForTaskStart();
      if (_interrupted) break;
      final outcome = await _runTask(task, jobs, config.variables);
      results.addAll(outcome.results);

      logger.logEmpty();
      if (outcome.failed && failFast) {
        logger.logWarning("stopping early (--fail-fast)");
        break;
      }
    }

    return results;
  }

  /// Runs up to [limit] tasks at once.
  ///
  /// Only whole tasks overlap. The jobs inside one stay strictly ordered,
  /// because that ordering is the point: a publish must never start before the
  /// build it uploads.
  ///
  /// Each task's output is collected and printed as one block when it
  /// finishes. Live interleaving would shred every multi-line tool error, and
  /// the log file already holds everything in true order, timestamped.
  Future<List<JobResult>> _runParallel(ConfigParser config, int limit) async {
    final runnable = <(Task, List<Job>)>[];
    for (final task in config.tasks) {
      final jobs = _resolveJobs(task);
      if (jobs.isEmpty) {
        logger.logWarning("${task.name} has no job to run, skipping");
        continue;
      }
      runnable.add((task, jobs));
    }
    if (runnable.isEmpty) return const [];

    logger.logInfo(
      ColorizeLogger.dim(
        'running ${runnable.length} task(s), up to $limit at once',
      ),
    );

    final results = <JobResult>[];
    final inFlight = <String>{};
    var stopped = false;
    var next = 0;

    Future<void> runOne() async {
      while (true) {
        if (stopped || _interrupted || next >= runnable.length) return;
        await _waitForTaskStart();
        if (stopped || _interrupted || next >= runnable.length) return;
        final (task, jobs) = runnable[next++];

        inFlight.add(task.key);
        final buffer = StringBuffer();
        final outcome = await ColorizeLogger.capture(
          buffer,
          () => _runTask(task, jobs, config.variables),
        );
        inFlight.remove(task.key);

        // Printed whole, under the spinner rather than through it.
        Spinner.active?.erase();
        stdout.write(buffer.toString());
        stdout.writeln();
        Spinner.active?.paint();

        results.addAll(outcome.results);
        if (outcome.failed && failFast) {
          stopped = true;
          if (!_stopSignal.isCompleted) _stopSignal.complete();
          Spinner.active?.erase();
          logger.logWarning(
            'stopping early (--fail-fast); '
            'tasks already running will finish',
          );
          Spinner.active?.paint();
        }
      }
    }

    await Spinner.run(
      'running tasks',
      () => Future.wait(List.generate(limit, (_) => runOne())),
      describe: () =>
          inFlight.isEmpty ? 'finishing' : 'running ${inFlight.join(", ")}',
    );

    return results;
  }

  /// Runs one task's jobs in order, stopping at the first fatal failure.
  Future<({List<JobResult> results, bool failed})> _runTask(
    Task task,
    List<Job> jobs,
    Variables variables,
  ) async {
    final results = <JobResult>[];

    logger.logGroup(task.name);
    if (task.description != null) logger.logDetail(task.description!);

    var failed = false;
    await ColorizeLogger.group(() async {
      final hooksRunner = HooksRunner(logger, variables, dryRun: isDryRun);
      final pre = await hooksRunner.run(
        task.hooks.pre,
        phase: 'pre',
        scopeSucceeded: true,
        context: _hookContext(status: 'running', task: task),
      );
      failed = _hookFailed(pre);

      if (!failed) {
        for (final job in jobs) {
          if (_interrupted) {
            failed = true;
            break;
          }
          logger.logEmpty();
          final result = await _runJob(task, job, variables);
          results.add(result);

          if (result.isFatal) {
            failed = true;
            final remaining = jobs.length - jobs.indexOf(job) - 1;
            if (remaining > 0) {
              logger.logWarning(
                "skipped $remaining remaining job(s) after ${job.label} failed",
              );
            }
            break;
          }
        }
      }

      final post = await hooksRunner.run(
        task.hooks.post,
        phase: 'post',
        scopeSucceeded: !failed,
        context: _hookContext(
          status: failed ? 'failure' : 'success',
          task: task,
          results: results,
        ),
        variableContext: _hookArtifactVariables(results: results),
      );
      if (_hookFailed(post)) failed = true;
      if (failed && (_hookFailed(pre) || _hookFailed(post))) {
        _lifecycleFailed = true;
      }
    });

    return (results: results, failed: failed);
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
      if (_resolvedVersion != null)
        'resolved-version': _resolvedVersion!.toJson(),
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
  Future<JobResult> _runJob(Task task, Job job, Variables variables) async {
    final kind = job.builder != null ? 'build' : 'publish';
    final ref = job.key == null ? task.key : "${task.key}.${job.key}";

    final saved = _stateStore?.job(ref);
    if (_isResuming &&
        !_invalidatedTasks.contains(task.key) &&
        saved != null &&
        await _canResume(job, saved)) {
      final resumed = JobResult.fromJson(saved);
      logger.logStep(
        "${job.name}  ${ColorizeLogger.dim('skipped (resumed)')}",
      );
      return resumed;
    }
    if (_isResuming) _invalidatedTasks.add(task.key);

    logger.logStep("${job.name}  ${ColorizeLogger.dim(kind)}");
    if (job.description != null) logger.logDetail(job.description!);

    await _stateStore?.mark(ref, {
      'task': task.key,
      'job': job.label,
      'ref': ref,
      'status': 'running',
      'started-at': DateTime.now().toUtc().toIso8601String(),
    });

    final stopwatch = Stopwatch()..start();
    var attempts = 0;
    var exitCode = 1;
    final hooksRunner = HooksRunner(logger, variables, dryRun: isDryRun);

    final pre = await hooksRunner.run(
      job.hooks.pre,
      phase: 'pre',
      scopeSucceeded: true,
      context: _hookContext(status: 'running', task: task, job: job),
    );
    if (_hookFailed(pre)) exitCode = pre.last.exitCode;

    while (!_hookFailed(pre) && attempts <= job.retry && !_interrupted) {
      attempts++;
      if (attempts > 1) {
        logger.logWarning("retry $attempts/${job.retry + 1}");
      }

      exitCode = await _runAttempt(job);

      if (exitCode == 0) break;
      if (attempts <= job.retry && job.retryDelay > Duration.zero) {
        logger.logInfo(
          'waiting ${formatDurationValue(job.retryDelay)} before retry',
        );
        await _waitOrInterrupt(job.retryDelay);
      }
    }

    var artifacts = exitCode == 0 && job.builder != null && !isDryRun
        ? await _collectArtifacts(job.builder!)
        : const <Artifact>[];

    var provisional = JobResult(
      taskKey: task.key,
      jobLabel: job.label,
      ref: ref,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      attempts: attempts,
      ignored: exitCode != 0 && job.continueOnError,
      artifacts: artifacts,
    );
    final post = await hooksRunner.run(
      job.hooks.post,
      phase: 'post',
      scopeSucceeded: exitCode == 0,
      context: _hookContext(
        status: exitCode == 0 ? 'success' : 'failure',
        task: task,
        job: job,
        result: provisional,
      ),
      variableContext: _hookArtifactVariables(result: provisional),
    );
    if (_hookFailed(post) && exitCode == 0) {
      exitCode = post.last.exitCode;
      artifacts = provisional.artifacts;
    }

    stopwatch.stop();

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

    final result = JobResult(
      taskKey: task.key,
      jobLabel: job.label,
      ref: ref,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      attempts: attempts,
      ignored: exitCode != 0 && job.continueOnError,
      artifacts: artifacts,
    );
    await _stateStore?.mark(ref, result.toJson());
    return result;
  }

  Future<int> _runAttempt(Job job) => JobArguments.withProcessScope(() async {
        final action = ColorizeLogger.group(
          () => job.builder != null
              ? _runBuilder(job.builder!)
              : _runPublisher(job.publisher!),
        );
        final timeout = job.timeout;
        if (timeout == null) return action;

        final completed = await Future.any<Object>([
          action,
          Future<Object>.delayed(timeout, () => const _JobTimedOut()),
        ]);
        if (completed is int) return completed;

        logger.logError(
          'job timed out after ${formatDurationValue(timeout)}',
        );
        await JobArguments.terminateScopedProcesses();
        try {
          await action.timeout(const Duration(seconds: 5));
        } on Object {
          // The timeout result is authoritative; the child was already killed.
        }
        return 124;
      });

  Future<bool> _canResume(Job job, Map<String, dynamic> saved) async {
    if (saved['status'] != 'success') return false;
    if (job.builder == null) return true;
    final rawArtifacts = saved['artifacts'];
    if (rawArtifacts is! List || rawArtifacts.isEmpty) return false;
    for (final raw in rawArtifacts) {
      final expected = Artifact.fromJson(Map<String, dynamic>.from(raw as Map));
      final file = File(expected.filePath);
      if (!await file.exists() || await file.length() != expected.sizeInBytes) {
        return false;
      }
      final actual = await Artifact.fromFile(file);
      if (actual.sha256Hash != expected.sha256Hash) return false;
    }
    return true;
  }

  /// Collects the binaries a builder job wrote to its output directories.
  ///
  /// Failures are swallowed on purpose: the report is a convenience, and an
  /// unreadable output directory must not fail a build that already succeeded.
  Future<List<Artifact>> _collectArtifacts(BuilderJob builder) async {
    final directories = <String>{
      if (builder.android != null)
        builder.android!.output ?? Files.androidDistributionOutputDir.path,
      if (builder.ios != null)
        builder.ios!.output ?? Files.iosDistributionOutputDir.path,
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
    if (publisher.huawei != null) {
      await runOne("Huawei", publisher.huawei!.publish);
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
        if (result.resumed) "resumed",
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
    if (parts.length > 2 || parts.any((part) => part.trim().isEmpty)) {
      throw ConfigException(
        "Invalid operation key '$operationKey'. Expected 'task' or "
        "'task.job'.",
      );
    }
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
