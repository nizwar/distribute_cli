import 'package:args/command_runner.dart';
import 'package:distribute_cli/logger.dart';

/// An abstract base class for CLI commands.
///
/// The `Commander` class extends the `Command` class from the `args` package
/// and provides a logger instance for logging messages.
abstract class Commander extends Command {
  /// The logger instance for logging messages.
  ColorizeLogger get logger => ColorizeLogger(globalResults?['verbose'] ?? false);

  void onVerbose(String message) => logger.logDebug(message);
  void onError(String message) => logger.logError(message);
}
