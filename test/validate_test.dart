import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/validate_command.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late File config;
  late File log;
  late CommandRunner<int> runner;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_validate');
    config = File('${sandbox.path}${Platform.pathSeparator}distribution.yaml');
    log = File('${sandbox.path}${Platform.pathSeparator}distribution.log');

    ColorizeLogger.logFilePath = log.path;
    ColorizeLogger.useColors = false;
    ColorizeLogger.verbosity = LogVerbosity.normal;
    ColorizeLogger.indentLevel = 0;

    runner = CommandRunner<int>('distribute', 'test')
      ..argParser.addOption('config', defaultsTo: 'distribution.yaml')
      ..addCommand(ValidateCommand());
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  /// Runs `validate` against [yaml] and returns (exitCode, output).
  Future<(int, String)> validate(String yaml, {bool strict = false}) async {
    config.writeAsStringSync(yaml);
    if (log.existsSync()) log.deleteSync();
    final code = await runner.run([
      'validate',
      '-c',
      config.path,
      if (strict) '--strict',
    ]);
    return (code ?? 0, log.existsSync() ? log.readAsStringSync() : '');
  }

  const valid = '''
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

  group('unknown keys', () {
    test('a clean configuration reports no problems', () async {
      final (code, output) = await validate(valid);
      expect(code, 0);
      expect(output, contains('no problems found'));
    });

    test('catches a mistyped build option and suggests the right one',
        () async {
      // The core footgun: `binary-typ` parses fine and silently builds an APK
      // instead of the requested AAB.
      final (_, output) = await validate(valid.replaceAll(
        'binary-type: aab',
        'binary-typ: aab',
      ));

      expect(output, contains("unknown key 'binary-typ'"));
      expect(output, contains("did you mean 'binary-type'"));
    });

    test('catches a mistyped job option', () async {
      final (_, output) = await validate(
        valid.replaceAll(
            '        builder:', '        retries: 2\n        builder:'),
      );
      expect(output, contains("unknown key 'retries'"));
      expect(output, contains("did you mean 'retry'"));
    });

    test('catches a mistyped top level section', () async {
      final (_, output) = await validate('$valid\nnotification: []\n');
      expect(output, contains("unknown key 'notification'"));
      expect(output, contains("did you mean 'notifications'"));
    });

    test('catches a mistyped task key', () async {
      final (_, output) = await validate(
        valid.replaceAll(
            '    key: android', '    key: android\n    workflow: [build]'),
      );
      expect(output, contains("unknown key 'workflow'"));
    });

    test('catches a mistyped ai key', () async {
      final (_, output) = await validate(
        '$valid\nai:\n  provider: openai\n  baseurl: http://x\n',
      );
      expect(output, contains("unknown key 'baseurl'"));
      expect(output, contains("did you mean 'base-url'"));
    });

    test('catches an unknown publisher', () async {
      final (_, output) = await validate('''
name: demo
description: demo
tasks:
  - name: Android
    key: android
    jobs:
      - name: Publish
        key: publish
        description: d
        package_name: com.example.app
        publisher:
          firebase:
            file-path: out
            app-id: "1:2:android:3"
            binary-type: apk
          slack:
            url: http://x
''');
      expect(output, contains("unknown key 'slack'"));
    });

    test('warns that `arguments` is not read by anything', () async {
      final (_, output) = await validate('$valid\narguments:\n  shared: {}\n');
      expect(output, contains('has no effect'));
    });

    test('a config using `arguments` no longer crashes', () async {
      // Regression: the field was typed Map<String, JobArguments> while being
      // populated with raw maps, so any config using it died with a TypeError.
      final (code, output) =
          await validate('$valid\narguments:\n  shared: {}\n');
      expect(code, 0);
      expect(output, isNot(contains('is not a subtype of')));
    });

    test('unknown keys are warnings, not errors, unless --strict', () async {
      final typo = valid.replaceAll('binary-type', 'binary-typ');

      final (lenient, _) = await validate(typo);
      expect(lenient, 0);

      final (strict, _) = await validate(typo, strict: true);
      expect(strict, 1);
    });
  });
}
