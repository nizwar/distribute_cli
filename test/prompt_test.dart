import 'dart:io';

import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/prompt.dart';
import 'package:test/test.dart';

void main() {
  _multiSelectEdges();

  late Prompt prompt;
  final original = Prompt.readLine;

  setUp(() {
    ColorizeLogger.logFilePath = '';
    ColorizeLogger.useColors = false;
    ColorizeLogger.verbosity = LogVerbosity.silent;
    prompt = Prompt();
  });

  tearDown(() => Prompt.readLine = original);

  /// Feeds [answers] to the next prompts, then end-of-input.
  void answering(List<String> answers) {
    final queue = List<String>.from(answers);
    Prompt.readLine = () => queue.isEmpty ? null : queue.removeAt(0);
  }

  group('end of input', () {
    // Regression: these loops used to re-ask on empty input without checking
    // for EOF. `readLineSync` keeps returning null once the stream is closed,
    // so a wizard started from CI span forever — and the recursive variant in
    // `create` overflowed the stack with a 14k frame trace.
    test('text aborts instead of re-asking forever', () {
      answering([]);
      expect(() => prompt.text('name'), throwsA(isA<PromptAbortedException>()));
    });

    test('text aborts after the answers run out', () {
      answering(['', '', '']);
      expect(() => prompt.text('name'), throwsA(isA<PromptAbortedException>()));
    });

    test('secret aborts instead of re-asking forever', () {
      answering([]);
      expect(
          () => prompt.secret('key'), throwsA(isA<PromptAbortedException>()));
    });

    test('confirm aborts rather than assuming the default', () {
      // Silently taking the default would answer "yes" to questions like
      // "write the API key into distribution.yaml?".
      answering([]);
      expect(
        () => prompt.confirm('overwrite?'),
        throwsA(isA<PromptAbortedException>()),
      );
    });

    test('select aborts rather than assuming the default', () {
      answering([]);
      expect(
        () => prompt.select('pick', ['a', 'b'], label: (v) => v),
        throwsA(isA<PromptAbortedException>()),
      );
    });

    test('the message says what to do instead', () {
      answering([]);
      try {
        prompt.text('name');
        fail('expected an abort');
      } on PromptAbortedException catch (e) {
        expect(e.message, contains('options'));
      }
    });
  });

  group('answers', () {
    test('text returns the typed value', () {
      answering(['hello']);
      expect(prompt.text('name'), 'hello');
    });

    test('text falls back to the default on an empty line', () {
      answering(['']);
      expect(prompt.text('name', defaultValue: 'fallback'), 'fallback');
    });

    test('text re-asks while the answer is empty and there is no default', () {
      answering(['', '  ', 'finally']);
      expect(prompt.text('name'), 'finally');
    });

    test('text allows an empty answer when asked to', () {
      answering(['']);
      expect(prompt.text('note', allowEmpty: true), '');
    });

    test('confirm reads yes and no in both spellings', () {
      answering(['y']);
      expect(prompt.confirm('go?'), isTrue);
      answering(['no']);
      expect(prompt.confirm('go?'), isFalse);
    });

    test('confirm re-asks on an unrecognised answer', () {
      answering(['maybe', 'yes']);
      expect(prompt.confirm('go?'), isTrue);
    });

    test('confirm takes the default on an empty line', () {
      answering(['']);
      expect(prompt.confirm('go?', defaultValue: false), isFalse);
    });

    test('select returns the numbered choice', () {
      answering(['2']);
      expect(prompt.select('pick', ['a', 'b'], label: (v) => v), 'b');
    });

    test('select re-asks on an out of range number', () {
      answering(['9', '0', '1']);
      expect(prompt.select('pick', ['a', 'b'], label: (v) => v), 'a');
    });

    test('select takes the default on an empty line', () {
      answering(['']);
      expect(
        prompt.select('pick', ['a', 'b'], label: (v) => v, defaultIndex: 1),
        'b',
      );
    });
  });

  group('validation', () {
    test('text re-asks while validate rejects the answer', () {
      // Rejecting at the prompt is the whole point: the old wizard only found
      // out a key was taken after every question had been answered.
      answering(['taken', 'also-taken', 'free']);
      final answer = prompt.text(
        'key',
        validate: (value) =>
            value.startsWith('free') ? null : 'that key is already used',
      );
      expect(answer, 'free');
    });

    test('validate also sees a defaulted answer', () {
      answering(['', 'typed']);
      final seen = <String>[];
      final answer = prompt.text(
        'key',
        defaultValue: 'suggested',
        validate: (value) {
          seen.add(value);
          return value == 'suggested' ? 'no good' : null;
        },
      );
      expect(seen, ['suggested', 'typed']);
      expect(answer, 'typed');
    });

    test('an empty answer is not run through validate when allowed', () {
      answering(['']);
      expect(
        prompt.text('note', allowEmpty: true, validate: (_) => 'never'),
        '',
      );
    });
  });

  group('multiSelect', () {
    final options = ['firebase', 'fastlane', 'xcrun', 'github'];

    test('reads a comma separated list', () {
      answering(['1,4']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['firebase', 'github'],
      );
    });

    test('reads a space separated list', () {
      answering(['2 3']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['fastlane', 'xcrun'],
      );
    });

    test('reads a range', () {
      answering(['1-3']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['firebase', 'fastlane', 'xcrun'],
      );
    });

    test('"all" selects everything', () {
      answering(['all']);
      expect(prompt.multiSelect('where', options, label: (v) => v), options);
    });

    test('returns the options in list order, not answer order', () {
      // The order decides which publisher block is written first; it has to be
      // stable no matter how the user typed the numbers.
      answering(['4,1']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['firebase', 'github'],
      );
    });

    test('de-duplicates a repeated pick', () {
      answering(['1,1,1']);
      expect(
          prompt.multiSelect('where', options, label: (v) => v), ['firebase']);
    });

    test('rejects the whole answer when one number is out of range', () {
      // Silently dropping the bad token would build a job the user did not ask
      // for, so the answer is refused as a whole.
      answering(['1,9', '2']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['fastlane'],
      );
    });

    test('rejects a backwards or oversized range', () {
      answering(['3-1', '1-9', '2']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['fastlane'],
      );
    });

    test('rejects a non numeric answer', () {
      answering(['firebase', '1']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['firebase'],
      );
    });

    test('an empty answer takes the defaults', () {
      answering(['']);
      expect(
        prompt.multiSelect('where', options,
            label: (v) => v, defaults: ['github']),
        ['github'],
      );
    });

    test('an empty answer re-asks when there is no default', () {
      answering(['', '', '2']);
      expect(
        prompt.multiSelect('where', options, label: (v) => v),
        ['fastlane'],
      );
    });

    test('aborts at end of input rather than selecting nothing', () {
      answering([]);
      expect(
        () => prompt.multiSelect('where', options, label: (v) => v),
        throwsA(isA<PromptAbortedException>()),
      );
    });
  });
}

/// Regression cover for the range parser and the review block.
void _multiSelectEdges() {
  late Prompt prompt;
  final original = Prompt.readLine;

  setUp(() {
    ColorizeLogger.logFilePath = '';
    ColorizeLogger.useColors = false;
    ColorizeLogger.verbosity = LogVerbosity.silent;
    prompt = Prompt();
  });
  tearDown(() => Prompt.readLine = original);

  void answering(List<String> answers) {
    final queue = List<String>.from(answers);
    Prompt.readLine = () => queue.isEmpty ? null : queue.removeAt(0);
  }

  group('multiSelect range parsing', () {
    final options = ['a', 'b', 'c'];

    test('a bound larger than int64 re-asks instead of throwing', () {
      // int.parse threw FormatException straight out of the wizard.
      answering(['1-99999999999999999999', '2']);
      expect(prompt.multiSelect('pick', options, label: (v) => v), ['b']);
    });

    test('a reversed overflowing range re-asks', () {
      answering(['99999999999999999999-1', '2']);
      expect(prompt.multiSelect('pick', options, label: (v) => v), ['b']);
    });

    test('a plain number larger than int64 re-asks', () {
      answering(['99999999999999999999', '2']);
      expect(prompt.multiSelect('pick', options, label: (v) => v), ['b']);
    });

    test('a single element range works', () {
      answering(['2-2']);
      expect(prompt.multiSelect('pick', options, label: (v) => v), ['b']);
    });

    test('overlapping ranges de-duplicate', () {
      answering(['1-2,2-3']);
      expect(prompt.multiSelect('pick', options, label: (v) => v), options);
    });
  });

  group('summary', () {
    test('prints each value against a padded key', () {
      final log = File(
        '${Directory.systemTemp.createTempSync('summary').path}/s.log',
      );
      ColorizeLogger.logFilePath = log.path;
      ColorizeLogger.verbosity = LogVerbosity.normal;

      Prompt().summary({'name': 'A', 'key': 'a', 'description': 'd'});

      ColorizeLogger.logFilePath = '';
      ColorizeLogger.verbosity = LogVerbosity.silent;

      final written = log.readAsStringSync();
      expect(written, contains('name'));
      expect(written, contains('description  d'));
    });

    test('omits an entry with no value', () {
      final log = File(
        '${Directory.systemTemp.createTempSync('summary2').path}/s.log',
      );
      ColorizeLogger.logFilePath = log.path;
      ColorizeLogger.verbosity = LogVerbosity.normal;

      Prompt().summary({'name': 'A', 'description': null, 'note': ''});

      ColorizeLogger.logFilePath = '';
      ColorizeLogger.verbosity = LogVerbosity.silent;

      final written = log.readAsStringSync();
      expect(written, contains('name'));
      expect(written, isNot(contains('description')));
      expect(written, isNot(contains('note')));
    });
  });
}
