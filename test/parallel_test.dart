import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/runner_command.dart';
import 'package:test/test.dart';

void main() {
  group('log capture', () {
    setUp(() {
      ColorizeLogger.logFilePath = '';
      ColorizeLogger.useColors = false;
      ColorizeLogger.verbosity = LogVerbosity.normal;
      ColorizeLogger.indentLevel = 0;
      ColorizeLogger.reserveStdout = false;
    });

    test('a captured task writes to its own buffer', () async {
      final buffer = StringBuffer();

      await ColorizeLogger.capture(buffer, () async {
        ColorizeLogger().logNote('inside');
      });

      expect(buffer.toString(), contains('inside'));
    });

    test('two captured tasks never share a buffer', () async {
      // The whole point: interleaved output would be unreadable, so each task
      // collects its own and prints it whole.
      final left = StringBuffer();
      final right = StringBuffer();

      await Future.wait([
        ColorizeLogger.capture(left, () async {
          for (var i = 0; i < 20; i++) {
            ColorizeLogger().logNote('left $i');
            await Future<void>.delayed(Duration.zero);
          }
        }),
        ColorizeLogger.capture(right, () async {
          for (var i = 0; i < 20; i++) {
            ColorizeLogger().logNote('right $i');
            await Future<void>.delayed(Duration.zero);
          }
        }),
      ]);

      expect(left.toString(), isNot(contains('right')));
      expect(right.toString(), isNot(contains('left')));
      expect('left'.allMatches(left.toString()).length, 20);
      expect('right'.allMatches(right.toString()).length, 20);
    });

    test('indentation is per task, not shared', () async {
      // A shared counter would be incremented by one task while another was
      // writing, and every line would come out at the wrong depth.
      final left = StringBuffer();
      final right = StringBuffer();

      await Future.wait([
        ColorizeLogger.capture(left, () async {
          await ColorizeLogger.group(() async {
            await ColorizeLogger.group(() async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              ColorizeLogger().logNote('deep');
            });
          });
        }),
        ColorizeLogger.capture(right, () async {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          ColorizeLogger().logNote('shallow');
        }),
      ]);

      final deep =
          left.toString().split('\n').firstWhere((l) => l.contains('deep'));
      final shallow =
          right.toString().split('\n').firstWhere((l) => l.contains('shallow'));

      expect(deep.indexOf('deep'), greaterThan(shallow.indexOf('shallow')));
    });

    test('capture restores the outer depth afterwards', () async {
      ColorizeLogger.indentLevel = 3;

      await ColorizeLogger.capture(StringBuffer(), () async {
        await ColorizeLogger.group(() async {});
      });

      expect(ColorizeLogger.indentLevel, 3);
    });

    test('a spinner does not draw inside a captured task', () async {
      final buffer = StringBuffer();
      Spinner.isTerminal = () => true;
      final spinnerOutput = StringBuffer();
      Spinner.sink = () => spinnerOutput;

      await ColorizeLogger.capture(buffer, () async {
        await Spinner.run('working', () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      });

      Spinner.resetOutput();
      expect(spinnerOutput.toString(), isEmpty);
      expect(buffer.toString(), isEmpty);
    });
  });

  group('running tasks in parallel', () {
    late Directory sandbox;
    late File config;
    late CommandRunner<int> runner;

    const two = '''
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
            binary-type: apk
  - name: iOS
    key: ios
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
      sandbox = Directory.systemTemp.createTempSync('distribute_parallel');
      config = File('${sandbox.path}${Platform.pathSeparator}distribution.yaml')
        ..writeAsStringSync(two);

      ColorizeLogger.logFilePath = '';
      ColorizeLogger.useColors = false;
      ColorizeLogger.verbosity = LogVerbosity.silent;
      ColorizeLogger.indentLevel = 0;
      ColorizeLogger.reserveStdout = false;

      runner = CommandRunner<int>('distribute', 'test')
        ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
        ..addCommand(RunnerCommand());
    });

    tearDown(() {
      ColorizeLogger.reserveStdout = false;
      sandbox.deleteSync(recursive: true);
    });

    Future<Map<String, dynamic>> run(List<String> extra) async {
      final report = '${sandbox.path}${Platform.pathSeparator}r.json';
      final code = await runner.run([
        'run', '-c', config.path, '--dry-run', '--no-notify', //
        '--json-file', report, ...extra,
      ]);
      expect(code, 0);
      return jsonDecode(File(report).readAsStringSync())
          as Map<String, dynamic>;
    }

    test('every job still runs and is reported', () async {
      final report = await run(['-j', '2']);

      final refs = (report['jobs'] as List).map((j) => j['ref']).toSet();
      expect(refs, {'android.build', 'ios.build'});
      expect(report['succeeded'], isTrue);
    });

    test('the result matches a sequential run', () async {
      final parallel = await run(['-j', '2']);
      final sequential = await run([]);

      List<String> refs(Map<String, dynamic> r) =>
          ((r['jobs'] as List).map((j) => j['ref'] as String).toList())..sort();

      expect(refs(parallel), refs(sequential));
      expect(parallel['succeeded'], sequential['succeeded']);
    });

    test('-j 1 is the sequential path', () async {
      final report = await run(['-j', '1']);
      expect((report['jobs'] as List), hasLength(2));
    });

    test('parallel: in the configuration is honoured', () async {
      config.writeAsStringSync('parallel: 2\n$two');
      final report = await run([]);
      expect((report['jobs'] as List), hasLength(2));
    });

    test('an unusable -j is refused rather than guessed at', () async {
      // It falls back to sequential and says so, instead of silently running
      // everything at once.
      final report = await run(['-j', 'nonsense']);
      expect((report['jobs'] as List), hasLength(2));
    });

    test('parallel: with a bad value is a configuration error', () async {
      config.writeAsStringSync('parallel: -3\n$two');
      final code = await runner.run(
        ['run', '-c', config.path, '--dry-run', '--no-notify'],
      );
      expect(code, 1);
    });
  });
}
