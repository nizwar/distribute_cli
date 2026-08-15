import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/runner_command.dart';
import 'package:test/test.dart';

/// Exercises `distribute run` through its real parser and report writer.
///
/// The jobs are dry-run only, so nothing is built or uploaded; what matters
/// here is the shape of the options and where the output lands. Every path is
/// absolute: `Directory.current` is process wide, and `dart test` shares one
/// process across test files, so changing it here would break other suites.
void main() {
  late Directory sandbox;
  late File config;
  late CommandRunner<int> runner;

  const yaml = '''
name: demo
description: demo
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        description: d
        package_name: com.example.app
        builder:
          android:
            binary-type: aab
''';

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_report');
    config = File('${sandbox.path}${Platform.pathSeparator}distribution.yaml')
      ..writeAsStringSync(yaml);

    ColorizeLogger.logFilePath = '';
    ColorizeLogger.useColors = false;
    ColorizeLogger.verbosity = LogVerbosity.silent;
    ColorizeLogger.reserveStdout = false;
    ColorizeLogger.indentLevel = 0;

    runner = CommandRunner<int>('distribute', 'test')
      ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
      ..argParser.addFlag('silent', negatable: false)
      ..addCommand(RunnerCommand());
  });

  tearDown(() {
    ColorizeLogger.reserveStdout = false;
    sandbox.deleteSync(recursive: true);
  });

  String inSandbox(List<String> parts) =>
      [sandbox.path, ...parts].join(Platform.pathSeparator);

  test('--json does not consume the following flag as its value', () {
    // Regression: `--json` took a path, so it swallowed `--silent` — writing
    // the report to a file literally named `--silent` and never silencing the
    // run. Both have to survive parsing on their own.
    final parsed = runner.parse([
      'run',
      '-c',
      config.path,
      '--dry-run',
      '--json',
      '--silent',
    ]);

    expect(parsed['silent'], isTrue);
    expect(parsed.command!['json'], isTrue);
    expect(parsed.command!['json-file'], isNull);
  });

  test('--json reserves stdout for the report', () async {
    await runner.run(['run', '-c', config.path, '--dry-run', '--json']);
    expect(ColorizeLogger.reserveStdout, isTrue,
        reason: 'the human readable log has to move to stderr');
  });

  test('--json-file writes a parseable report', () async {
    final target = inSandbox(['report.json']);
    final code = await runner
        .run(['run', '-c', config.path, '--dry-run', '--json-file', target]);

    expect(code, 0);

    final report = jsonDecode(File(target).readAsStringSync()) as Map;
    expect(report['succeeded'], isTrue);
    expect(report['dry-run'], isTrue);
    expect(report['config'], config.path);

    final jobs = report['jobs'] as List;
    expect(jobs, hasLength(1));
    expect((jobs.single as Map)['ref'], 'android.build');
    expect((jobs.single as Map)['exit-code'], 0);
  });

  test('--json-file leaves stdout alone', () async {
    await runner.run([
      'run',
      '-c',
      config.path,
      '--dry-run',
      '--json-file',
      inSandbox(['report.json']),
    ]);
    expect(ColorizeLogger.reserveStdout, isFalse);
  });

  test('no report is produced when neither option is given', () async {
    await runner.run(['run', '-c', config.path, '--dry-run']);
    expect(
      sandbox.listSync().where((entity) => entity.path.endsWith('.json')),
      isEmpty,
    );
  });

  test('--json-file creates the parent directory', () async {
    final target = inSandbox(['build', 'reports', 'run.json']);
    await runner
        .run(['run', '-c', config.path, '--dry-run', '--json-file', target]);

    expect(File(target).existsSync(), isTrue);
  });
}
