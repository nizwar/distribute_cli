import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/create_command.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/prompt.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Drives the `create` wizards by feeding [Prompt] a scripted set of answers.
void main() {
  late Directory sandbox;
  late File config;
  late CommandRunner<int> runner;
  final original = Prompt.readLine;

  const seed = '''
name: demo
description: demo
tasks:
  - name: Android release
    key: android
    workflows: []
    jobs:
      - name: Build
        key: build
        description: d
        package_name: com.example.app
        builder:
          android:
            binary-type: aab
  - name: iOS release
    key: ios
    workflows: []
    jobs: []
''';

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_wizard');
    config = File('${sandbox.path}${Platform.pathSeparator}distribution.yaml')
      ..writeAsStringSync(seed);

    ColorizeLogger.logFilePath = '';
    ColorizeLogger.useColors = false;
    // The wizard refuses to run below `normal`, because it would be asking
    // questions it is not allowed to print.
    ColorizeLogger.verbosity = LogVerbosity.normal;
    ColorizeLogger.indentLevel = 0;

    runner = CommandRunner<int>('distribute', 'test')
      ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
      ..addCommand(CreateCommand());
  });

  tearDown(() {
    Prompt.readLine = original;
    sandbox.deleteSync(recursive: true);
  });

  /// Feeds [answers] to the wizard, then end-of-input.
  void answering(List<String> answers) {
    final queue = List<String>.from(answers);
    Prompt.readLine = () => queue.isEmpty ? null : queue.removeAt(0);
  }

  /// The answer to the builder platform question, which is only asked where
  /// there is more than one platform to choose from — iOS needs Xcode.
  final pickAndroid = Platform.isMacOS ? ['1'] : <String>[];

  /// firebase and github in the publisher menu, which lists xcrun only on macOS.
  final firebaseAndGithub = Platform.isMacOS ? '1,4' : '1,3';

  Map<String, dynamic> readConfig() =>
      Map<String, dynamic>.from(loadYaml(config.readAsStringSync()) as Map);

  List<dynamic> tasksOf(Map<String, dynamic> parsed) =>
      parsed['tasks'] as List<dynamic>;

  Map<dynamic, dynamic> taskNamed(Map<String, dynamic> parsed, String key) =>
      tasksOf(parsed).firstWhere((task) => task['key'] == key) as Map;

  group('slugify', () {
    test('turns a name into a usable key', () {
      expect(CreatorCommand.slugify('Android release'), 'android_release');
      expect(CreatorCommand.slugify('Build & Ship!'), 'build_ship');
      expect(CreatorCommand.slugify('  spaced  out  '), 'spaced_out');
    });

    test('strips the characters that would break a task.job reference', () {
      // A dot would make `distribute run -o a.b.c` ambiguous.
      expect(CreatorCommand.slugify('web.staging'), 'web_staging');
      expect(CreatorCommand.slugify('v1.0 build'), 'v1_0_build');
    });

    test('leaves nothing behind for a name with no usable characters', () {
      expect(CreatorCommand.slugify('!!!'), '');
    });
  });

  group('validateKey', () {
    test('accepts a plain key', () {
      expect(
        CreatorCommand.validateKey('android', taken: {}, what: 'task'),
        isNull,
      );
    });

    test('rejects a key that is already used', () {
      expect(
        CreatorCommand.validateKey('android', taken: {'android'}, what: 'task'),
        contains('already used'),
      );
    });

    test('rejects characters that would break a reference', () {
      for (final bad in ['a.b', 'a b', 'a/b', '', 'a:b']) {
        expect(
          CreatorCommand.validateKey(bad, taken: {}, what: 'job'),
          isNotNull,
          reason: '"$bad" should be rejected',
        );
      }
    });
  });

  group('create task --wizard', () {
    test('writes the task and derives the key from the name', () async {
      answering(['Web release', '', 'Ship the web build', 'y']);
      final code =
          await runner.run(['create', 'task', '-c', config.path, '-w']);

      expect(code, 0);
      final task = taskNamed(readConfig(), 'web_release');
      expect(task['name'], 'Web release');
      expect(task['description'], 'Ship the web build');
    });

    test('re-asks instead of failing when the key is taken', () {
      // The old wizard asked every question, then exited 1 on a duplicate key.
      answering(['Another', 'android', 'free', '', 'y']);
      return runner.run(['create', 'task', '-c', config.path, '-w']).then((_) {
        expect(taskNamed(readConfig(), 'free')['name'], 'Another');
      });
    });

    test('declining leaves the file untouched', () async {
      final before = config.readAsStringSync();
      answering(['Web', '', '', 'n']);
      final code =
          await runner.run(['create', 'task', '-c', config.path, '-w']);

      expect(code, 0, reason: 'declining is not a failure');
      expect(config.readAsStringSync(), before);
    });

    test('aborts cleanly when the answers run out', () {
      answering(['Web']);
      expect(
        runner.run(['create', 'task', '-c', config.path, '-w']),
        throwsA(isA<PromptAbortedException>()),
      );
    });
  });

  group('create job builder --wizard', () {
    test('picks the task from the list and writes the job', () async {
      answering([
        '2',
        'Build iOS',
        'build',
        'd',
        'com.example.app',
        ...pickAndroid,
        'y'
      ]);
      final code = await runner.run(
        ['create', 'job', 'builder', '-c', config.path, '-w'],
      );

      expect(code, 0);
      final jobs = taskNamed(readConfig(), 'ios')['jobs'] as List;
      expect(jobs, hasLength(1));
      expect(jobs.single['key'], 'build');
      expect(jobs.single['name'], 'Build iOS');
      expect(jobs.single['builder']['android'], isNotNull);
    });

    test('a job key only has to be unique within its own task', () async {
      // `build` already exists under `android`; the same key under `ios` is
      // fine, because references are `task.job`.
      answering(
          ['2', 'Build', 'build', '', 'com.example.app', ...pickAndroid, 'y']);
      await runner.run(['create', 'job', 'builder', '-c', config.path, '-w']);

      expect((taskNamed(readConfig(), 'ios')['jobs'] as List), hasLength(1));
    });

    test('re-asks when the key collides inside the chosen task', () async {
      answering([
        '1', 'Second', 'build', 'build2', '', 'com.example.app', //
        ...pickAndroid, 'y',
      ]);
      await runner.run(['create', 'job', 'builder', '-c', config.path, '-w']);

      final jobs = taskNamed(readConfig(), 'android')['jobs'] as List;
      expect(jobs.map((job) => job['key']), containsAll(['build', 'build2']));
    });

    test('declining leaves the file untouched', () async {
      final before = config.readAsStringSync();
      answering(
          ['1', 'Nope', 'nope', '', 'com.example.app', ...pickAndroid, 'n']);
      final code = await runner.run(
        ['create', 'job', 'builder', '-c', config.path, '-w'],
      );

      expect(code, 0);
      expect(config.readAsStringSync(), before);
    });

    test('refuses when there is no task to attach the job to', () async {
      config.writeAsStringSync('name: a\ndescription: b\ntasks: []\n');
      answering([]);
      final code = await runner.run(
        ['create', 'job', 'builder', '-c', config.path, '-w'],
      );

      expect(code, 1, reason: 'it must not ask questions it cannot use');
    });
  });

  group('create job publisher --wizard', () {
    test('writes every selected tool', () async {
      answering(
          ['1', 'Ship', 'ship', '', 'com.example.app', firebaseAndGithub, 'y']);
      final code = await runner.run(
        ['create', 'job', 'publisher', '-c', config.path, '-w'],
      );

      expect(code, 0);
      final job = (taskNamed(readConfig(), 'android')['jobs'] as List)
          .firstWhere((job) => job['key'] == 'ship');
      expect(job['publisher']['firebase'], isNotNull);
      expect(job['publisher']['github'], isNotNull);
      expect(job['publisher']['fastlane'], isNull);
    });

    test('the tool question aborts at end of input', () async {
      // Regression: this question read stdin directly, so it neither validated
      // the answer nor stopped when the input ran out.
      answering(['1', 'Ship', 'ship', '', 'com.example.app']);
      expect(
        runner.run(['create', 'job', 'publisher', '-c', config.path, '-w']),
        throwsA(isA<PromptAbortedException>()),
      );
    });
  });

  group('comments', () {
    const commented = '''
# Release pipeline for Acme
name: demo
description: demo

tasks:
  # the internal track
  - name: Android release
    key: android
    workflows: []
    jobs: []
''';

    test('the wizard warns before the confirm, not after it', () async {
      // Re-encoding drops every comment. The user has to see that while
      // deciding, not discover it in a diff afterwards.
      config.writeAsStringSync(commented);
      final log = File('${sandbox.path}${Platform.pathSeparator}w.log');
      ColorizeLogger.logFilePath = log.path;
      ColorizeLogger.verbosity = LogVerbosity.normal;

      answering(['Web', '', '', 'n']);
      final code =
          await runner.run(['create', 'task', '-c', config.path, '-w']);

      ColorizeLogger.logFilePath = '';
      ColorizeLogger.verbosity = LogVerbosity.normal;

      expect(code, 0);
      expect(config.readAsStringSync(), commented, reason: 'declined');

      // The run was declined, so nothing after the confirm ever executed.
      // The warning still being here proves it was printed before it.
      expect(log.readAsStringSync(), contains('drop its comments'));
    });

    test('accepting still writes, without the comments', () async {
      config.writeAsStringSync(commented);
      answering(['Web', '', '', 'y']);
      await runner.run(['create', 'task', '-c', config.path, '-w']);

      final after = config.readAsStringSync();
      expect(after, isNot(contains('# Release pipeline')));
      expect(taskNamed(readConfig(), 'web')['name'], 'Web');
    });

    test('a config without comments is written without a warning', () async {
      final log = File('${sandbox.path}${Platform.pathSeparator}q.log');
      ColorizeLogger.logFilePath = log.path;
      ColorizeLogger.verbosity = LogVerbosity.normal;

      answering(['Web', '', '', 'y']);
      await runner.run(['create', 'task', '-c', config.path, '-w']);

      ColorizeLogger.logFilePath = '';
      ColorizeLogger.verbosity = LogVerbosity.normal;

      expect(log.readAsStringSync(), isNot(contains('drop its comments')));
    });

    test('the scripted path warns but does not stop', () async {
      config.writeAsStringSync(commented);
      final log = File('${sandbox.path}${Platform.pathSeparator}s.log');
      ColorizeLogger.logFilePath = log.path;
      ColorizeLogger.verbosity = LogVerbosity.normal;

      answering([]);
      final code = await runner.run(
        ['create', 'task', '-c', config.path, '-n', 'Web', '-k', 'web'],
      );

      ColorizeLogger.logFilePath = '';
      ColorizeLogger.verbosity = LogVerbosity.normal;

      expect(code, 0, reason: 'automation must not be blocked on a question');
      expect(log.readAsStringSync(), contains('drop its comments'));
      expect(taskNamed(readConfig(), 'web')['name'], 'Web');
    });
  });

  group('inputs that used to break the wizard', () {
    test('a range whose bound overflows int64 re-asks instead of crashing',
        () async {
      // `int.parse` on the range bounds threw FormatException straight out of
      // the wizard, discarding every answer already typed.
      answering([
        '1', 'B', 'b', '', 'com.example.app', //
        if (Platform.isMacOS) ...['1-99999999999999999999', '1'],
        'y',
      ]);
      final code = await runner.run(
        ['create', 'job', 'builder', '-c', config.path, '-w'],
      );

      expect(code, 0);
      expect(
        (taskNamed(readConfig(), 'android')['jobs'] as List)
            .map((job) => job['key']),
        contains('b'),
      );
    });

    test('a reversed overflowing range is refused the same way', () async {
      answering([
        '1', 'B', 'b', '', 'com.example.app', //
        if (Platform.isMacOS) ...['99999999999999999999-1', '1'],
        'y',
      ]);
      expect(
        await runner.run(['create', 'job', 'builder', '-c', config.path, '-w']),
        0,
      );
    });

    test('a non-mapping config is refused, not overwritten', () async {
      // Pointing --config at the wrong file used to replace its contents with
      // just `tasks:`, silently.
      final notes = File('${sandbox.path}${Platform.pathSeparator}notes.yaml')
        ..writeAsStringSync('- one\n- two\n- three\n');

      answering(['T', 'tk', '', 'y']);
      final code = await runner.run(['create', 'task', '-c', notes.path, '-w']);

      expect(code, 1);
      expect(notes.readAsStringSync(), '- one\n- two\n- three\n');
    });

    test('a scalar config is refused too', () async {
      final notes = File('${sandbox.path}${Platform.pathSeparator}s.yaml')
        ..writeAsStringSync('just a string\n');

      answering([]);
      final code = await runner.run(
        ['create', 'task', '-c', notes.path, '-n', 'T', '-k', 'tk'],
      );

      expect(code, 1);
      expect(notes.readAsStringSync(), 'just a string\n');
    });

    test(
        'the job lands in the task that was pointed at, not the first '
        'one sharing its key', () async {
      config.writeAsStringSync('''
name: demo
description: demo
tasks:
  - name: First
    key: dup
    workflows: []
    jobs: []
  - name: Second
    key: dup
    workflows: []
    jobs: []
''');

      answering(
          ['2', 'New', 'new', '', 'com.example.app', ...pickAndroid, 'y']);
      await runner.run(['create', 'job', 'builder', '-c', config.path, '-w']);

      final tasks = tasksOf(readConfig());
      expect((tasks[0]['jobs'] as List), isEmpty,
          reason: 'First was not picked');
      expect((tasks[1]['jobs'] as List), hasLength(1));
    });

    test('the wizard refuses to run under --quiet', () async {
      // It would hide the questions while still blocking on the answers.
      ColorizeLogger.verbosity = LogVerbosity.quiet;
      answering(['Web', '', '', 'y']);

      expect(
        runner.run(['create', 'task', '-c', config.path, '-w']),
        throwsA(isA<PromptAbortedException>()),
      );
    });
  });

  group('the option form is checked as strictly as the wizard', () {
    test('a task key that cannot be referenced is rejected', () async {
      answering([]);
      final code = await runner.run(
        ['create', 'task', '-c', config.path, '-n', 'T', '-k', 'my.key'],
      );

      expect(code, 1);
      expect(tasksOf(readConfig()), hasLength(2), reason: 'nothing was added');
    });

    test('a job key that cannot be referenced is rejected', () async {
      answering([]);
      final code = await runner.run([
        'create', 'job', 'builder', '-c', config.path, //
        '-t', 'ios', '-n', 'B', '-k', 'a b', '-P', 'android',
      ]);

      expect(code, 1);
    });

    test('-P may be repeated', () async {
      answering([]);
      final code = await runner.run([
        'create', 'job', 'builder', '-c', config.path, //
        '-t', 'ios', '-n', 'B', '-k', 'b',
        '-P', 'android', if (Platform.isMacOS) ...['-P', 'ios'],
      ]);

      expect(code, 0);
      final job = (taskNamed(readConfig(), 'ios')['jobs'] as List).single;
      expect(job['builder']['android'], isNotNull);
      if (Platform.isMacOS) expect(job['builder']['ios'], isNotNull);
    });

    test('-T may be repeated', () async {
      answering([]);
      final code = await runner.run([
        'create', 'job', 'publisher', '-c', config.path, //
        '-t', 'ios', '-n', 'P', '-k', 'p',
        '-T', 'firebase', '-T', 'github',
      ]);

      expect(code, 0);
      final job = (taskNamed(readConfig(), 'ios')['jobs'] as List).single;
      expect(job['publisher']['firebase'], isNotNull);
      expect(job['publisher']['github'], isNotNull);
      expect(job['publisher']['fastlane'], isNull);
    });

    test('an unset description is null in both paths', () async {
      answering([]);
      await runner.run(
        ['create', 'task', '-c', config.path, '-n', 'A', '-k', 'a'],
      );
      answering(['B', 'b', '', 'y']);
      await runner.run(['create', 'task', '-c', config.path, '-w']);

      expect(taskNamed(readConfig(), 'a')['description'], isNull);
      expect(taskNamed(readConfig(), 'b')['description'], isNull);
    });
  });

  group('non-wizard path still works', () {
    test('options create a task without asking anything', () async {
      answering([]);
      final code = await runner.run(
        ['create', 'task', '-c', config.path, '-n', 'Web', '-k', 'web'],
      );

      expect(code, 0);
      expect(taskNamed(readConfig(), 'web')['name'], 'Web');
    });

    test('a builder job needs a platform', () async {
      answering([]);
      final code = await runner.run([
        'create', 'job', 'builder', '-c', config.path, //
        '-t', 'ios', '-n', 'B', '-k', 'b',
      ]);

      expect(code, 1);
    });
  });
}
