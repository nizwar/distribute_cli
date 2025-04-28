import 'package:args/command_runner.dart';
import 'package:distribute_cli/builder.dart';
import 'package:distribute_cli/initializer.dart';

import 'package:distribute_cli/publisher.dart';

/// The entry point for the `distribute` CLI application.
///
/// This script sets up a `CommandRunner` to handle various commands related
/// to distributing app packages. It includes options for specifying a
/// configuration file path, enabling verbose output, and enabling process logs.
///
/// The following commands are added to the runner:
/// - `InitCommand`: Initializes the distribution process.
/// - `Builder`: Handles the building of app packages.
/// - `Publisher`: Manages the publishing of app packages.
///
/// ### Options:
/// - `--config_path`: Specifies the path to the configuration file. Defaults to `.distribution.env`.
/// - `--verbose` (`-v`): Enables verbose output. Defaults to `false`.
/// - `--process_logs` (`-l`): Enables process logs. Defaults to `false`.
///
/// ### Usage:
/// Run the CLI with the desired command and options:
/// ```bash
/// dart distribute_cli.dart <command> [options]
/// ```
///
/// Example:
/// ```bash
/// dart distribute_cli.dart build --config_path=config.env -v
/// ```
void main(List<String> args) async {
  final runner = CommandRunner(
      'distribute', 'Run commands to distribute your app packages.');
  runner.argParser
    ..addOption("config_path",
        defaultsTo: ".distribution.env",
        help: "Path to the configuration file.")
    ..addFlag("verbose",
        abbr: 'v', defaultsTo: false, help: "Enable verbose output.")
    ..addFlag("process_logs",
        abbr: 'l', defaultsTo: false, help: "Enable process logs.");

  runner.addCommand(InitCommand());
  runner.addCommand(Builder());
  runner.addCommand(Publisher());
  runner.run(args);
}
