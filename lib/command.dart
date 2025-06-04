import 'package:args/command_runner.dart';
import 'logger.dart';

/// An abstract base class for CLI commands in the distribute CLI.
///
/// The `Commander` class extends the `Command` class from the `args` package
/// and provides a logger instance for logging messages with color support.
/// It automatically configures the logger based on the global verbose flag.
abstract class Commander extends Command {
  /// Creates a new Commander instance.
  ///
  /// This constructor calls the parent Command constructor to set up
  /// the basic command infrastructure.
  Commander() : super();

  /// The logger instance for logging messages with color support.
  ///
  /// The logger is automatically configured based on the global `--verbose` flag.
  /// When verbose is enabled, debug messages will be shown.
  ///
  /// Returns a ColorizeLogger instance configured with the current verbose setting.
  ColorizeLogger get logger =>
      ColorizeLogger(globalResults?['verbose'] ?? false);
}
