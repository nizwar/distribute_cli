import 'dart:io';

/// A utility class for logging messages with ANSI color codes.
///
/// The `ColorizeLogger` class provides methods to log messages with different
/// log levels, such as error, warning, success, info, and debug. Each log level
/// is associated with a specific color for better visibility in the terminal.
///
/// Example usage:
/// ```dart
/// final logger = ColorizeLogger(true);
/// logger.logInfo("This is an informational message.");
/// logger.logError("This is an error message.");
/// ```
///
/// The logger writes messages to both the terminal and a log file named `distribution.log`.
/// Verbose logging can be controlled via the provided `isVerbose` flag.
class ColorizeLogger {
  /// Whether verbose logging is enabled
  /// - When `true` - Shows all messages including debug messages
  /// - When `false` - Hides debug and verbose error messages
  final bool isVerbose;

  /// Creates a new ColorizeLogger instance.
  ///
  /// Parameters:
  /// - `isVerbose` - Controls whether verbose logging is enabled
  ColorizeLogger(this.isVerbose);

  /// ANSI reset code to reset terminal colors back to default
  final String _reset = '\x1B[0m';

  /// Logs a message with the specified level and color.
  ///
  /// This method handles the core logging logic, determining whether to display
  /// the message based on the verbose setting and log level.
  ///
  /// Parameters:
  /// - `message` - The message to log
  /// - `level` - The log level (defaults to info)
  ///
  /// Behavior:
  /// - Always writes to `distribution.log` file
  /// - Shows in terminal based on verbose setting and log level
  void log(String message, {LogLevel level = LogLevel.info}) async {
    if (isVerbose) {
      stdout.writeln('${level.color}$message$_reset');
    } else {
      if (level != LogLevel.debug && level != LogLevel.errorVerbose) {
        stdout.writeln('${level.color}$message$_reset');
      }
    }
    File("distribution.log")
        .writeAsStringSync("$message\n", mode: FileMode.append);
  }

  /// Logs an error message in red color with `[ERROR]` prefix.
  ///
  /// Parameters:
  /// - `message` - The error message to display
  void logError(String message) =>
      log("[ERROR] $message", level: LogLevel.error);

  /// Logs a verbose error message in red color with `[ERROR]` prefix.
  /// Only shown when verbose logging is enabled.
  ///
  /// Parameters:
  /// - `message` - The error message to display
  void logErrorVerbose(String message) =>
      log("[ERROR] $message", level: LogLevel.errorVerbose);

  /// Logs a warning message in yellow color with `[WARNING]` prefix.
  ///
  /// Parameters:
  /// - `message` - The warning message to display
  void logWarning(String message) =>
      log("[WARNING] $message", level: LogLevel.warning);

  /// Logs a success message in green color with `[SUCCESS]` prefix.
  ///
  /// Parameters:
  /// - `message` - The success message to display
  void logSuccess(String message) =>
      log("[SUCCESS] $message", level: LogLevel.success);

  /// Logs an informational message in orange color with `[INFO]` prefix.
  ///
  /// Parameters:
  /// - `message` - The informational message to display
  void logInfo(String message) => log("[INFO] $message", level: LogLevel.info);

  /// Logs a debug message with `[VERBOSE]` prefix.
  /// Only shown when verbose logging is enabled.
  ///
  /// Parameters:
  /// - `message` - The debug message to display
  void logDebug(String message) =>
      log("[VERBOSE] $message", level: LogLevel.debug);

  /// Logs an empty line to stdout for better message separation.
  void logEmpty() {
    stdout.writeln('');
  }
}

/// Represents the log levels with associated ANSI color codes.
///
/// The `LogLevel` enum defines different log levels with specific
/// ANSI color codes for better visibility in the terminal.
///
/// Available levels:
/// - `info` - Orange color for informational messages
/// - `warning` - Yellow color for warning messages
/// - `success` - Green color for success messages
/// - `debug` - Default color for debug messages
/// - `error` - Red color for error messages
/// - `errorVerbose` - Red color for verbose error messages
enum LogLevel {
  /// Informational log level with orange color
  info('\x1B[33m'),

  /// Warning log level with yellow color
  warning('\x1B[33m'),

  /// Success log level with green color
  success('\x1B[32m'),

  /// Debug log level with default terminal color
  debug('\x1B[0m'),

  /// Error log level with red color
  error('\x1B[31m'),

  /// Error log level with red color for verbose output
  errorVerbose('\x1B[31m');

  /// The ANSI color code for this log level
  final String color;

  /// Creates a new LogLevel with the given ANSI color code.
  ///
  /// Parameters:
  /// - `color` - The ANSI escape sequence for the color
  const LogLevel(this.color);
}
