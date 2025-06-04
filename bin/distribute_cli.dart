import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/builder_command.dart';
import 'package:distribute_cli/create_command.dart';
import 'package:distribute_cli/initializer_command.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/build_info.dart';

import 'package:distribute_cli/publisher_command.dart';
import 'package:distribute_cli/runner_command.dart';

/// The main entry point for the Distribute CLI application.
///
/// This function sets up and runs the command-line interface for the distribution tool.
/// It initializes build information, creates a command runner, and adds all available commands.
///
/// Available commands:
/// - `init` - Initialize distribution configuration
/// - `build` - Build app packages
/// - `publish` - Publish app packages
/// - `run` - Run distribution tasks
/// - `create` - Create new distribution templates
///
/// Global options:
/// - `--verbose` or `-v` - Enable verbose output for detailed logging
/// - `--config` - Path to the configuration file (defaults to "distribution.yaml")
///
/// Parameters:
/// - `args` - Command line arguments passed to the application
void main(List<String> args) async {
  // Apply build information to the application
  await BuildInfo.applyBuildInfo();

  // Create the main command runner for the distribute CLI
  final runner = CommandRunner(
      'distribute', 'Run commands to distribute your app packages.');

  // Clean up any existing log files
  final logs = File("distribution.log");
  if (await logs.exists()) {
    await logs.delete(recursive: true).catchError((value) => value);
  }

  // Add global command line options
  runner.argParser.addFlag("verbose",
      abbr: 'v', defaultsTo: false, help: "Enable verbose output.");
  runner.argParser.addOption("config",
      defaultsTo: "distribution.yaml", help: "Path to the configuration file.");

  // Register all available commands
  runner.addCommand(InitializerCommand());
  runner.addCommand(BuilderCommand());
  runner.addCommand(PublisherCommand());
  runner.addCommand(RunnerCommand());
  runner.addCommand(CreateCommand());

  // Execute the command with error handling
  runner.run(args).catchError((e, s) {
    final logger = ColorizeLogger(true);
    logger.logError("${e.toString()}\n${s.toString()}");
    exit(1);
  });
}
