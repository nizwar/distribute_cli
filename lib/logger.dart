import 'dart:io';

class ColorizeLogger {
  static const String _reset = '\x1B[0m';

  static void log(String message, {LogLevel color = LogLevel.info}) {
    stdout.writeln('${color.color}$message$_reset');
  }

  static void logError(String message) {
    log(message, color: LogLevel.error);
  }

  static void logWarning(String message) {
    log(message, color: LogLevel.warning);
  }

  static void logSuccess(String message) {
    log(message, color: LogLevel.success);
  }

  static void logInfo(String message) {
    log(message, color: LogLevel.info);
  }

  static void logDebug(String message) {
    log(message, color: LogLevel.debug);
  }
}

enum LogLevel {
  info('\x1B[32m'),
  warning('\x1B[33m'),
  success('\x1B[32m'),
  debug('\x1B[0m'),
  error('\x1B[31m');

  final String color;
  const LogLevel(this.color);
}
