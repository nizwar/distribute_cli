import 'dart:io';

/// A utility class for logging messages with ANSI color codes.
///
/// The `ColorizeLogger` class provides methods to log messages with different
/// log levels, such as error, warning, success, info, and debug. Each log level
/// is associated with a specific color for better visibility in the terminal.
///
/// Example usage:
/// ```
/// ColorizeLogger.logInfo("This is an informational message.");
/// ColorizeLogger.logError("This is an error message.");
/// ```
class ColorizeLogger {
  /// ANSI reset code to reset terminal colors.
  static const String _reset = '\x1B[0m';

  /// Logs a message with the specified [color].
  static void log(String message, {LogLevel color = LogLevel.info}) {
    stdout.writeln('${color.color}$message$_reset');
    File("distribution.log")
        .writeAsStringSync("$message\n", mode: FileMode.append);
  }

  /// Logs an error message in red.
  static void logError(String message) => log(message, color: LogLevel.error);

  /// Logs a warning message in yellow.
  static void logWarning(String message) =>
      log(message, color: LogLevel.warning);

  /// Logs a success message in green.
  static void logSuccess(String message) =>
      log(message, color: LogLevel.success);

  /// Logs an informational message in green.
  static void logInfo(String message) => log(message, color: LogLevel.info);

  /// Logs a debug message in the default terminal color.
  static void logDebug(String message) => log(message, color: LogLevel.debug);
}

/// Represents the log levels with associated ANSI color codes.
///
/// The `LogLevel` enum defines different log levels, such as `info`, `warning`,
/// `success`, `debug`, and `error`. Each log level is associated with a specific
/// ANSI color code for better visibility in the terminal.
enum LogLevel {
  /// Informational log level with green color.
  info('\x1B[32m'),

  /// Warning log level with yellow color.
  warning('\x1B[33m'),

  /// Success log level with green color.
  success('\x1B[32m'),

  /// Debug log level with default terminal color.
  debug('\x1B[0m'),

  /// Error log level with red color.
  error('\x1B[31m');

  /// The ANSI color code for the log level.
  final String color;
  const LogLevel(this.color);
}
