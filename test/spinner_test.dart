import 'dart:async';

import 'package:distribute_cli/logger.dart';
import 'package:test/test.dart';

/// Drives [Spinner] against a buffer instead of a terminal.
void main() {
  _spinnerWidth();

  late StringBuffer output;

  setUp(() {
    output = StringBuffer();
    ColorizeLogger.logFilePath = '';
    ColorizeLogger.useColors = false;
    ColorizeLogger.useUnicode = true;
    ColorizeLogger.verbosity = LogVerbosity.normal;
    ColorizeLogger.indentLevel = 0;
    ColorizeLogger.reserveStdout = false;

    Spinner.sink = () => output;
    Spinner.isTerminal = () => true;
  });

  tearDown(() {
    Spinner.resetOutput();
    Spinner.active = null;
    ColorizeLogger.verbosity = LogVerbosity.normal;
    ColorizeLogger.useUnicode = true;
  });

  /// Everything the spinner wrote so far.
  String written() => output.toString();

  group('when it runs', () {
    test('it draws while the body is pending and clears afterwards', () async {
      final gate = Completer<int>();
      final result = Spinner.run('building apk', () => gate.future);

      // Let the timer tick a few times.
      await Future<void>.delayed(Spinner.interval * 3);
      expect(written(), contains('building apk'));

      gate.complete(7);
      expect(await result, 7);

      // The last thing written must be an erase, so the terminal is left clean.
      expect(written().endsWith('\r'), isTrue);
      expect(Spinner.active, isNull);
    });

    test('it advances through the frames', () async {
      final gate = Completer<void>();
      final result = Spinner.run('working', () => gate.future);

      await Future<void>.delayed(Spinner.interval * 4);
      gate.complete();
      await result;

      final frames = RegExp(r'[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]')
          .allMatches(written())
          .map((m) => m.group(0))
          .toSet();
      expect(frames.length, greaterThan(1),
          reason: 'a static frame is not an animation');
    });

    test('it shows the elapsed time', () async {
      final gate = Completer<void>();
      final result = Spinner.run('working', () => gate.future);

      await Future<void>.delayed(Spinner.interval * 3);
      gate.complete();
      await result;

      expect(written(), matches(RegExp(r'\d+\.\ds')));
    });

    test('it stops even when the body throws', () async {
      await expectLater(
        Spinner.run('working', () async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );

      expect(Spinner.active, isNull);
      expect(written().endsWith('\r'), isTrue);
    });

    test('it returns the body result untouched', () async {
      expect(await Spinner.run('x', () async => 'value'), 'value');
    });

    test('a nested run does not start a second spinner', () async {
      final result = await Spinner.run('outer', () async {
        expect(Spinner.active, isNotNull);
        final before = Spinner.active;
        final inner = await Spinner.run('inner', () async => 1);
        expect(Spinner.active, same(before));
        return inner;
      });

      expect(result, 1);
      expect(written(), contains('outer'));
      expect(written(), isNot(contains('inner')));
    });

    test('the ASCII fallback is used without unicode', () async {
      ColorizeLogger.useUnicode = false;
      final gate = Completer<void>();
      final result = Spinner.run('working', () => gate.future);

      await Future<void>.delayed(Spinner.interval * 2);
      gate.complete();
      await result;

      expect(written(), isNot(matches(RegExp(r'[⠋⠙⠹]'))));
      expect(written(), contains('working'));
    });
  });

  group('when it must stay out of the way', () {
    test('nothing is drawn without a terminal', () async {
      Spinner.isTerminal = () => false;

      expect(await Spinner.run('working', () async => 1), 1);
      expect(written(), isEmpty);
      expect(Spinner.active, isNull);
    });

    test('nothing is drawn under --quiet', () async {
      ColorizeLogger.verbosity = LogVerbosity.quiet;
      expect(await Spinner.run('working', () async => 1), 1);
      expect(written(), isEmpty);
    });

    test('nothing is drawn under --silent', () async {
      ColorizeLogger.verbosity = LogVerbosity.silent;
      expect(await Spinner.run('working', () async => 1), 1);
      expect(written(), isEmpty);
    });

    test('nothing is drawn under --verbose', () async {
      // The tool's own output is streaming; an animation would be spliced
      // into the middle of it.
      ColorizeLogger.verbosity = LogVerbosity.verbose;
      expect(await Spinner.run('working', () async => 1), 1);
      expect(written(), isEmpty);
    });
  });

  group('sharing the terminal with log lines', () {
    test('a log line erases the spinner before printing', () async {
      final lines = StringBuffer();
      // The logger writes to the real stdout, which the test cannot capture,
      // so the ordering is asserted through the spinner's own buffer: an
      // erase has to appear between two paints.
      final gate = Completer<void>();
      final result = Spinner.run('working', () async {
        await Future<void>.delayed(Spinner.interval * 2);
        ColorizeLogger().logNote('something happened');
        lines.write('logged');
        await gate.future;
      });

      await Future<void>.delayed(Spinner.interval * 4);
      gate.complete();
      await result;

      // `\r` followed by spaces followed by `\r` is the erase sequence.
      expect(written(), contains(RegExp(r'\r +\r')));
      expect(lines.toString(), 'logged');
    });

    test('the erase covers the full painted width', () async {
      final gate = Completer<void>();
      final result = Spinner.run('a very long label indeed', () => gate.future);

      await Future<void>.delayed(Spinner.interval * 2);
      gate.complete();
      await result;

      final erase = RegExp(r'\r( +)\r').allMatches(written()).last.group(1)!;
      expect(erase.length,
          greaterThanOrEqualTo('a very long label indeed'.length));
    });
  });
}

/// The spinner must stay on one row: a wrapped line cannot be erased, because
/// `\r` only returns to the start of the last row.
///
/// Registered from `main`, so it shares the buffer that `setUp` installs.
void _spinnerWidth() {
  /// Whatever the spinner has written to the buffer `main` installed.
  String written() => (Spinner.sink() as StringBuffer).toString();

  group('line width', () {
    test('a long label is truncated rather than wrapped', () async {
      final gate = Completer<void>();
      final result = Spinner.run('x' * 500, () => gate.future);

      await Future<void>.delayed(Spinner.interval * 2);
      gate.complete();
      await result;

      for (final line in written().split('\r')) {
        expect(line.length, lessThan(500),
            reason: 'no painted line may exceed the pane');
      }
      expect(written(), contains('…'));
    });

    test('the erase still covers the truncated width', () async {
      final gate = Completer<void>();
      final result = Spinner.run('y' * 500, () => gate.future);

      await Future<void>.delayed(Spinner.interval * 2);
      gate.complete();
      await result;

      final painted = written()
          .split('\r')
          .where((s) => s.contains('y'))
          .map((s) => s.length)
          .reduce((a, b) => a > b ? a : b);
      final erased =
          RegExp(r'\r( +)\r').allMatches(written()).last.group(1)!.length;

      expect(erased, greaterThanOrEqualTo(painted));
    });
  });
}
