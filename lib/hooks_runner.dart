import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logger.dart';
import 'parsers/hooks.dart';
import 'parsers/job_arguments.dart';
import 'parsers/variables.dart';

/// Result of a pre/post command.
class HookResult {
  final String command;
  final int exitCode;
  final Duration duration;
  final bool ignored;
  final bool timedOut;

  const HookResult({
    required this.command,
    required this.exitCode,
    required this.duration,
    this.ignored = false,
    this.timedOut = false,
  });

  bool get succeeded => exitCode == 0;

  Map<String, dynamic> toJson() => {
        'command': command,
        'exit-code': exitCode,
        'duration-ms': duration.inMilliseconds,
        'status': succeeded
            ? 'success'
            : ignored
                ? 'failed-ignored'
                : timedOut
                    ? 'timed-out'
                    : 'failed',
      };
}

/// Executes custom hook commands with the same variable and logging rules as jobs.
class HooksRunner {
  final ColorizeLogger logger;
  final Variables variables;
  final bool dryRun;

  const HooksRunner(this.logger, this.variables, {required this.dryRun});

  Future<List<HookResult>> run(
    List<HookStep> steps, {
    required String phase,
    required bool scopeSucceeded,
    Map<String, String> context = const {},
    Map<String, String> variableContext = const {},
  }) async {
    final results = <HookResult>[];
    for (final step in steps) {
      if (phase == 'post' && !step.on.shouldRun(scopeSucceeded)) continue;
      final result = await _runOne(
        step,
        phase: phase,
        context: context,
        variableContext: variableContext,
      );
      results.add(result);
      if (!result.succeeded && !result.ignored) break;
    }
    return results;
  }

  Future<HookResult> _runOne(
    HookStep step, {
    required String phase,
    required Map<String, String> context,
    required Map<String, String> variableContext,
  }) async {
    // A copy keeps per-job artifact aliases isolated while parallel tasks share
    // the configuration's base variable resolver.
    final hookVariables = Variables(
      {...variables.variables, ...variableContext},
      variables.globalResults,
    );
    final command = await hookVariables.process(step.command);
    final arguments = <String>[
      for (final argument in step.arguments)
        await hookVariables.process(argument),
    ];
    final workingDirectory = step.workingDirectory == null
        ? null
        : await hookVariables.process(step.workingDirectory!);
    final environment = <String, String>{...Platform.environment, ...context};
    for (final entry in step.environment.entries) {
      final value = await hookVariables.process(entry.value);
      environment[entry.key] = value;
      if (RegExp(r'(token|secret|password|api.?key)', caseSensitive: false)
          .hasMatch(entry.key)) {
        ColorizeLogger.registerSecret(value);
      }
    }

    final printable = arguments.isEmpty
        ? command
        : '$command ${arguments.map(_quote).join(' ')}';
    logger.logCommand('hook $phase: $printable');
    if (dryRun) {
      return HookResult(
        command: printable,
        exitCode: 0,
        duration: Duration.zero,
      );
    }

    final stopwatch = Stopwatch()..start();
    final Process process;
    try {
      process = await Process.start(
        command,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: true,
        runInShell: true,
      );
      JobArguments.trackProcess(process);
    } on ProcessException catch (error) {
      stopwatch.stop();
      logger.logError("Unable to start hook '$command': ${error.message}");
      return HookResult(
        command: printable,
        exitCode: 127,
        duration: stopwatch.elapsed,
        ignored: step.continueOnError,
      );
    }

    final drained = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(logger.logDebug),
      process.stderr.transform(utf8.decoder).forEach(logger.logErrorVerbose),
    ]);

    var timedOut = false;
    int exitCode;
    if (step.timeout == null) {
      exitCode = await process.exitCode;
    } else {
      exitCode = await Future.any<int>([
        process.exitCode,
        Future<int>.delayed(step.timeout!, () => -1),
      ]);
      if (exitCode == -1) {
        timedOut = true;
        logger.logError(
          "hook timed out after ${step.timeout!.inMilliseconds}ms: $command",
        );
        process.kill(ProcessSignal.sigterm);
        exitCode = await Future.any<int>([
          process.exitCode,
          Future<int>.delayed(const Duration(seconds: 2), () => -1),
        ]);
        if (exitCode == -1) {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
        exitCode = 124;
      }
    }
    await drained;
    stopwatch.stop();

    final ignored = exitCode != 0 && step.continueOnError;
    if (exitCode == 0) {
      logger.logSuccess('hook $phase completed');
    } else if (ignored) {
      logger.logWarning('hook $phase failed with exit $exitCode (ignored)');
    } else {
      logger.logError('hook $phase failed with exit $exitCode');
    }
    return HookResult(
      command: printable,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
      ignored: ignored,
      timedOut: timedOut,
    );
  }

  static String _quote(String value) =>
      value.contains(' ') ? '"${value.replaceAll('"', '\\"')}"' : value;
}
