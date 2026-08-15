import 'package:args/command_runner.dart';
import 'logger.dart';

/// An abstract base class for CLI commands in the distribute CLI.
///
/// The `Commander` class extends the `Command` class from the `args` package
/// and provides a logger instance for logging messages with color support.
/// It automatically configures the logger based on the global verbose flag.
///
/// Commands are typed as `Command<int>` so that every command reports an exit
/// code, which the entry point forwards to the process. Returning `0` means
/// success, any other value marks the invocation as failed.
abstract class Commander extends Command<int> {
  /// Creates a new Commander instance.
  ///
  /// This constructor calls the parent Command constructor to set up
  /// the basic command infrastructure.
  Commander() : super();

  /// The logger used by this command.
  ///
  /// Visibility comes from the process wide [ColorizeLogger.verbosity], which
  /// `main` resolves from `--verbose`, `--quiet` and `--silent`. Commands
  /// constructed outside a runner (tests) therefore log at the default level.
  ColorizeLogger get logger => ColorizeLogger();

  /// The configuration file this command should read.
  ///
  /// A sub-command's own `--config` wins, but only when it was actually typed:
  /// its default would otherwise shadow the global `--config` on every
  /// invocation, which silently made the documented global option do nothing.
  String get configPath {
    final local = argResults;
    if (local != null &&
        local.options.contains('config') &&
        local.wasParsed('config')) {
      return local['config'] as String;
    }
    return (globalResults?['config'] as String?) ?? 'distribution.yaml';
  }
}
