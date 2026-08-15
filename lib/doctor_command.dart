import 'dart:io';

import 'package:args/args.dart';

import 'command.dart';
import 'files.dart';
import 'logger.dart';
import 'parsers/build_info.dart';
import 'parsers/builtin_variables.dart';
import 'parsers/compress_files.dart';
import 'parsers/config_parser.dart';
import 'version.dart';

/// Result of a single environment probe.
class _Check {
  final String label;
  final bool ok;
  final String detail;
  final String? hint;
  final bool optional;

  const _Check(
    this.label, {
    required this.ok,
    required this.detail,
    this.hint,
    this.optional = false,
  });
}

/// Reports whether the machine is ready to build and publish.
///
/// `distribute doctor` answers "why did this work on my laptop but not in CI?"
/// in one command: it probes every external tool the CLI shells out to, checks
/// the configuration, and prints the values the built-in variables expand to.
///
/// Missing *optional* tools are reported as warnings, because a project that
/// only publishes to Firebase has no reason to install Fastlane. The command
/// only fails when something required is broken.
class DoctorCommand extends Commander {
  @override
  String get description =>
      "Check that the tools, configuration and credentials are ready to use.";

  @override
  String get name => "doctor";

  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    );

  @override
  Future<int> run() async {
    logger.logInfo(
      ColorizeLogger.dim("distribute $packageVersion  environment check"),
    );
    logger.logEmpty();

    final checks = <_Check>[
      await _checkTool(
        'Flutter',
        'flutter',
        ['--version'],
        hint: 'Install from https://flutter.dev/docs/get-started/install',
      ),
      await _checkTool(
        'Git',
        'git',
        ['--version'],
        hint: 'Required for the GIT_* built-in variables.',
        optional: true,
      ),
      await _checkTool(
        'Fastlane',
        'fastlane',
        ['--version'],
        hint: 'Only needed for the fastlane publisher: gem install fastlane',
        optional: true,
      ),
      await _checkTool(
        'Firebase CLI',
        'firebase',
        ['--version'],
        hint: 'Only needed for the firebase publisher: '
            'npm i -g firebase-tools',
        optional: true,
      ),
      if (Platform.isMacOS)
        await _checkTool(
          'Xcode (xcrun altool)',
          'xcrun',
          ['altool', '--help'],
          hint: 'Only needed for the xcrun publisher.',
          optional: true,
        ),
      await _checkCompression(),
      _checkProject(),
      _checkFile(
        'Google Play service account',
        Files.fastlaneJson.path,
        hint: 'Only needed for the fastlane publisher. '
            'Pass it with `distribute init -g <path>`.',
        optional: true,
      ),
      await _checkConfig(),
    ];

    // Pad the labels so the details line up into a readable second column.
    final width = checks
        .map((check) => check.label.length)
        .reduce((a, b) => a > b ? a : b);

    for (final check in checks) {
      final line =
          '${check.label.padRight(width)}  ${ColorizeLogger.dim(check.detail)}';
      if (check.ok) {
        logger.logSuccess(line);
      } else if (check.optional) {
        logger.logWarning(line);
      } else {
        logger.logError(line);
      }
      if (!check.ok && check.hint != null) logger.logDetail(check.hint!);
    }

    await _printBuiltins();

    final failures = checks.where((c) => !c.ok && !c.optional).length;
    final warnings = checks.where((c) => !c.ok && c.optional).length;

    logger.logEmpty();
    if (failures > 0) {
      logger.logError(
        "$failures required check(s) failed  "
        "${ColorizeLogger.dim("$warnings optional skipped")}",
      );
      return 1;
    }
    logger.logSuccess(
      "all required checks passed"
      "${warnings > 0 ? "  ${ColorizeLogger.dim("$warnings optional tool(s) missing")}" : ""}",
    );
    return 0;
  }

  /// Probes an executable by running it with a harmless argument.
  Future<_Check> _checkTool(
    String label,
    String executable,
    List<String> arguments, {
    String? hint,
    bool optional = false,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        // `runInShell: true` means a missing binary comes back as the shell's
        // own 127 rather than a ProcessException, so reporting it as "found
        // but exited" sent the reader looking for a broken install instead of
        // a missing one.
        final missing = result.exitCode == 127;
        return _Check(
          label,
          ok: false,
          detail: missing
              ? 'not found in PATH'
              : 'found but exited with code ${result.exitCode}',
          hint: hint,
          optional: optional,
        );
      }
      final firstLine = result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => 'installed');
      return _Check(label, ok: true, detail: firstLine, optional: optional);
    } on ProcessException {
      return _Check(
        label,
        ok: false,
        detail: 'not found in PATH',
        hint: hint,
        optional: optional,
      );
    }
  }

  Future<_Check> _checkCompression() async {
    try {
      final available = await CompressFiles.checkTools();
      return _Check(
        'Archiver (zip)',
        ok: available,
        detail: available ? 'available' : 'not found',
        hint: 'Needed to package Android native debug symbols.',
        optional: true,
      );
    } on UnsupportedError catch (e) {
      return _Check(
        'Archiver (zip)',
        ok: false,
        detail: e.message ?? 'unsupported platform',
        optional: true,
      );
    }
  }

  _Check _checkProject() {
    if (!File('pubspec.yaml').existsSync()) {
      return const _Check(
        'Flutter project',
        ok: false,
        detail: 'no pubspec.yaml in the current directory',
        hint: 'Run distribute from the root of your Flutter project.',
      );
    }

    final detected = <String>[
      if (BuildInfo.androidPackageName != null)
        'android=${BuildInfo.androidPackageName}',
      if (BuildInfo.iosBundleId != null) 'ios=${BuildInfo.iosBundleId}',
    ];

    return _Check(
      'Flutter project',
      ok: true,
      detail: detected.isEmpty
          ? 'pubspec.yaml found (no platform identifier detected)'
          : detected.join(', '),
    );
  }

  _Check _checkFile(
    String label,
    String filePath, {
    String? hint,
    bool optional = false,
  }) {
    final exists = File(filePath).existsSync();
    return _Check(
      label,
      ok: exists,
      detail: exists ? filePath : 'missing at $filePath',
      hint: hint,
      optional: optional,
    );
  }

  Future<_Check> _checkConfig() async {
    final configPath = super.configPath;
    if (!File(configPath).existsSync()) {
      return _Check(
        'Configuration',
        ok: false,
        detail: '$configPath not found',
        hint: 'Run `distribute init` to create it.',
      );
    }

    try {
      final config =
          await ConfigParser.distributeYaml(configPath, globalResults);
      final jobs =
          config.tasks.fold<int>(0, (sum, task) => sum + task.jobs.length);
      return _Check(
        'Configuration',
        ok: true,
        detail: '$configPath (${config.tasks.length} task(s), $jobs job(s))',
      );
    } on ConfigException catch (e) {
      return _Check(
        'Configuration',
        ok: false,
        detail: e.message,
        hint: 'Run `distribute validate` for the full report.',
      );
    }
  }

  /// Shows what the built-in placeholders currently expand to.
  Future<void> _printBuiltins() async {
    final resolved = await BuiltinVariables.resolveAll();
    logger.logEmpty();
    logger.logHeading('built-in variables');

    if (resolved.isEmpty) {
      logger.logWarning('none could be resolved here');
      return;
    }

    final width = resolved.keys
        .map((name) => name.length)
        .reduce((a, b) => a > b ? a : b);
    for (final entry in resolved.entries) {
      logger.logNote(
        '${entry.key.padRight(width)}  ${ColorizeLogger.bold(entry.value)}',
      );
    }

    final unresolved = BuiltinVariables.names.difference(resolved.keys.toSet());
    if (unresolved.isNotEmpty) {
      logger.logNote('unavailable here: ${unresolved.join(', ')}');
    }
  }
}
