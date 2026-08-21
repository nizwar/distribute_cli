import 'dart:async';
import 'dart:io';

import 'version.dart';

/// Raw ANSI escape sequences used to style terminal output.
///
/// Kept private to the logger: everything user facing goes through the
/// semantic helpers below so the palette can change in one place.
class _Ansi {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String cyan = '\x1B[36m';
  static const String gray = '\x1B[90m';
}

/// Glyphs that prefix a line, with an ASCII fallback.
///
/// Legacy Windows consoles render box drawing and check marks as garbage, so
/// the ASCII set is used whenever colors are unavailable or `DISTRIBUTE_ASCII`
/// is set.
class LogSymbols {
  const LogSymbols._();

  /// Successful outcome.
  static String get success => ColorizeLogger.useUnicode ? '✓' : '+';

  /// Failed outcome.
  static String get failure => ColorizeLogger.useUnicode ? '✗' : 'x';

  /// Something worth attention that is not fatal.
  static String get warning => '!';

  /// A step that is starting.
  static String get step => ColorizeLogger.useUnicode ? '›' : '>';

  /// A top level group, such as a task.
  static String get group => ColorizeLogger.useUnicode ? '▸' : '>';

  /// Separates inline segments, e.g. `2 jobs · 1m 12s`.
  static String get separator => ColorizeLogger.useUnicode ? '·' : '|';
}

/// Renders progress to the terminal and a diagnostic trail to a log file.
///
/// The two outputs are deliberately different. The terminal gets a compact,
/// symbol based view meant to be read while it scrolls:
///
/// ```text
/// ▸ Android Build and deploy
///   › Build Android
///     $ flutter build aab --release --pub
///     ✓ 1m 24s
///       app-release.aab  42.7 MB  9f2a1c0b3d4e
/// ```
///
/// The log file gets a timestamped, level prefixed line per message, which is
/// what you actually want when grepping a failed CI run:
///
/// ```text
/// 12:13:51.140  INFO   Build Android
/// 12:13:51.141  DEBUG  flutter build aab --release --pub
/// ```
///
/// Every message passes through [redact] first, so credentials registered with
/// [registerSecret] never reach either destination - not even when a child
/// process echoes them back.
class ColorizeLogger {
  /// Per-instance request for verbose output.
  ///
  /// Present so a caller can force debug output without touching the global
  /// [verbosity]; the effective value is the more permissive of the two.
  final bool _verboseOverride;

  /// Creates a new ColorizeLogger instance.
  ///
  /// Parameters:
  /// - `isVerbose` - Forces verbose output for this instance
  ColorizeLogger([bool isVerbose = false]) : _verboseOverride = isVerbose;

  /// How much reaches the terminal. The log file always receives everything.
  ///
  /// Set once from the global flags in `main`; every logger instance reads it,
  /// which is what keeps `--quiet` consistent across sub-commands.
  static LogVerbosity verbosity = LogVerbosity.normal;

  /// The verbosity this instance actually logs at.
  ///
  /// A per-instance override can raise the level, but never past `--silent`:
  /// asking for no output has to mean no output.
  LogVerbosity get _effective {
    if (verbosity == LogVerbosity.silent) return LogVerbosity.silent;
    return _verboseOverride ? LogVerbosity.verbose : verbosity;
  }

  /// Whether debug messages are shown.
  bool get isVerbose => _effective.rank >= LogVerbosity.verbose.rank;

  /// Whether [level] reaches the terminal at the current verbosity.
  bool _isVisible(LogLevel level) => _effective.rank >= level.minVerbosity.rank;

  /// The path of the file every log line is appended to.
  ///
  /// Defaults to `distribution.log` in the current working directory and can be
  /// overridden through the global `--log-file` option. Set it to an empty
  /// string to disable file logging entirely.
  static String logFilePath = "distribution.log";

  /// Whether messages are persisted to disk.
  static bool get fileLoggingEnabled => logFilePath.trim().isNotEmpty;

  /// Whether ANSI colors are emitted to the terminal.
  ///
  /// Automatically disabled when stdout is not a terminal (piped output, CI log
  /// capture) or when `NO_COLOR` is set.
  static bool useColors = stdout.supportsAnsiEscapes &&
      !Platform.environment.containsKey('NO_COLOR');

  /// Re-evaluates [useColors] for the stream the human output will use.
  ///
  /// `--json` moves that output to stderr, so a run whose stdout is piped to a
  /// parser while stderr is still a terminal should keep its colours — and the
  /// reverse, a piped stderr should lose them.
  static void retargetColors() {
    if (Platform.environment.containsKey('NO_COLOR')) return;
    useColors =
        reserveStdout ? stderr.supportsAnsiEscapes : stdout.supportsAnsiEscapes;
  }

  /// Whether the unicode glyph set is used instead of the ASCII fallback.
  static bool useUnicode =
      !Platform.environment.containsKey('DISTRIBUTE_ASCII');

  /// Whether stdout is reserved for machine readable output.
  ///
  /// `distribute run --json` writes its report to stdout, so the human readable
  /// log has to move aside for `distribute run --json > report.json` to produce
  /// a parseable file while the operator still sees progress on the terminal.
  /// Errors already go to stderr, so this only relocates the rest.
  static bool reserveStdout = false;

  /// Zone key holding a parallel task's own indentation counter.
  static const Object _zoneIndent = #distributeIndent;

  /// Zone key holding a parallel task's captured output.
  static const Object _zoneSink = #distributeSink;

  /// Indentation depth outside any captured task.
  static int _indentLevel = 0;

  /// Current indentation depth. Each level is two spaces.
  ///
  /// Per-zone when tasks run in parallel: a shared counter would be
  /// incremented by one task while another was writing, and every line would
  /// come out at the wrong depth.
  static int get indentLevel =>
      (Zone.current[_zoneIndent] as _Counter?)?.value ?? _indentLevel;

  static set indentLevel(int value) {
    final scoped = Zone.current[_zoneIndent] as _Counter?;
    if (scoped != null) {
      scoped.value = value;
    } else {
      _indentLevel = value;
    }
  }

  /// Whether the current zone is collecting output instead of printing it.
  static bool get isCapturing => Zone.current[_zoneSink] != null;

  /// Runs [body] with the output indented one extra level.
  static Future<T> group<T>(Future<T> Function() body) async {
    indentLevel++;
    try {
      return await body();
    } finally {
      indentLevel--;
    }
  }

  /// Runs [body] with everything it logs collected into [sink].
  ///
  /// Parallel tasks each get their own buffer, printed as one block when the
  /// task finishes. Interleaving them live would produce a transcript nobody
  /// could read, and the alternative — prefixing every line with a task name —
  /// still cannot keep a multi-line tool error together.
  ///
  /// The log file is unaffected: it is timestamped, so it can carry everything
  /// in the order it actually happened.
  static Future<T> capture<T>(
    StringSink sink,
    Future<T> Function() body,
  ) =>
      runZoned(
        body,
        zoneValues: {
          _zoneSink: sink,
          _zoneIndent: _Counter(indentLevel),
        },
      );

  /// Secret values that must never appear in the terminal or the log file.
  static final Set<String> _secrets = <String>{};

  /// Registers a value that must be masked in every future log line.
  ///
  /// Short values (fewer than 6 characters) and unresolved placeholders such as
  /// `${{TOKEN}}` are ignored: masking them would either redact harmless text or
  /// hide the very placeholder the user needs to see while debugging.
  static void registerSecret(String? value) {
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.length < 6) return;
    if (trimmed.contains(r'${') || trimmed.contains('%{')) return;
    _secrets.add(trimmed);
  }

  /// Replaces every registered secret in [message] with `***`.
  static String redact(String message) {
    if (_secrets.isEmpty) return message;
    var output = message;
    for (final secret in _secrets) {
      output = output.replaceAll(secret, '***');
    }
    return output;
  }

  /// Clears all registered secrets. Intended for tests.
  static void clearSecrets() => _secrets.clear();

  /// Option names whose value is a credential and must never be logged.
  ///
  /// The run header is written before any job has had a chance to register its
  /// secrets, so [redact] cannot help there - the command line has to be masked
  /// on its own.
  static final RegExp _secretOptionPattern = RegExp(
    r'(token|password|passwd|secret|credential|api-key|api-issuer|key-data|ai-key)',
    caseSensitive: false,
  );

  /// Short forms of credential options, by the sub-command that declares them.
  ///
  /// Matching on the letter alone would be wrong: `-p` is the App Store
  /// app-specific password under `publish xcrun`, but the package name under
  /// `create job`. The command has to be part of the decision.
  ///
  /// `test/logger_test.dart` walks the real argument parsers and fails if a
  /// credential option grows an abbreviation that is not listed here.
  static const Map<String, Set<String>> secretAbbreviations = {
    'xcrun': {'p'},
    'fastlane': {'J'},
  };

  /// Renders [arguments] with the value of every credential option masked.
  ///
  /// Handles `--token=value`, `--token value`, `-J value`, `-Jvalue` and
  /// `-J=value`.
  static String maskSecretArguments(List<String> arguments) {
    // The header is written before anything is parsed, so the sub-command is
    // recovered from the raw list.
    final abbreviations = <String>{};
    for (final argument in arguments) {
      final forCommand = secretAbbreviations[argument];
      if (forCommand != null) abbreviations.addAll(forCommand);
    }

    final masked = <String>[];
    var maskNext = false;

    for (final argument in arguments) {
      if (maskNext) {
        masked.add('***');
        maskNext = false;
        continue;
      }

      if (!argument.startsWith('-')) {
        masked.add(argument);
        continue;
      }

      if (!argument.startsWith('--') && abbreviations.isNotEmpty) {
        // A short option, possibly bundled (`-vp secret`) or with the value
        // attached (`-psecret`). Everything after the credential letter is the
        // value, so mask from there on.
        final letters = argument.substring(1);
        final at = letters.split('').indexWhere(abbreviations.contains);
        if (at != -1) {
          final head = '-${letters.substring(0, at + 1)}';
          final tail = letters.substring(at + 1);
          if (tail.isEmpty) {
            masked.add(head);
            maskNext = true;
          } else {
            masked.add('$head***');
          }
          continue;
        }
      }

      final separator = argument.indexOf('=');
      final name =
          separator == -1 ? argument : argument.substring(0, separator);

      if (!_secretOptionPattern.hasMatch(name)) {
        masked.add(argument);
        continue;
      }

      if (separator == -1) {
        masked.add(argument);
        maskNext = true;
      } else {
        masked.add('$name=***');
      }
    }

    return masked.join(' ');
  }

  /// Starts a fresh log file and writes the run header.
  ///
  /// The header carries the full date, the CLI version, the working directory
  /// and the exact invocation, which is what turns a pasted log into a
  /// reproducible bug report. Timestamps on the following lines are time-only,
  /// so the date has to live here.
  ///
  /// Refuses to touch anything that is not a regular file: `--log-file` pointing
  /// at a directory must never delete it.
  static void startLogFile(List<String> arguments) {
    if (!fileLoggingEnabled) return;
    final file = File(logFilePath);

    if (FileSystemEntity.isDirectorySync(logFilePath)) {
      stderr.writeln(
        'Refusing to use "$logFilePath" as a log file: it is a directory.',
      );
      return;
    }

    try {
      if (file.existsSync()) file.deleteSync();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '# distribute_cli $packageVersion\n'
        '# ${DateTime.now().toIso8601String()}\n'
        '# cwd: ${Directory.current.path}\n'
        '# args: ${maskSecretArguments(arguments)}\n',
      );
    } on FileSystemException {
      // Logging to a file is best-effort; never abort the run over it.
    }
  }

  /// Applies [style] to [text], or returns it unchanged when colors are off.
  static String _paint(String text, String style) =>
      useColors ? '$style$text${_Ansi.reset}' : text;

  /// Styles [text] as de-emphasised secondary information.
  static String dim(String text) => _paint(text, _Ansi.gray);

  /// Styles [text] as a heading.
  static String bold(String text) => _paint(text, _Ansi.bold);

  /// Leading whitespace for the current depth.
  ///
  /// Flattened below [LogVerbosity.normal]: once the surrounding context lines
  /// are hidden, indenting the survivors only makes them look truncated.
  String get _indent =>
      verbosity.rank < LogVerbosity.normal.rank ? '' : '  ' * indentLevel;

  /// Matches ANSI escape sequences, including the colors child processes emit.
  static final RegExp _ansiPattern = RegExp(
    r'\x1B(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
  );

  /// Removes every ANSI escape sequence from [text].
  static String stripAnsi(String text) => text.replaceAll(_ansiPattern, '');

  /// Core write path: renders to the terminal and appends to the log file.
  ///
  /// [symbol] and [style] shape the terminal line only; the file always
  /// receives the plain message so it stays greppable.
  ///
  /// [message] is split on newlines because the output of a child process
  /// arrives as arbitrary chunks, not lines: emitting a chunk verbatim would
  /// leave every line after the first without an indent or a log prefix.
  void _emit(
    String message, {
    required LogLevel level,
    String? symbol,
    String? style,
    int extraIndent = 0,
  }) {
    final safe = redact(message);
    // Trailing newlines would otherwise become spurious blank entries; a child
    // process almost always terminates its chunk with one.
    final lines = _splitLines(safe);
    if (lines.isEmpty) return;

    if (_isVisible(level)) {
      final flat = verbosity.rank < LogVerbosity.normal.rank;
      final pad = _indent + (flat ? '' : '  ' * extraIndent);
      final captured = Zone.current[_zoneSink] as StringSink?;
      final sink =
          captured ?? ((level.isError || reserveStdout) ? stderr : stdout);
      // The spinner owns a line that is being overwritten in place. Anything
      // printed while it is running has to erase it first, or the two end up
      // spliced together on the same row.
      if (captured == null) Spinner.active?.erase();
      // Continuation lines are aligned under the text, not under the symbol.
      final continuation = symbol == null ? '' : ' ' * (symbol.length + 1);

      for (var i = 0; i < lines.length; i++) {
        final rendered = useColors ? lines[i] : stripAnsi(lines[i]);
        final prefix = i > 0
            ? continuation
            : symbol == null
                ? ''
                : '${style == null ? symbol : _paint(symbol, style)} ';
        final body = style == null ? rendered : _paint(rendered, style);
        sink.writeln('$pad$prefix$body');
      }
      if (captured == null) Spinner.active?.paint();
    }

    _append(lines, level);
  }

  /// Splits [message] into lines, dropping trailing blank ones.
  static List<String> _splitLines(String message) {
    final lines = message.split('\n');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  /// Appends one timestamped record per line to the log file, best effort.
  ///
  /// ANSI codes are stripped here unconditionally: a log file full of escape
  /// sequences is neither greppable nor readable in an editor.
  void _append(List<String> lines, LogLevel level) {
    if (!fileLoggingEnabled) return;

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
        '.${now.millisecond.toString().padLeft(3, '0')}';
    final label = level.label.padRight(5);

    final buffer = StringBuffer();
    for (final line in lines) {
      buffer.writeln('$stamp  $label  ${stripAnsi(line)}');
    }

    try {
      File(logFilePath).writeAsStringSync(
        buffer.toString(),
        mode: FileMode.append,
      );
    } on FileSystemException {
      // The log file is best-effort: a read-only working directory or a locked
      // file must never abort the build.
    }
  }

  /// Logs a message with the specified level.
  ///
  /// Retained for callers that select the level dynamically; prefer the
  /// semantic helpers below.
  void log(String message, {LogLevel level = LogLevel.info}) {
    switch (level) {
      case LogLevel.success:
        logSuccess(message);
      case LogLevel.warning:
        logWarning(message);
      case LogLevel.error:
        logError(message);
      case LogLevel.errorVerbose:
        logErrorVerbose(message);
      case LogLevel.debug:
        logDebug(message);
      case LogLevel.info:
        logInfo(message);
    }
  }

  /// Logs a failure, prefixed with `✗` in red.
  void logError(String message) => _emit(
        message,
        level: LogLevel.error,
        symbol: LogSymbols.failure,
        style: _Ansi.red,
      );

  /// Logs a failure that is only shown with `--verbose`.
  void logErrorVerbose(String message) => _emit(
        message,
        level: LogLevel.errorVerbose,
        style: _Ansi.red,
      );

  /// Logs a warning, prefixed with `!` in yellow.
  void logWarning(String message) => _emit(
        message,
        level: LogLevel.warning,
        symbol: LogSymbols.warning,
        style: _Ansi.yellow,
      );

  /// Logs a success, prefixed with `✓` in green.
  void logSuccess(String message) => _emit(
        message,
        level: LogLevel.success,
        symbol: LogSymbols.success,
        style: _Ansi.green,
      );

  /// Logs a neutral message with no prefix and no color.
  ///
  /// Plain by design: when everything is highlighted, nothing is.
  void logInfo(String message) => _emit(message, level: LogLevel.info);

  /// Logs a debug message, shown only with `--verbose`.
  void logDebug(String message) =>
      _emit(message, level: LogLevel.debug, style: _Ansi.gray);

  /// Announces a step that is starting, prefixed with `›` in bold cyan.
  void logStep(String message) => _emit(
        message,
        level: LogLevel.info,
        symbol: LogSymbols.step,
        style: '${_Ansi.bold}${_Ansi.cyan}',
      );

  /// Announces a group such as a task, prefixed with `▸` in bold.
  void logGroup(String message) => _emit(
        message,
        level: LogLevel.info,
        symbol: LogSymbols.group,
        style: _Ansi.bold,
      );

  /// Logs de-emphasised information that hangs off the line above it.
  ///
  /// Indented one extra level, so artifacts read as belonging to the result
  /// they were produced by.
  void logDetail(String message) => _emit(
        message,
        level: LogLevel.info,
        style: _Ansi.gray,
        extraIndent: 1,
      );

  /// Logs a de-emphasised aside at the current level.
  ///
  /// Use for remarks that stand on their own rather than qualifying the
  /// previous line - those belong in [logDetail].
  void logNote(String message) =>
      _emit(message, level: LogLevel.info, style: _Ansi.gray);

  /// Logs the command that is about to run, as a shell-style `$` line.
  void logCommand(String command) => _emit(
        '\$ $command',
        level: LogLevel.info,
        style: _Ansi.gray,
      );

  /// Logs a bold section heading.
  void logHeading(String message) =>
      _emit(message, level: LogLevel.info, style: _Ansi.bold);

  /// Logs an empty line to separate blocks. Never written to the log file.
  ///
  /// Suppressed below [LogVerbosity.normal]: a `--quiet` run should be a dense
  /// list of errors, not a page of blank lines.
  void logEmpty() {
    if (!_isVisible(LogLevel.info)) return;
    final captured = Zone.current[ColorizeLogger._zoneSink] as StringSink?;
    if (captured != null) {
      captured.writeln('');
      return;
    }
    Spinner.active?.erase();
    (ColorizeLogger.reserveStdout ? stderr : stdout).writeln('');
    Spinner.active?.paint();
  }
}

/// How much of the log reaches the terminal.
///
/// Chosen once from the global flags. The log file is unaffected: it always
/// records every message, which is what makes `--silent` safe to use in CI -
/// nothing is printed, but the full trail is still on disk.
enum LogVerbosity {
  /// Print nothing at all; the exit code is the only signal.
  silent(0),

  /// Print failures only.
  quiet(1),

  /// Print failures, warnings and progress. The default.
  normal(2),

  /// Also print diagnostic detail and the raw output of child processes.
  verbose(3);

  /// Ordering rank; higher means more output.
  final int rank;

  /// Creates a verbosity with its [rank].
  const LogVerbosity(this.rank);

  /// Resolves the verbosity implied by the global flags.
  ///
  /// `--silent` wins over `--quiet`, which wins over `--verbose`, so the most
  /// restrictive flag the user typed is always honoured.
  static LogVerbosity fromFlags({
    bool silent = false,
    bool quiet = false,
    bool verbose = false,
  }) {
    if (silent) return LogVerbosity.silent;
    if (quiet) return LogVerbosity.quiet;
    if (verbose) return LogVerbosity.verbose;
    return LogVerbosity.normal;
  }
}

/// Severity of a log message.
///
/// The level drives the log file prefix and the minimum verbosity at which the
/// message reaches the terminal; the visual treatment is chosen by the helper
/// that emits it.
enum LogLevel {
  /// Neutral progress information.
  info('INFO', LogVerbosity.normal),

  /// Something worth attention that is not fatal.
  warning('WARN', LogVerbosity.normal),

  /// A step completed successfully.
  success('OK', LogVerbosity.normal),

  /// Diagnostic detail, shown only with `--verbose`.
  debug('DEBUG', LogVerbosity.verbose),

  /// A failure. Survives `--quiet`; only `--silent` hides it.
  error('ERROR', LogVerbosity.quiet),

  /// A failure detail that is only surfaced with `--verbose`.
  errorVerbose('ERROR', LogVerbosity.verbose);

  /// Fixed width label written to the log file.
  final String label;

  /// Lowest verbosity at which this level is still printed.
  final LogVerbosity minVerbosity;

  /// Creates a level carrying its log file [label] and visibility threshold.
  const LogLevel(this.label, this.minVerbosity);

  /// Whether messages of this level belong on stderr instead of stdout.
  bool get isError => this == LogLevel.error || this == LogLevel.errorVerbose;
}

/// A single line that animates in place while a long step is running.
///
/// Builds and uploads spend minutes producing nothing on screen — flutter's own
/// output only appears under `--verbose` — so without this the CLI looks hung.
/// The spinner replaces that silence with a frame, the step's name and a live
/// elapsed time, rewritten on one row.
///
/// It deliberately refuses to run in the places where an animation is wrong:
///
/// - no terminal (piped output, CI logs) — the escape codes would be captured
///   verbatim and every tick would become another line in the log
/// - `--quiet` and `--silent`, which asked for less output, not more
/// - `--verbose`, where the tool's own output is streaming and would be
///   interleaved with the animation
///
/// Nothing it draws reaches the log file: the file is the record, and a record
/// of an animation is noise.
class Spinner {
  /// The spinner currently drawing, if any.
  ///
  /// Only one runs at a time — steps are sequential — and [ColorizeLogger]
  /// consults it before printing so the two never share a row.
  static Spinner? active;

  /// Frames of the animation, unicode with an ASCII fallback.
  static List<String> get _frames => ColorizeLogger.useUnicode
      ? const ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
      : const ['-', '\\', '|', '/'];

  /// How often the frame advances.
  static const Duration interval = Duration(milliseconds: 90);

  /// Label shown next to the frame.
  final String label;

  /// Recomputes the label on every frame, when the caller has something that
  /// changes — the set of tasks currently running, for instance.
  final String Function()? describe;

  /// Indentation captured when the spinner started.
  final String _pad;

  Timer? _timer;
  final Stopwatch _elapsed = Stopwatch();
  int _frame = 0;
  int _painted = 0;
  bool _running = false;

  Spinner._(this.label, this._pad, this.describe);

  /// Where the animation is drawn. Replaced in tests.
  static StringSink Function() sink =
      () => ColorizeLogger.reserveStdout ? stderr : stdout;

  /// Whether that destination can show an animation. Replaced in tests.
  static bool Function() isTerminal =
      () => (ColorizeLogger.reserveStdout ? stderr : stdout).hasTerminal;

  /// Restores the production destination. Intended for tests.
  static void resetOutput() {
    sink = () => ColorizeLogger.reserveStdout ? stderr : stdout;
    isTerminal =
        () => (ColorizeLogger.reserveStdout ? stderr : stdout).hasTerminal;
  }

  /// Whether an animation is appropriate for the current output.
  static bool get supported {
    if (ColorizeLogger.verbosity != LogVerbosity.normal) return false;
    // A captured task's output is a buffer printed later; an animation in it
    // would arrive as a screenful of escape codes long after the fact.
    if (ColorizeLogger.isCapturing) return false;
    return isTerminal();
  }

  /// Runs [body] with a spinner labelled [label].
  ///
  /// The spinner is always stopped, including when [body] throws, so a failure
  /// never leaves a half-drawn line on the terminal.
  static Future<T> run<T>(
    String label,
    Future<T> Function() body, {
    String Function()? describe,
  }) async {
    if (!supported || active != null) return body();

    final spinner =
        Spinner._(label, '  ' * ColorizeLogger.indentLevel, describe);
    active = spinner;
    spinner._start();
    try {
      return await body();
    } finally {
      spinner._stop();
      active = null;
    }
  }

  void _start() {
    _running = true;
    _elapsed.start();
    paint();
    _timer = Timer.periodic(interval, (_) {
      _frame = (_frame + 1) % _frames.length;
      paint();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _elapsed.stop();
    erase();
    _running = false;
  }

  /// Draws the current frame, replacing whatever the spinner drew last.
  void paint() {
    if (!_running) return;

    final plain = '$_pad${_frames[_frame]} ${describe?.call() ?? label}  '
        '${_format(_elapsed.elapsed)}';
    // A line wider than the pane wraps, and `\r` only returns to the start of
    // the *last* row — so the erase would miss everything above it and every
    // repaint would scroll another row. Truncating keeps the animation on one
    // line, which is the only shape it can clean up after.
    final trimmed = plain.length <= _columns
        ? plain
        : '${plain.substring(0, _columns - 1)}…';

    sink().write('\r${_styled(trimmed)}');
    // Remembered so the next erase clears exactly this many columns; a shorter
    // following line would otherwise leave the tail of this one behind.
    _painted = trimmed.length;
  }

  /// Re-applies the dim styling to the elapsed time inside [line].
  String _styled(String line) {
    if (!ColorizeLogger.useColors) return line;
    final split = line.lastIndexOf('  ');
    if (split == -1) return line;
    return line.substring(0, split + 2) +
        ColorizeLogger.dim(line.substring(split + 2));
  }

  /// Usable width, with a floor so a nonsensical value cannot break the maths.
  static int get _columns {
    try {
      final width = stdout.terminalColumns;
      return width < 20 ? 20 : width - 1;
    } on StdoutException {
      // No terminal to ask; the spinner is not drawn there anyway.
      return 80;
    }
  }

  /// Removes the spinner's line, leaving the cursor at the start of the row.
  void erase() {
    if (_painted == 0) return;
    sink().write('\r${' ' * _painted}\r');
    _painted = 0;
  }

  /// `1.4s`, `12s`, `2m 05s` — short enough not to jitter the line width.
  static String _format(Duration duration) {
    if (duration.inSeconds < 10) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    if (duration.inMinutes < 1) return '${duration.inSeconds}s';
    final seconds = duration.inSeconds % 60;
    return '${duration.inMinutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}

/// A mutable integer held in a zone, so each parallel task owns its own depth.
class _Counter {
  int value;
  _Counter(this.value);
}
