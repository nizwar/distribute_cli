import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/clean_service.dart';
import 'package:distribute_cli/hooks_runner.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/config_parser.dart';
import 'package:distribute_cli/parsers/duration.dart';
import 'package:distribute_cli/parsers/hooks.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:distribute_cli/parsers/run_state.dart';
import 'package:distribute_cli/parsers/version_config.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:distribute_cli/runner_command.dart';
import 'package:test/test.dart';

void main() {
  group('duration parser', () {
    test('supports milliseconds, seconds, minutes, hours, and bare seconds',
        () {
      expect(parseDuration('500ms', label: 'x').inMilliseconds, 500);
      expect(parseDuration('1.5s', label: 'x').inMilliseconds, 1500);
      expect(parseDuration('2m', label: 'x').inSeconds, 120);
      expect(parseDuration('1h', label: 'x').inMinutes, 60);
      expect(parseDuration(7, label: 'x').inSeconds, 7);
    });

    test('rejects malformed and forbidden zero durations', () {
      expect(() => parseDuration('later', label: 'x'), throwsArgumentError);
      expect(
        () => parseDuration('0s', label: 'x', allowZero: false),
        throwsArgumentError,
      );
      expect(
        () => parseDuration(
          const Duration(seconds: -1),
          label: 'x',
        ),
        throwsArgumentError,
      );
    });
  });

  group('run settings config', () {
    late Directory sandbox;
    late File config;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('distribute_run_control');
      config = File('${sandbox.path}/distribution.yaml');
    });

    tearDown(() => sandbox.deleteSync(recursive: true));

    test('parses mapping parallel settings, hooks, version, clean, and timeout',
        () async {
      config.writeAsStringSync('''
name: demo
description: demo
parallel:
  tasks: auto
  gap: 250ms
on-error: stop
pre: echo root
version:
  code: timestamp
clean:
  on: success
  flutter: false
  outputs: true
tasks:
  - name: Android
    key: android
    pre: echo task
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        retry: 2
        retry-delay: 3s
        timeout: 20m
        post:
          - command: echo
            arguments: [done]
            on: always
            timeout: 2m
        builder:
          android:
            binary-type: aab
''');
      final parsed = await ConfigParser.distributeYaml(config.path, null);

      expect(parsed.parallelSettings.isAuto, isTrue);
      expect(parsed.parallelSettings.gap.inMilliseconds, 250);
      expect(parsed.errorPolicy.name, 'stop');
      expect(parsed.hooks.pre.single.command, 'echo root');
      expect(parsed.versionConfig?.codeSource, VersionCodeSource.timestamp);
      expect(parsed.clean?.flutter, isFalse);
      expect(parsed.tasks.single.hooks.pre.single.command, 'echo task');
      final job = parsed.tasks.single.jobs.single;
      expect(job.retry, 2);
      expect(job.retryDelay.inSeconds, 3);
      expect(job.timeout?.inMinutes, 20);
      expect(job.hooks.post.single.arguments, ['done']);
      final serialized = job.toJson();
      expect(serialized['retry-delay'], '3s');
      expect(serialized['timeout'], '20m');
      expect(
        (serialized['post'] as List).single,
        containsPair('on', 'always'),
      );
      expect(
        (serialized['post'] as List).single,
        containsPair('timeout', '2m'),
      );
    });

    test('legacy scalar parallel values stay supported', () async {
      config.writeAsStringSync('''
name: demo
description: demo
parallel: 3
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder:
          android:
            binary-type: aab
''');
      final parsed = await ConfigParser.distributeYaml(config.path, null);
      expect(parsed.parallel, 3);
    });

    test('rejects operation keys with empty or extra path segments', () async {
      config.writeAsStringSync('''
name: demo
description: demo
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder:
          android: {binary-type: apk}
''');
      ColorizeLogger.verbosity = LogVerbosity.silent;
      ColorizeLogger.logFilePath = '';
      final runner = CommandRunner<int>('distribute', 'test')
        ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
        ..addCommand(RunnerCommand());

      expect(
        await runner.run([
          'run',
          '-c',
          config.path,
          '-o',
          'android.build.extra',
          '--dry-run',
        ]),
        1,
      );
      expect(
        await runner.run([
          'run',
          '-c',
          config.path,
          '-o',
          'android.',
          '--dry-run',
        ]),
        1,
      );
    });
  });

  group('parallel start gap', () {
    test('delays starts globally even when jobs are dry-run', () async {
      final sandbox =
          Directory.systemTemp.createTempSync('distribute_parallel_gap');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final config = File('${sandbox.path}/distribution.yaml')
        ..writeAsStringSync('''
name: demo
description: demo
parallel:
  tasks: 2
  gap: 80ms
tasks:
  - name: One
    key: one
    jobs:
      - name: Build
        key: build
        package_name: com.example.one
        builder:
          android: {binary-type: apk}
  - name: Two
    key: two
    jobs:
      - name: Build
        key: build
        package_name: com.example.two
        builder:
          android: {binary-type: aab}
''');
      ColorizeLogger.verbosity = LogVerbosity.silent;
      ColorizeLogger.logFilePath = '';
      final runner = CommandRunner<int>('distribute', 'test')
        ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
        ..addCommand(RunnerCommand());
      final stopwatch = Stopwatch()..start();
      final code = await runner.run([
        'run',
        '-c',
        config.path,
        '--dry-run',
        '--no-notify',
      ]);
      stopwatch.stop();

      expect(code, 0);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(65));
    });

    test('stop-on-error releases workers waiting on a long start gap',
        () async {
      final sandbox =
          Directory.systemTemp.createTempSync('distribute_parallel_stop');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final config = File('${sandbox.path}/distribution.yaml')
        ..writeAsStringSync('''
name: demo
description: demo
parallel:
  tasks: 2
  gap: 5s
on-error: stop
tasks:
  - name: One
    key: one
    pre:
      command: sh
      arguments: [-c, "exit 7"]
    jobs:
      - name: Build
        key: build
        package_name: com.example.one
        builder:
          android: {binary-type: apk}
  - name: Two
    key: two
    pre:
      command: sh
      arguments: [-c, "exit 7"]
    jobs:
      - name: Build
        key: build
        package_name: com.example.two
        builder:
          android: {binary-type: aab}
''');
      ColorizeLogger.verbosity = LogVerbosity.silent;
      ColorizeLogger.logFilePath = '';
      final runner = CommandRunner<int>('distribute', 'test')
        ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
        ..addCommand(RunnerCommand());
      final stopwatch = Stopwatch()..start();
      final code = await runner.run([
        'run',
        '-c',
        config.path,
        '--state-file',
        '${sandbox.path}/state.json',
        '--no-notify',
      ]);
      stopwatch.stop();

      expect(code, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('run state', () {
    test('round-trips atomically with resolved version and jobs', () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_state');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final stateFile = File('${sandbox.path}/state.json');
      final store = await RunStateStore.create(
        file: stateFile,
        configHash: 'abc',
        operation: 'android',
      );
      await store.setVersion(
        const ResolvedVersion(name: '1.2.3', code: '42'),
      );
      await store.mark('android.build', {
        'task': 'android',
        'job': 'Build',
        'ref': 'android.build',
        'status': 'success',
        'exit-code': 0,
        'duration-ms': 12,
        'attempts': 1,
      });

      final restored = await RunStateStore.load(stateFile);
      expect(restored.state.version?.code, '42');
      expect(restored.job('android.build')?['status'], 'success');
      expect(jsonDecode(stateFile.readAsStringSync()), isA<Map>());
      expect(File('${stateFile.path}.tmp').existsSync(), isFalse);
    });

    test('serializes concurrent parallel updates without corrupting state',
        () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_state');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final stateFile = File('${sandbox.path}/state.json');
      final store = await RunStateStore.create(
        file: stateFile,
        configHash: 'abc',
        operation: '',
      );

      await Future.wait([
        for (var index = 0; index < 40; index++)
          store.mark('task.job$index', {
            'task': 'task',
            'job': 'job$index',
            'ref': 'task.job$index',
            'status': 'success',
            'exit-code': 0,
          }),
      ]);

      final restored = await RunStateStore.load(stateFile);
      expect(restored.state.jobs, hasLength(40));
      expect(File('${stateFile.path}.tmp').existsSync(), isFalse);
    });

    test('rejects malformed job entries with a descriptive format error',
        () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_state');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final stateFile = File('${sandbox.path}/state.json')
        ..writeAsStringSync(jsonEncode({
          'schema': 1,
          'config-hash': 'abc',
          'operation': '',
          'started-at': DateTime.now().toIso8601String(),
          'updated-at': DateTime.now().toIso8601String(),
          'jobs': {'broken': 7},
        }));

      await expectLater(
        RunStateStore.load(stateFile),
        throwsA(isA<FormatException>()),
      );
    });

    test('fingerprint changes after a committed source revision', () {
      final sandbox = Directory.systemTemp.createTempSync('distribute_state');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      expect(
        Process.runSync('git', ['init'], workingDirectory: sandbox.path)
            .exitCode,
        0,
      );
      final config = File('${sandbox.path}/distribution.yaml')
        ..writeAsStringSync('name: demo\n');
      File('${sandbox.path}/source.txt').writeAsStringSync('first');
      Process.runSync('git', ['add', '.'], workingDirectory: sandbox.path);
      expect(
        Process.runSync(
          'git',
          [
            '-c',
            'user.name=Test',
            '-c',
            'user.email=test@example.com',
            'commit',
            '-m',
            'first',
          ],
          workingDirectory: sandbox.path,
        ).exitCode,
        0,
      );
      final first = RunStateStore.fingerprint(config, 'android');

      File('${sandbox.path}/source.txt').writeAsStringSync('second');
      Process.runSync('git', ['add', '.'], workingDirectory: sandbox.path);
      expect(
        Process.runSync(
          'git',
          [
            '-c',
            'user.name=Test',
            '-c',
            'user.email=test@example.com',
            'commit',
            '-m',
            'second',
          ],
          workingDirectory: sandbox.path,
        ).exitCode,
        0,
      );

      expect(RunStateStore.fingerprint(config, 'android'), isNot(first));
    });
  });

  group('hooks', () {
    test('receives context and supports a variable working directory',
        () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_hooks');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final runner = HooksRunner(
        ColorizeLogger(),
        Variables({'HOOK_DIR': sandbox.path}, null),
        dryRun: false,
      );
      final results = await runner.run(
        const [
          HookStep(
            command: 'sh',
            arguments: ['-c', r'printf "$DISTRIBUTE_REF" > context.txt'],
            workingDirectory: r'${{HOOK_DIR}}',
          ),
        ],
        phase: 'post',
        scopeSucceeded: true,
        context: const {'DISTRIBUTE_REF': 'android.build'},
      );

      expect(results.single.exitCode, 0);
      expect(
        File('${sandbox.path}/context.txt').readAsStringSync(),
        'android.build',
      );
    });

    test('resolves isolated artifact aliases for post hooks', () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_hooks');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final runner = HooksRunner(
        ColorizeLogger(),
        Variables(<String, dynamic>{}, null),
        dryRun: false,
      );
      final artifact = '${sandbox.path}/output/app.aab';
      final results = await runner.run(
        const [
          HookStep(
            command: 'sh',
            arguments: [
              '-c',
              r'printf "%s|%s" "$1" "$2" > "$3"',
              'hook',
              r'${{ARTIFACT}}',
              r'${{ARTIFACT_DIR}}',
              r'${{RESULT_FILE}}',
            ],
          ),
        ],
        phase: 'post',
        scopeSucceeded: true,
        variableContext: {
          'ARTIFACT': artifact,
          'ARTIFACT_DIR': File(artifact).parent.path,
          'RESULT_FILE': '${sandbox.path}/aliases.txt',
        },
      );

      expect(results.single.exitCode, 0);
      expect(
        File('${sandbox.path}/aliases.txt').readAsStringSync(),
        '$artifact|${File(artifact).parent.path}',
      );
    });

    test('terminates a hook that exceeds its timeout', () async {
      final runner = HooksRunner(
        ColorizeLogger(),
        Variables(<String, dynamic>{}, null),
        dryRun: false,
      );
      final stopwatch = Stopwatch()..start();
      final results = await runner.run(
        const [
          HookStep(
            command: 'sh',
            arguments: ['-c', 'sleep 5'],
            timeout: Duration(milliseconds: 50),
          ),
        ],
        phase: 'pre',
        scopeSucceeded: true,
      );
      stopwatch.stop();

      expect(results.single.timedOut, isTrue);
      expect(results.single.exitCode, 124);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('job scope cancels in-process work on timeout', () async {
      var cancelled = false;
      await JobArguments.withProcessScope(() async {
        JobArguments.trackCancellation(() => cancelled = true);
        await JobArguments.terminateScopedProcesses();
      });
      expect(cancelled, isTrue);
    });

    test('a failing cancellation does not block the remaining callbacks',
        () async {
      var secondCancelled = false;
      await JobArguments.withProcessScope(() async {
        JobArguments.trackCancellation(() => throw StateError('broken'));
        JobArguments.trackCancellation(() => secondCancelled = true);
        await JobArguments.terminateScopedProcesses();
      });
      expect(secondCancelled, isTrue);
    });
  });

  group('version resolver', () {
    test('rejects non-positive literal build numbers', () {
      expect(
        () => VersionConfig.parse({'code': 0}),
        throwsArgumentError,
      );
      expect(
        () => VersionConfig.parse({'code': -1}),
        throwsArgumentError,
      );
    });

    test('increments without rewriting when writeBack is disabled', () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_version');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final pubspec = File('${sandbox.path}/pubspec.yaml')
        ..writeAsStringSync('name: demo\nversion: 1.2.3+9\n');
      final resolver = VersionResolver(
        Variables(<String, dynamic>{}, null),
        pubspec: pubspec,
      );
      final resolved = await resolver.resolve(
        const VersionConfig(
          code: 'increment',
          codeSource: VersionCodeSource.increment,
        ),
      );

      expect(resolved.name, '1.2.3');
      expect(resolved.code, '10');
      expect(pubspec.readAsStringSync(), contains('version: 1.2.3+9'));
    });
  });

  group('clean safety', () {
    test('removes an output directory but refuses an ancestor of metadata',
        () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_clean');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final output = Directory('${sandbox.path}/distribution/android/output')
        ..createSync(recursive: true);
      File('${output.path}/app.aab').writeAsStringSync('artifact');
      final metadata =
          Directory('${sandbox.path}/distribution/android/metadata')
            ..createSync(recursive: true);
      File('${metadata.path}/listing.txt').writeAsStringSync('keep');

      final service = CleanService(
        ColorizeLogger(),
        dryRun: false,
        projectRoot: sandbox,
      );
      expect(await service.outputs([output.path]), 0);
      expect(output.existsSync(), isFalse);
      expect(metadata.existsSync(), isTrue);
      expect(await service.outputs(['distribution']), 1);
      expect(metadata.existsSync(), isTrue);
      final metadataChild = Directory('${metadata.path}/generated')
        ..createSync(recursive: true);
      expect(await service.outputs([metadataChild.path]), 1);
      expect(metadataChild.existsSync(), isTrue);
    });

    test('refuses a target reached through a symlinked parent', () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_clean');
      final outside = Directory.systemTemp.createTempSync('distribute_victim');
      addTearDown(() {
        if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      final victim = Directory('${outside.path}/output')
        ..createSync(recursive: true);
      File('${victim.path}/app.aab').writeAsStringSync('keep');
      Link('${sandbox.path}/linked').createSync(outside.path);
      final service = CleanService(
        ColorizeLogger(),
        dryRun: false,
        projectRoot: sandbox,
      );

      expect(await service.outputs(['linked/output']), 1);
      expect(victim.existsSync(), isTrue);
      expect(File('${victim.path}/app.aab').existsSync(), isTrue);
    });

    test('refuses output ancestors containing custom protected files',
        () async {
      final sandbox = Directory.systemTemp.createTempSync('distribute_clean');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final credential = File('${sandbox.path}/generated/private/key.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('secret');
      final state = File('${sandbox.path}/generated/state/run.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      final service = CleanService(
        ColorizeLogger(),
        dryRun: false,
        projectRoot: sandbox,
        protectedPaths: [credential.path, state.path],
      );

      expect(await service.outputs(['generated']), 1);
      expect(credential.existsSync(), isTrue);
      expect(state.existsSync(), isTrue);
    });
  });
}
