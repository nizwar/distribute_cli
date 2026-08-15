import 'dart:io';

import 'package:distribute_cli/logger.dart';
import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_builder;
import 'package:distribute_cli/app_builder/ios/arguments.dart' as ios_builder;
import 'package:distribute_cli/app_publisher/fastlane/arguments.dart'
    as fastlane_publisher;
import 'package:distribute_cli/app_publisher/firebase/arguments.dart'
    as firebase_publisher;
import 'package:distribute_cli/app_publisher/github/arguments.dart'
    as github_publisher;
import 'package:distribute_cli/app_publisher/xcrun/arguments.dart'
    as xcrun_publisher;
import 'package:test/test.dart';

void main() {
  _secretAbbreviationCoverage();
  _shortFormMasking();

  late Directory sandbox;
  late File logFile;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_logger');
    logFile = File('${sandbox.path}${Platform.pathSeparator}distribution.log');
    ColorizeLogger.logFilePath = logFile.path;
    ColorizeLogger.useColors = false;
    ColorizeLogger.verbosity = LogVerbosity.normal;
    ColorizeLogger.indentLevel = 0;
    ColorizeLogger.clearSecrets();
  });

  tearDown(() {
    ColorizeLogger.verbosity = LogVerbosity.normal;
    ColorizeLogger.indentLevel = 0;
    ColorizeLogger.clearSecrets();
    sandbox.deleteSync(recursive: true);
  });

  /// Contents of the log file, or an empty string when nothing was written.
  String logContents() =>
      logFile.existsSync() ? logFile.readAsStringSync() : '';

  group('secret redaction', () {
    test('masks a registered secret in the log file', () {
      ColorizeLogger.registerSecret('super-secret-token');
      ColorizeLogger().logInfo('Using token super-secret-token now');

      expect(logContents(), contains('***'));
      expect(logContents(), isNot(contains('super-secret-token')));
    });

    test('masks secrets echoed back by a child process', () {
      ColorizeLogger.registerSecret('ghp_abcdef123456');
      ColorizeLogger(true)
          .logDebug('remote responded: Bad credentials for ghp_abcdef123456');

      expect(logContents(), isNot(contains('ghp_abcdef123456')));
    });

    test('ignores unresolved placeholders so they stay debuggable', () {
      ColorizeLogger.registerSecret(r'${{GITHUB_TOKEN}}');
      ColorizeLogger().logInfo(r'token is ${{GITHUB_TOKEN}}');

      expect(logContents(), contains(r'${{GITHUB_TOKEN}}'));
    });

    test('ignores short values that would over-redact ordinary text', () {
      ColorizeLogger.registerSecret('abc');
      ColorizeLogger().logInfo('abc is a common substring');

      expect(logContents(), contains('abc is a common substring'));
    });

    test('redact is a pure function over the registered set', () {
      ColorizeLogger.registerSecret('p@ssword-value');
      expect(ColorizeLogger.redact('login p@ssword-value ok'), 'login *** ok');
    });
  });

  group('verbosity', () {
    test('normal hides debug but keeps it in the log file', () {
      ColorizeLogger().logDebug('hidden but recorded');
      expect(logContents(), contains('hidden but recorded'));
      expect(logContents(), contains('DEBUG'));
    });

    test('errors survive --quiet', () {
      ColorizeLogger.verbosity = LogVerbosity.quiet;
      final logger = ColorizeLogger();

      expect(LogLevel.error.minVerbosity, LogVerbosity.quiet);
      expect(
        LogVerbosity.quiet.rank >= LogLevel.error.minVerbosity.rank,
        isTrue,
      );
      // Info and warning are suppressed at quiet.
      expect(
        LogVerbosity.quiet.rank >= LogLevel.info.minVerbosity.rank,
        isFalse,
      );
      expect(
        LogVerbosity.quiet.rank >= LogLevel.warning.minVerbosity.rank,
        isFalse,
      );

      logger.logError('still recorded');
      expect(logContents(), contains('still recorded'));
    });

    test('silent hides even errors from the terminal', () {
      expect(
        LogVerbosity.silent.rank >= LogLevel.error.minVerbosity.rank,
        isFalse,
      );
    });

    test('the log file records every level regardless of verbosity', () {
      ColorizeLogger.verbosity = LogVerbosity.silent;
      final logger = ColorizeLogger();

      logger.logInfo('info line');
      logger.logWarning('warn line');
      logger.logError('error line');
      logger.logDebug('debug line');

      final contents = logContents();
      expect(contents, contains('info line'));
      expect(contents, contains('warn line'));
      expect(contents, contains('error line'));
      expect(contents, contains('debug line'));
    });

    test('isVerbose follows the global verbosity', () {
      expect(ColorizeLogger().isVerbose, isFalse);
      ColorizeLogger.verbosity = LogVerbosity.verbose;
      expect(ColorizeLogger().isVerbose, isTrue);
    });

    test('an instance can force verbose without touching the global level', () {
      ColorizeLogger.verbosity = LogVerbosity.quiet;
      expect(ColorizeLogger(true).isVerbose, isTrue);
      expect(ColorizeLogger().isVerbose, isFalse);
    });

    test('--silent overrides a per-instance verbose request', () {
      // Asking for no output has to mean no output, whoever asked.
      ColorizeLogger.verbosity = LogVerbosity.silent;
      expect(ColorizeLogger(true).isVerbose, isFalse);
    });
  });

  group('file logging toggle', () {
    test('an empty --log-file disables persistence', () {
      ColorizeLogger.logFilePath = '';
      expect(ColorizeLogger.fileLoggingEnabled, isFalse);

      expect(() => ColorizeLogger().logInfo('nowhere'), returnsNormally);
      expect(() => ColorizeLogger.startLogFile(['run']), returnsNormally);
      expect(logFile.existsSync(), isFalse);
    });
  });

  group('LogVerbosity.fromFlags', () {
    test('defaults to normal', () {
      expect(LogVerbosity.fromFlags(), LogVerbosity.normal);
    });

    test('verbose raises the level', () {
      expect(
        LogVerbosity.fromFlags(verbose: true),
        LogVerbosity.verbose,
      );
    });

    test('quiet beats verbose', () {
      expect(
        LogVerbosity.fromFlags(quiet: true, verbose: true),
        LogVerbosity.quiet,
      );
    });

    test('silent beats everything', () {
      expect(
        LogVerbosity.fromFlags(silent: true, quiet: true, verbose: true),
        LogVerbosity.silent,
      );
    });
  });

  group('log file format', () {
    test('each line carries a timestamp and a level label', () {
      ColorizeLogger().logSuccess('done');
      expect(
        logContents(),
        matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}  OK\s+done')),
      );
    });

    test('the terminal symbols never leak into the file', () {
      ColorizeLogger().logSuccess('done');
      expect(logContents(), isNot(contains(LogSymbols.success)));
    });
  });

  group('indentation', () {
    test('group nests and always restores the previous depth', () async {
      expect(ColorizeLogger.indentLevel, 0);
      await ColorizeLogger.group(() async {
        expect(ColorizeLogger.indentLevel, 1);
        await ColorizeLogger.group(() async {
          expect(ColorizeLogger.indentLevel, 2);
        });
      });
      expect(ColorizeLogger.indentLevel, 0);
    });

    test('depth is restored even when the body throws', () async {
      await expectLater(
        ColorizeLogger.group(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(ColorizeLogger.indentLevel, 0);
    });
  });

  group('multi-line chunks', () {
    // A child process hands us arbitrary chunks through utf8.decoder, not
    // lines, so a single call routinely carries several lines.
    test('every line of a chunk gets its own log record', () {
      ColorizeLogger(true).logDebug('one\ntwo\nthree');

      final lines = logContents().trim().split('\n');
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(line, matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}  DEBUG')));
      }
      expect(lines[0], endsWith('one'));
      expect(lines[2], endsWith('three'));
    });

    test('a trailing newline does not create a blank record', () {
      ColorizeLogger().logInfo('only line\n');
      expect(logContents().trim().split('\n'), hasLength(1));
    });

    test('a chunk that is only whitespace is dropped entirely', () {
      ColorizeLogger().logInfo('\n\n');
      expect(logContents(), isEmpty);
    });
  });

  group('ANSI handling', () {
    test('escape codes from child processes never reach the log file', () {
      ColorizeLogger(true).logDebug('\x1B[32mBuilding\x1B[0m done');

      expect(logContents(), contains('Building done'));
      expect(logContents(), isNot(contains('\x1B')));
    });

    test('stripAnsi leaves plain text untouched', () {
      expect(ColorizeLogger.stripAnsi('plain text'), 'plain text');
      expect(ColorizeLogger.stripAnsi('\x1B[1;31mred\x1B[0m'), 'red');
    });
  });

  group('run header', () {
    test('records the version, the date and the invocation', () {
      ColorizeLogger.startLogFile(['run', '--dry-run']);

      final contents = logContents();
      expect(contents, contains('# distribute_cli'));
      expect(contents, contains('# args: run --dry-run'));
      expect(contents, matches(RegExp(r'# \d{4}-\d{2}-\d{2}T')));
    });

    test('masks credentials passed on the command line', () {
      // The header is written before any job registers its secrets, so the
      // command line has to be masked on its own.
      ColorizeLogger.startLogFile([
        'publish',
        'github',
        '--token',
        'ghp_supersecret',
        '--api-key=ABC123DEF4',
      ]);

      final contents = logContents();
      expect(contents, isNot(contains('ghp_supersecret')));
      expect(contents, isNot(contains('ABC123DEF4')));
      expect(contents, contains('--token ***'));
      expect(contents, contains('--api-key=***'));
    });

    test('leaves ordinary options readable', () {
      expect(
        ColorizeLogger.maskSecretArguments(
          ['run', '-o', 'android.build', '--json-key', 'key.json'],
        ),
        'run -o android.build --json-key key.json',
      );
    });

    test('truncates the previous run instead of appending to it', () {
      ColorizeLogger().logInfo('from the previous run');
      ColorizeLogger.startLogFile(['run']);
      expect(logContents(), isNot(contains('from the previous run')));
    });

    test('refuses to delete a directory passed as --log-file', () {
      final directory = Directory('${sandbox.path}/not-a-log')..createSync();
      ColorizeLogger.logFilePath = directory.path;

      expect(() => ColorizeLogger.startLogFile(['run']), returnsNormally);
      expect(directory.existsSync(), isTrue);
    });
  });

  test('a missing log directory never crashes the run', () {
    ColorizeLogger.logFilePath =
        '${sandbox.path}/missing/nested/distribution.log';
    expect(() => ColorizeLogger().logInfo('still fine'), returnsNormally);
  });
}

/// Proves [ColorizeLogger.secretAbbreviations] has not fallen behind the real
/// argument parsers.
///
/// The run header is masked from the raw command line, before anything is
/// parsed, so the mapping is maintained by hand. A credential option that grows
/// an abbreviation without being listed here would leak it into the log file,
/// which is exactly the failure this file exists to prevent.
void _secretAbbreviationCoverage() {
  final parsers = <String, ArgParser>{
    'fastlane': fastlane_publisher.Arguments.parser,
    'firebase': firebase_publisher.Arguments.parser,
    'xcrun': xcrun_publisher.Arguments.parser,
    'github': github_publisher.Arguments.parser,
    'android': android_builder.Arguments.parser,
    'ios': ios_builder.Arguments.parser,
  };

  final secretish = RegExp(
    r'(token|password|passwd|secret|credential|api-key|api-issuer|key-data)',
    caseSensitive: false,
  );

  group('secret abbreviation coverage', () {
    parsers.forEach((command, parser) {
      test('$command declares no unmasked credential abbreviation', () {
        final listed = ColorizeLogger.secretAbbreviations[command] ?? const {};
        for (final entry in parser.options.entries) {
          final abbr = entry.value.abbr;
          if (abbr == null) continue;
          if (!secretish.hasMatch(entry.key)) continue;

          expect(
            listed,
            contains(abbr),
            reason: '`$command --${entry.key}` has abbreviation -$abbr; add it '
                'to ColorizeLogger.secretAbbreviations or its value will be '
                'written to the log header in the clear',
          );
        }
      });
    });
  });
}

/// The short-form leak the audit found: `-p` and `-J` reached the log header
/// in the clear because only long option names were matched.
void _shortFormMasking() {
  group('short form secrets in the run header', () {
    test('xcrun -p is masked, separated form', () {
      expect(
        ColorizeLogger.maskSecretArguments(
            ['publish', 'xcrun', '-p', 'abcd-efgh-ijkl']),
        'publish xcrun -p ***',
      );
    });

    test('xcrun -p is masked, attached form', () {
      expect(
        ColorizeLogger.maskSecretArguments(
            ['publish', 'xcrun', '-pabcd-efgh-ijkl']),
        'publish xcrun -p***',
      );
    });

    test('fastlane -J is masked', () {
      expect(
        ColorizeLogger.maskSecretArguments(
            ['publish', 'fastlane', '-J', '{"private_key":"x"}']),
        'publish fastlane -J ***',
      );
    });

    test('a bundled short option still masks from the credential letter', () {
      expect(
        ColorizeLogger.maskSecretArguments(['publish', 'xcrun', '-vp', 'pw']),
        'publish xcrun -vp ***',
      );
    });

    test('the same letter is left alone under a different command', () {
      // `create job -p` is the package name, not a password.
      expect(
        ColorizeLogger.maskSecretArguments(
            ['create', 'job', 'builder', '-p', 'com.example.app']),
        'create job builder -p com.example.app',
      );
    });

    test('long forms keep working', () {
      expect(
        ColorizeLogger.maskSecretArguments(['--token', 'abc']),
        '--token ***',
      );
      expect(
        ColorizeLogger.maskSecretArguments(['--token=abc']),
        '--token=***',
      );
    });
  });
}
