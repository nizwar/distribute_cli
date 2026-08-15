import 'dart:io';

import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/config_parser.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_config');
    ColorizeLogger.logFilePath =
        '${sandbox.path}${Platform.pathSeparator}distribution.log';
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  /// Writes [yaml] into the sandbox and parses it.
  Future<ConfigParser> parse(String yaml) {
    final file = File('${sandbox.path}${Platform.pathSeparator}config.yaml');
    file.writeAsStringSync(yaml);
    return ConfigParser.distributeYaml(file.path, null);
  }

  const minimalTask = '''
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder:
          android:
            binary-type: apk
''';

  group('ConfigParser.distributeYaml', () {
    test('parses a configuration without a variables section', () async {
      final config = await parse('''
name: Demo
description: Demo config
$minimalTask''');

      expect(config.tasks, hasLength(1));
      expect(config.tasks.single.key, 'android');
      expect(config.tasks.single.jobs.single.packageName, 'com.example.app');
    });

    test('reports a missing file with an actionable message', () {
      expect(
        () => ConfigParser.distributeYaml(
          '${sandbox.path}/nope.yaml',
          null,
        ),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            allOf(contains('not found'), contains('distribute init')),
          ),
        ),
      );
    });

    test('names the missing top level key', () {
      expect(
        () => parse('description: no name\n$minimalTask'),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.message, 'message', contains("'name'")),
        ),
      );
    });

    test('rejects a task without jobs', () {
      expect(
        () => parse('''
name: Demo
description: Demo config
tasks:
  - name: Empty
    key: empty
    jobs: []
'''),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.message, 'message', contains("'jobs'")),
        ),
      );
    });

    test('rejects duplicate task keys', () {
      expect(
        () => parse('''
name: Demo
description: Demo config
tasks:
  - name: One
    key: dup
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder: {android: {binary-type: apk}}
  - name: Two
    key: dup
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder: {android: {binary-type: apk}}
'''),
        throwsA(
          isA<ConfigException>().having(
              (e) => e.message, 'message', contains('Duplicate task key')),
        ),
      );
    });

    test('rejects a workflow that references an unknown job key', () {
      expect(
        () => parse('''
name: Demo
description: Demo config
tasks:
  - name: Android
    key: android
    workflows: [build, publish]
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder: {android: {binary-type: apk}}
'''),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            allOf(contains("workflow 'publish'"), contains('build')),
          ),
        ),
      );
    });

    test('rejects a job declaring both a builder and a publisher', () {
      expect(
        () => parse('''
name: Demo
description: Demo config
tasks:
  - name: Android
    key: android
    jobs:
      - name: Both
        key: both
        package_name: com.example.app
        builder: {android: {binary-type: apk}}
        publisher:
          firebase:
            file-path: out
            app-id: "1:2:android:3"
            binary-type: apk
'''),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.message, 'message', contains('both')),
        ),
      );
    });

    test('rejects an invalid android binary-type', () {
      expect(
        () => parse('''
name: Demo
description: Demo config
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        builder: {android: {binary-type: exe}}
'''),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.message, 'message', contains('binary-type')),
        ),
      );
    });

    test('parses continue-on-error and retry on a job', () async {
      final config = await parse('''
name: Demo
description: Demo config
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        continue-on-error: true
        retry: 2
        builder: {android: {binary-type: apk}}
''');

      final job = config.tasks.single.jobs.single;
      expect(job.continueOnError, isTrue);
      expect(job.retry, 2);
    });

    test('rejects a negative retry count', () {
      expect(
        () => parse('''
name: Demo
description: Demo config
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: com.example.app
        retry: -1
        builder: {android: {binary-type: apk}}
'''),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.message, 'message', contains('non-negative')),
        ),
      );
    });

    test('substitutes variables declared in the config', () async {
      final config = await parse('''
name: Demo
description: Demo config
variables:
  PKG: com.example.substituted
tasks:
  - name: Android
    key: android
    jobs:
      - name: Build
        key: build
        package_name: "\${{PKG}}"
        builder: {android: {binary-type: apk}}
''');

      expect(config.environments['PKG'], 'com.example.substituted');
    });
  });
}
