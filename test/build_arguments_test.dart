import 'dart:io';

import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/app_builder/ios/arguments.dart' as ios_arguments;
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_build');
    ColorizeLogger.logFilePath =
        '${sandbox.path}${Platform.pathSeparator}distribution.log';
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Variables variables() => Variables(<String, dynamic>{}, null);

  group('dart defines', () {
    test('emits one --dart-define per entry, not the invalid --dart-defines',
        () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
        dartDefines: 'FLAVOR=prod,API_URL=https://example.com',
      );

      final built = arguments.argumentBuilder;
      expect(built, contains('--dart-define=FLAVOR=prod'));
      expect(built, contains('--dart-define=API_URL=https://example.com'));
      expect(
        built.where((arg) => arg.startsWith('--dart-defines')),
        isEmpty,
        reason: 'Flutter has no --dart-defines option',
      );
    });

    test('trims whitespace and ignores empty entries', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
        dartDefines: ' A=1 , , B=2 ',
      );

      expect(
        arguments.dartDefineArguments,
        equals(['--dart-define=A=1', '--dart-define=B=2']),
      );
    });

    test('emits nothing when dart defines are absent', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
      );

      expect(arguments.dartDefineArguments, isEmpty);
    });

    test('keeps --dart-define-from-file untouched', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
        dartDefinesFile: 'defines.json',
      );

      expect(
        arguments.argumentBuilder,
        contains('--dart-define-from-file=defines.json'),
      );
    });
  });

  group('obfuscation', () {
    test('android auto-fills split-debug-info, which flutter requires', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
        obfuscate: true,
      );

      expect(arguments.argumentBuilder, contains('--obfuscate'));
      expect(
        arguments.argumentBuilder.any(
          (arg) => arg.startsWith('--split-debug-info='),
        ),
        isTrue,
      );
    });

    test('android honours an explicit split-debug-info path', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
        obfuscate: true,
        splitDebugInfo: 'symbols/android',
      );

      expect(
        arguments.argumentBuilder,
        contains('--split-debug-info=symbols/android'),
      );
    });

    test('android does not add split-debug-info without obfuscation', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'apk',
      );

      expect(arguments.effectiveSplitDebugInfo, isNull);
    });

    test('ios supports obfuscation with the same guarantee', () {
      final arguments = ios_arguments.Arguments(
        variables(),
        binaryType: 'ipa',
        obfuscate: true,
      );

      expect(arguments.argumentBuilder, contains('--obfuscate'));
      expect(
        arguments.argumentBuilder.any(
          (arg) => arg.startsWith('--split-debug-info='),
        ),
        isTrue,
      );
    });
  });

  group('validation', () {
    test('rejects an unsupported android binary type', () {
      expect(
        () => android_arguments.Arguments(variables(), binaryType: 'exe'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects split-per-abi combined with an app bundle', () {
      expect(
        () => android_arguments.Arguments(
          variables(),
          binaryType: 'aab',
          splitPerAbi: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('argument ordering', () {
    test('build mode and flavor are forwarded verbatim', () {
      final arguments = android_arguments.Arguments(
        variables(),
        binaryType: 'aab',
        buildMode: 'profile',
        flavor: 'staging',
      );

      final built = arguments.argumentBuilder;
      expect(built.first, 'aab');
      expect(built, contains('--profile'));
      expect(built, contains('--flavor=staging'));
    });

    test('pub is explicitly enabled or disabled', () {
      expect(
        android_arguments.Arguments(variables(), binaryType: 'apk', pub: false)
            .argumentBuilder,
        contains('--no-pub'),
      );
      expect(
        android_arguments.Arguments(variables(), binaryType: 'apk')
            .argumentBuilder,
        contains('--pub'),
      );
    });
  });
}
