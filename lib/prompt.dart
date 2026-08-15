import 'dart:io';

import 'logger.dart';

/// Thrown when a wizard runs out of input before it has an answer.
///
/// Reaching end-of-input is not a crash: it is what happens when a wizard is
/// started from CI, from a pipe, or when the user presses Ctrl-D. Without it a
/// re-asking prompt would spin forever on a stream that can never answer.
class PromptAbortedException implements Exception {
  /// What the user should do instead.
  final String message;

  /// Creates an abort carrying an actionable [message].
  const PromptAbortedException([
    this.message = 'no input available; pass the values as options instead '
        'of using the wizard',
  ]);

  @override
  String toString() => message;
}

/// Interactive prompts for the CLI's wizards.
///
/// Kept in one place so every wizard asks questions the same way: a dim hint
/// for the default, numbered menus instead of free-text matching, and a
/// best-effort attempt to keep secrets off the screen — see [secret], which
/// warns rather than fails where the terminal will not disable echo.
class Prompt {
  final ColorizeLogger _logger;

  /// Creates a prompt bound to [logger] for its non-question output.
  Prompt([ColorizeLogger? logger]) : _logger = logger ?? ColorizeLogger();

  /// Whether the terminal can answer questions at all.
  ///
  /// A wizard invoked from CI has no one to ask; callers check this and fail
  /// with an actionable message rather than blocking on a read that never
  /// returns.
  static bool get isInteractive => stdin.hasTerminal;

  /// Source of a single line of input. Replaced in tests to drive a wizard.
  ///
  /// Returning null means end-of-input, exactly as `stdin.readLineSync` does.
  static String? Function() readLine = () => stdin.readLineSync();

  /// Reads one line, treating end-of-input as an abort rather than an answer.
  ///
  /// `readLineSync` returns null once the stream is closed and keeps returning
  /// null, so every re-asking loop below has to stop on it.
  static String _readLine() {
    final line = readLine();
    if (line == null) throw const PromptAbortedException();
    return line;
  }

  /// Asks for a line of text.
  ///
  /// Returns [defaultValue] when the user just presses enter. Re-asks while the
  /// answer is empty and no default exists.
  ///
  /// [validate] returns an error message to reject an answer, or null to accept
  /// it. Rejecting here rather than after the last question is the difference
  /// between retyping one field and retyping the whole wizard.
  String text(
    String question, {
    String? defaultValue,
    bool allowEmpty = false,
    String? Function(String)? validate,
  }) {
    while (true) {
      final hint = defaultValue == null || defaultValue.isEmpty
          ? ''
          : ' ${ColorizeLogger.dim('($defaultValue)')}';
      stdout.write('${ColorizeLogger.bold('?')} $question$hint ');
      final typed = _readLine().trim();

      final String answer;
      if (typed.isNotEmpty) {
        answer = typed;
      } else if (defaultValue != null && defaultValue.isNotEmpty) {
        answer = defaultValue;
      } else if (allowEmpty) {
        // `allowEmpty` says nothing is a valid answer, so there is nothing for
        // [validate] to judge — running it here would let the two options
        // contradict each other.
        return '';
      } else {
        _logger.logWarning('a value is required');
        continue;
      }

      final problem = validate?.call(answer);
      if (problem == null) return answer;
      _logger.logWarning(problem);
    }
  }

  /// Asks for a secret, with terminal echo disabled while typing.
  ///
  /// Echo is restored in a `finally` so a Ctrl-C mid-answer cannot leave the
  /// user's terminal silently unable to display input.
  String secret(String question, {bool allowEmpty = false}) {
    while (true) {
      stdout.write('${ColorizeLogger.bold('?')} $question ');

      // Echo control is best effort. `stdin.echoMode` throws on anything that
      // is not a real terminal — a pipe, a CI runner, a test harness — and
      // `hasTerminal` does not reliably predict it, so the only way to know is
      // to try. Failing here would hide the abort that actually explains the
      // problem, so the read goes ahead either way.
      bool? hadEcho;
      try {
        hadEcho = stdin.echoMode;
        stdin.echoMode = false;
      } on StdinException {
        _logger.logWarning('cannot hide input here; what you type is visible');
      }

      String answer;
      try {
        answer = _readLine().trim();
      } finally {
        if (hadEcho != null) {
          try {
            stdin.echoMode = hadEcho;
          } on StdinException {
            // Nothing to restore if the terminal went away mid-answer.
          }
        }
        stdout.writeln();
      }

      if (answer.isNotEmpty || allowEmpty) return answer;
      _logger.logWarning('a value is required');
    }
  }

  /// Asks a yes/no question.
  bool confirm(String question, {bool defaultValue = true}) {
    final hint = defaultValue ? 'Y/n' : 'y/N';
    while (true) {
      stdout.write(
        '${ColorizeLogger.bold('?')} $question ${ColorizeLogger.dim('($hint)')} ',
      );
      final answer = _readLine().trim().toLowerCase();

      if (answer.isEmpty) return defaultValue;
      if (answer == 'y' || answer == 'yes') return true;
      if (answer == 'n' || answer == 'no') return false;
      _logger.logWarning('answer y or n');
    }
  }

  /// Asks the user to pick one of [options] from a numbered list.
  ///
  /// Numbered selection rather than typed names: it cannot be misspelled, and
  /// it shows every valid answer without the user having to know them.
  T select<T>(
    String question,
    List<T> options, {
    required String Function(T) label,
    String Function(T)? describe,
    int defaultIndex = 0,
  }) {
    _logger.logInfo('${ColorizeLogger.bold('?')} $question');
    for (var i = 0; i < options.length; i++) {
      final marker = i == defaultIndex ? '›' : ' ';
      final description = describe?.call(options[i]);
      _logger.logInfo(
        '  $marker ${i + 1}) ${label(options[i])}'
        '${description == null ? '' : '  ${ColorizeLogger.dim(description)}'}',
      );
    }

    while (true) {
      stdout.write(
        '  ${ColorizeLogger.dim('1-${options.length} (${defaultIndex + 1})')} ',
      );
      final answer = _readLine().trim();
      if (answer.isEmpty) return options[defaultIndex];

      final index = int.tryParse(answer);
      if (index != null && index >= 1 && index <= options.length) {
        return options[index - 1];
      }
      _logger.logWarning('enter a number between 1 and ${options.length}');
    }
  }

  /// Asks the user to pick any number of [options] from a numbered list.
  ///
  /// Accepts comma or space separated numbers, ranges like `1-3`, and `all`.
  /// Answering nothing takes [defaults]; when there are no defaults the
  /// question is asked again, because an empty selection is never what the
  /// caller wanted — a job with no platform cannot be built.
  List<T> multiSelect<T>(
    String question,
    List<T> options, {
    required String Function(T) label,
    String Function(T)? describe,
    List<T> defaults = const [],
  }) {
    _logger.logInfo('${ColorizeLogger.bold('?')} $question');
    for (var i = 0; i < options.length; i++) {
      final marker = defaults.contains(options[i]) ? '›' : ' ';
      final description = describe?.call(options[i]);
      _logger.logInfo(
        '  $marker ${i + 1}) ${label(options[i])}'
        '${description == null ? '' : '  ${ColorizeLogger.dim(description)}'}',
      );
    }

    final hint = defaults.isEmpty
        ? '1-${options.length}, comma separated, or "all"'
        : '1-${options.length} or "all" '
            '(${defaults.map((d) => options.indexOf(d) + 1).join(',')})';

    while (true) {
      stdout.write('  ${ColorizeLogger.dim(hint)} ');
      final answer = _readLine().trim().toLowerCase();

      if (answer.isEmpty) {
        if (defaults.isNotEmpty) return List<T>.from(defaults);
        _logger.logWarning('pick at least one');
        continue;
      }
      if (answer == 'all' || answer == 'a' || answer == '*') {
        return List<T>.from(options);
      }

      final picked = _parseIndexes(answer, options.length);
      if (picked == null) {
        _logger.logWarning(
          'use numbers between 1 and ${options.length}, e.g. "1,3" or "1-2"',
        );
        continue;
      }
      if (picked.isEmpty) {
        _logger.logWarning('pick at least one');
        continue;
      }
      return picked.map((i) => options[i]).toList();
    }
  }

  /// Parses `1,3` and `1-2` into zero based indexes, or null when malformed.
  ///
  /// Returns null rather than skipping a bad token: silently dropping part of
  /// a selection would build a job the user did not ask for.
  static List<int>? _parseIndexes(String answer, int length) {
    final picked = <int>{};
    for (final token in answer.split(RegExp(r'[,\s]+'))) {
      if (token.isEmpty) continue;

      final range = RegExp(r'^(\d+)-(\d+)$').firstMatch(token);
      if (range != null) {
        // tryParse, not parse: a token with more than nineteen digits overflows
        // int64 and would throw straight out of the wizard, discarding every
        // answer already given. An unparseable bound is just a bad answer.
        final from = int.tryParse(range.group(1)!);
        final to = int.tryParse(range.group(2)!);
        if (from == null || to == null) return null;
        if (from < 1 || to > length || from > to) return null;
        for (var i = from; i <= to; i++) {
          picked.add(i - 1);
        }
        continue;
      }

      final index = int.tryParse(token);
      if (index == null || index < 1 || index > length) return null;
      picked.add(index - 1);
    }
    final sorted = picked.toList()..sort();
    return sorted;
  }

  /// Prints a `key  value` block, used to review answers before committing.
  void summary(Map<String, String?> values) {
    final width = values.keys
        .map((key) => key.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null || value.isEmpty) continue;
      _logger.logInfo(
        '  ${ColorizeLogger.dim(entry.key.padRight(width))}  $value',
      );
    }
  }
}
