import 'dart:io';

import 'package:distribute_cli/app_publisher/fastlane/arguments.dart'
    as fastlane;
import 'package:distribute_cli/app_publisher/firebase/arguments.dart'
    as firebase;
import 'package:distribute_cli/app_publisher/github/arguments.dart' as github;
import 'package:distribute_cli/app_publisher/xcrun/arguments.dart' as xcrun;
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_publisher');
    ColorizeLogger.logFilePath =
        '${sandbox.path}${Platform.pathSeparator}distribution.log';
    ColorizeLogger.clearSecrets();
  });

  tearDown(() {
    ColorizeLogger.clearSecrets();
    sandbox.deleteSync(recursive: true);
  });

  Variables variables() => Variables(<String, dynamic>{}, null);

  /// Creates a file inside the sandbox and returns its path.
  String artifact(String name) {
    final file = File('${sandbox.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync('binary');
    return file.path;
  }

  group('fastlane', () {
    test(
      'resolves the package name from --package-name when there is no parent job',
      () {
        // Regression: the standalone `distribute publish fastlane` path used to
        // dereference an uninitialised `parent` and throw LateInitializationError.
        final arguments = fastlane.Arguments(
          variables(),
          filePath: artifact('app.apk'),
          packageName: 'com.example.standalone',
          metadataPath: 'metadata',
          jsonKey: 'key.json',
          binaryType: 'apk',
          uploadDebugSymbols: false,
        );

        expect(
          arguments.argumentBuilder,
          contains('package_name:com.example.standalone'),
        );
      },
    );

    test('explains itself when no package name can be determined', () {
      final arguments = fastlane.Arguments(
        variables(),
        filePath: artifact('app.apk'),
        metadataPath: 'metadata',
        jsonKey: 'key.json',
        binaryType: 'apk',
        uploadDebugSymbols: false,
      );

      expect(
        () => arguments.argumentBuilder,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('--package-name'),
          ),
        ),
      );
    });

    test('does not mutate the caller mapping-paths list across reads', () {
      final mappingPaths = <String>['existing.txt'];
      final arguments = fastlane.Arguments(
        variables(),
        filePath: artifact('app.apk'),
        packageName: 'com.example.app',
        metadataPath: 'metadata',
        jsonKey: 'key.json',
        binaryType: 'apk',
        mappingPaths: mappingPaths,
        uploadDebugSymbols: false,
      );

      arguments.argumentBuilder;
      arguments.argumentBuilder;

      expect(mappingPaths, equals(['existing.txt']));
    });

    test('marks json-key-data as a secret', () {
      final arguments = fastlane.Arguments(
        variables(),
        filePath: artifact('app.apk'),
        metadataPath: 'metadata',
        jsonKey: 'key.json',
        binaryType: 'apk',
      );

      expect(arguments.secretKeys, contains('json-key-data'));
    });
  });

  group('firebase', () {
    test('accepts the documented CLI options without crashing', () {
      // Regression: fromArgResults read an option named "cli-token" that the
      // parser never declared, so the subcommand threw before doing any work.
      final parsed = firebase.Arguments.parser.parse([
        '--file-path',
        'out',
        '--app-id',
        '1:2:android:3',
        '--token',
        'firebase-ci-token',
      ]);

      final arguments = firebase.Arguments.fromArgResults(parsed, null);
      expect(arguments.filePath, 'out');
      expect(arguments.appId, '1:2:android:3');
      expect(arguments.cliToken, 'firebase-ci-token');
      expect(arguments.argumentBuilder, contains('--token=firebase-ci-token'));
    });

    test('marks the CI token as a secret', () {
      final arguments = firebase.Arguments(
        variables(),
        filePath: 'out',
        appId: '1:2:android:3',
        binaryType: 'apk',
        cliToken: 'firebase-ci-token',
      );

      expect(arguments.secretKeys, contains('token'));
    });
  });

  group('xcrun', () {
    test('uses the --validate-app command rather than an unrelated -v flag',
        () {
      final arguments = xcrun.Arguments(
        variables(),
        filePath: artifact('app.ipa'),
        validateApp: true,
      );

      expect(arguments.argumentsForCommand('--validate-app'),
          contains('--validate-app'));
      // `-v` means verbose in altool and never triggered validation.
      expect(arguments.argumentBuilder, isNot(contains('-v')));
      expect(arguments.argumentBuilder, contains('--upload-app'));
    });

    test('honours upload-package in place of -f', () {
      final arguments = xcrun.Arguments(
        variables(),
        filePath: artifact('app.ipa'),
        uploadPackage: 'prepared.itmsp',
      );

      final built = arguments.argumentBuilder;
      expect(built, containsAllInOrder(['--upload-package', 'prepared.itmsp']));
      expect(built, isNot(contains('-f')));
    });

    test('masks the App Store Connect credentials', () {
      final arguments = xcrun.Arguments(
        variables(),
        filePath: artifact('app.ipa'),
        password: 'app-specific-password',
      );

      expect(arguments.secretKeys, contains('password'));
      expect(arguments.secretKeys, contains('api-key'));
    });
  });

  group('github', () {
    test('filters directory uploads by binary-type', () {
      final arguments = github.Arguments(
        variables(),
        filePath: sandbox.path,
        binaryType: 'apk',
        repoName: 'repo',
        repoOwner: 'owner',
        token: 'ghp_token_value',
        releaseName: 'v1.0.0',
      );

      expect(arguments.binaryType, 'apk');
      expect(arguments.toJson()['binary-type'], 'apk');
    });

    test('requires a release name in the configuration', () {
      expect(
        () => github.Arguments.fromJson(
          {
            'file-path': 'out',
            'repo-name': 'repo',
            'repo-owner': 'owner',
            'token': 'ghp_token_value',
          },
          variables: variables(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('parses draft and prerelease from their stringified form', () {
      // publish() round-trips the config through Variables.processMap, which
      // turns every value into a String.
      final arguments = github.Arguments.fromJson(
        {
          'file-path': 'out',
          'binary-type': 'aab',
          'repo-name': 'repo',
          'repo-owner': 'owner',
          'token': 'ghp_token_value',
          'release-name': 'v1.0.0',
          'draft': 'true',
          'prerelease': 'false',
        },
        variables: variables(),
      );

      expect(arguments.draft, isTrue);
      expect(arguments.prerelease, isFalse);
    });

    test('defaults to a published release, not a draft', () {
      final arguments = github.Arguments(
        variables(),
        filePath: 'out',
        binaryType: 'apk',
        repoName: 'repo',
        repoOwner: 'owner',
        token: 'ghp_token_value',
        releaseName: 'v1.0.0',
      );

      expect(arguments.draft, isFalse);
    });
  });

  group('dry run', () {
    tearDown(() => JobArguments.dryRun = false);

    test('a missing artifact is tolerated during a rehearsal', () async {
      JobArguments.dryRun = true;
      final arguments = firebase.Arguments(
        variables(),
        filePath: '${sandbox.path}/does-not-exist',
        appId: '1:2:android:3',
        binaryType: 'apk',
      );

      expect(await arguments.publish(), 0);
    });
  });
}
