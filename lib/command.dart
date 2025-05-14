import 'package:args/command_runner.dart';
import 'logger.dart';

/// An abstract base class for CLI commands.
///
/// The [Commander] class extends the [Command] class from the `args` package
/// and provides a logger instance for logging messages, as well as
/// convenience methods for verbose and error logging.
abstract class Commander extends Command {
  /// Creates a new [Commander] instance.
  Commander() : super();

  /// The logger instance for logging messages.
  ColorizeLogger get logger =>
      ColorizeLogger(globalResults?['verbose'] ?? false);

  /// Logs a verbose message using the logger.
  void onVerbose(String message) => logger.logDebug(message);

  /// Logs an error message using the logger.
  void onError(String message) => logger.logError(message);
}
