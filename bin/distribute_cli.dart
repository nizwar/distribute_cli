import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/builder_command.dart';
import 'package:distribute_cli/create_command.dart';
import 'package:distribute_cli/initializer_command.dart';
import 'package:distribute_cli/logger.dart';

import 'package:distribute_cli/publisher_command.dart';
import 'package:distribute_cli/runner_command.dart';

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
  final runner = CommandRunner('distribute', 'Run commands to distribute your app packages.');
  final logs = File("distribution.log");
  if (await logs.exists()) {
    await logs.delete(recursive: true).catchError((value) => value);
  }

  runner.argParser.addFlag("verbose", abbr: 'v', defaultsTo: false, help: "Enable verbose output.");
  runner.argParser.addOption("config", defaultsTo: "distribution.yaml", help: "Path to the configuration file.");
  runner.addCommand(InitializerCommand());
  runner.addCommand(BuilderCommand());
  runner.addCommand(PublisherCommand());
  runner.addCommand(RunnerCommand());
  runner.addCommand(CreateCommand());
  
  runner.run(args).catchError((e, s) {
    final logger = ColorizeLogger(true);
    logger.logError("${e.toString()}\n${s.toString()}");
    exit(1);
  });
}
