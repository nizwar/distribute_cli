import 'dart:io';

import 'package:distribute_cli/parsers/artifact_report.dart';
import 'package:distribute_cli/parsers/builtin_variables.dart';
import 'package:distribute_cli/parsers/notification_config.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:test/test.dart';

void main() {
  group('BuiltinVariables', () {
    setUp(BuiltinVariables.reset);
    tearDown(BuiltinVariables.reset);

    test('exposes the git and pubspec helpers', () {
      expect(
        BuiltinVariables.names,
        containsAll([
          'GIT_SHA',
          'GIT_SHORT_SHA',
          'GIT_BRANCH',
          'GIT_COMMIT_COUNT',
          'PUBSPEC_VERSION',
          'PUBSPEC_VERSION_NAME',
          'PUBSPEC_BUILD_NUMBER',
          'BUILD_DATE',
        ]),
      );
    });

    test('returns null for a name it does not own', () async {
      expect(await BuiltinVariables.resolve('NOT_A_BUILTIN'), isNull);
    });

    test('resolves the version declared in pubspec.yaml', () async {
      // The test runs from the package root, so its own pubspec is readable.
      final version = await BuiltinVariables.resolve('PUBSPEC_VERSION');
      expect(version, isNotNull);
      expect(await BuiltinVariables.resolve('PUBSPEC_NAME'), 'distribute_cli');
    });

    test('BUILD_DATE is an ISO calendar date', () async {
      final date = await BuiltinVariables.resolve('BUILD_DATE');
      expect(date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('is usable straight from a placeholder', () async {
      final resolved = await Variables(<String, dynamic>{}, null)
          .process(r'build-${{BUILD_DATE}}');
      expect(resolved, isNot(contains(r'${{')));
    });

    test('an explicit variable overrides the built-in', () async {
      final resolved =
          await Variables(<String, dynamic>{'BUILD_DATE': 'pinned'}, null)
              .process(r'${{BUILD_DATE}}');
      expect(resolved, 'pinned');
    });

    test('an unknown placeholder is left untouched', () async {
      final resolved = await Variables(<String, dynamic>{}, null)
          .process(r'${{TOTALLY_UNKNOWN}}');
      expect(resolved, r'${{TOTALLY_UNKNOWN}}');
    });
  });

  group('NotificationConfig', () {
    test('parses a slack entry', () {
      final config = NotificationConfig.fromJson({
        'provider': 'slack',
        'webhook-url': 'https://hooks.slack.com/services/x',
        'on': 'failure',
        'title': 'Android release',
      });

      expect(config.provider, NotifyProvider.slack);
      expect(config.on, NotifyOn.failure);
      expect(config.buildPayload('hi'), {'text': 'hi'});
    });

    test('discord uses a content field', () {
      final config = NotificationConfig.fromJson({
        'provider': 'discord',
        'webhook-url': 'https://discord.com/api/webhooks/x',
      });

      expect(config.buildPayload('hi'), {'content': 'hi'});
      expect(config.on, NotifyOn.always);
    });

    test('telegram requires a chat id', () {
      expect(
        () => NotificationConfig.fromJson({
          'provider': 'telegram',
          'webhook-url': 'https://api.telegram.org/botX/sendMessage',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a webhook url is mandatory', () {
      expect(
        () => NotificationConfig.fromJson({'provider': 'slack'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an unknown provider', () {
      expect(
        () => NotificationConfig.fromJson({
          'provider': 'carrier-pigeon',
          'webhook-url': 'https://example.com',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('triggers fire only for the matching outcome', () {
      expect(NotifyOn.always.shouldFire(succeeded: true), isTrue);
      expect(NotifyOn.always.shouldFire(succeeded: false), isTrue);
      expect(NotifyOn.success.shouldFire(succeeded: true), isTrue);
      expect(NotifyOn.success.shouldFire(succeeded: false), isFalse);
      expect(NotifyOn.failure.shouldFire(succeeded: false), isTrue);
      expect(NotifyOn.failure.shouldFire(succeeded: true), isFalse);
    });
  });

  group('Artifact', () {
    late Directory sandbox;

    setUp(() => sandbox =
        Directory.systemTemp.createTempSync('distribute_cli_artifact'));
    tearDown(() => sandbox.deleteSync(recursive: true));

    test('reports the size and a stable sha256', () async {
      final file = File('${sandbox.path}${Platform.pathSeparator}app.apk');
      await file.writeAsString('hello');

      final artifact = await Artifact.fromFile(file);
      expect(artifact.name, 'app.apk');
      expect(artifact.sizeInBytes, 5);
      expect(
        artifact.sha256Hash,
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
      expect(artifact.shortHash, '2cf24dba5fb0');
    });

    test('formats sizes for humans', () {
      expect(
        const Artifact(filePath: 'a', sizeInBytes: 512, sha256Hash: '0')
            .readableSize,
        '512 B',
      );
      expect(
        const Artifact(filePath: 'a', sizeInBytes: 2048, sha256Hash: '0')
            .readableSize,
        '2.0 KB',
      );
      expect(
        const Artifact(
          filePath: 'a',
          sizeInBytes: 25 * 1024 * 1024,
          sha256Hash: '0',
        ).readableSize,
        '25.0 MB',
      );
    });

    test('only picks up distributable extensions', () async {
      File('${sandbox.path}${Platform.pathSeparator}app.apk')
          .writeAsStringSync('a');
      File('${sandbox.path}${Platform.pathSeparator}notes.txt')
          .writeAsStringSync('b');

      final artifacts = await Artifact.fromDirectory(sandbox.path);
      expect(artifacts.map((a) => a.name), ['app.apk']);
    });

    test('a missing directory yields no artifacts', () async {
      expect(await Artifact.fromDirectory('${sandbox.path}/nope'), isEmpty);
    });
  });
}
