import 'dart:io';

/// A utility class for logging messages with ANSI color codes.
///
/// The `ColorizeLogger` class provides methods to log messages with different
/// log levels, such as error, warning, success, info, and debug. Each log level
/// is associated with a specific color for better visibility in the terminal.
///
/// Example usage:
/// ```dart
/// final logger = ColorizeLogger(environment);
/// logger.logInfo("This is an informational message.");
/// logger.logError("This is an error message.");
/// ```
///
/// The logger writes messages to both the terminal and a log file named `distribution.log`.
/// Verbose logging can be controlled via the provided [Environment] instance.
class ColorizeLogger {
  /// The current environment configuration
  final bool isVerbose;

  /// Initializes the `ColorizeLogger` with the given [environment].
  /// The [environment] parameter is used to determine if verbose logging is enabled.
  /// If verbose logging is enabled, all log messages will be displayed.
  ColorizeLogger(this.isVerbose);

  /// ANSI reset code to reset terminal colors.
  final String _reset = '\x1B[0m';

  /// Logs a message with the specified [color].
  void log(String message, {LogLevel color = LogLevel.info}) {
    if ((isVerbose || color != LogLevel.debug) && message.trim().isNotEmpty) {
      stdout.writeln('${color.color}$message$_reset');
    }
    File("distribution.log").writeAsStringSync("$message\n", mode: FileMode.append);
  }

  /// Logs an error message in red.
  void logError(String message) => log("[ERROR] $message", color: LogLevel.error);
  void logErrorVerbose(String message) => log("[ERROR] $message", color: LogLevel.errorVerbose);

  /// Logs a warning message in yellow.
  void logWarning(String message) => log("[WARNING] $message", color: LogLevel.warning);

  /// Logs a success message in green.
  void logSuccess(String message) => log("[SUCCESS] $message", color: LogLevel.success);

  /// Logs an informational message in green.
  void logInfo(String message) => log("[INFO] $message", color: LogLevel.info);

  /// Logs a debug message in the default terminal color.
  void logDebug(String message) => log("[VERBOSE] $message", color: LogLevel.debug);

  void logEmpty() {
    stdout.writeln('');
  }
}

/// Represents the log levels with associated ANSI color codes.
///
/// The `LogLevel` enum defines different log levels, such as `info`, `warning`,
/// `success`, `debug`, and `error`. Each log level is associated with a specific
/// ANSI color code for better visibility in the terminal.
enum LogLevel {
  /// Informational log level with orange color.
  info('\x1B[33m'),

  /// Warning log level with yellow color.
  warning('\x1B[33m'),

  /// Success log level with green color.
  success('\x1B[32m'),

  /// Debug log level with default terminal color.
  debug('\x1B[0m'),

  /// Error log level with red color.
  error('\x1B[31m'),

  /// Error log level with red color.
  errorVerbose('\x1B[31m');

  /// The ANSI color code for the log level.
  final String color;

  /// Constructor for the `LogLevel` enum.
  const LogLevel(this.color);
}
