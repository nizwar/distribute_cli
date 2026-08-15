import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:distribute_cli/ai_command.dart';
import 'package:distribute_cli/builder_command.dart';
import 'package:distribute_cli/create_command.dart';
import 'package:distribute_cli/doctor_command.dart';
import 'package:distribute_cli/initializer_command.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/build_info.dart';
import 'package:distribute_cli/prompt.dart';
import 'package:distribute_cli/validate_command.dart';
import 'package:distribute_cli/version.dart';

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
/// - `validate` - Validate the configuration without running anything
/// - `doctor` - Check the tools, configuration and credentials
///
/// Global options:
/// - `--verbose` or `-v` - Print diagnostic detail and raw tool output
/// - `--quiet` or `-q` - Print failures only
/// - `--silent` - Print nothing; the log file is still written
/// - `--version` - Print the CLI version and exit
/// - `--config` - Path to the configuration file (defaults to "distribution.yaml")
/// - `--log-file` - Path to the log file (defaults to "distribution.log")
/// - `--no-color` - Disable ANSI colors in the terminal output
///
/// The process exit code mirrors the outcome of the executed command, so CI
/// pipelines can reliably detect a failed build or upload.
///
/// Parameters:
/// - `args` - Command line arguments passed to the application
Future<void> main(List<String> args) async {
  // Detecting the package name reads pubspec.yaml and the platform project
  // files. None of that is essential — every command still works without it —
  // so an unreadable or malformed file must not take the whole CLI down with
  // an uncaught error and exit 255.
  try {
    await BuildInfo.applyBuildInfo();
  } catch (e) {
    stderr.writeln(
      'Could not read the project metadata: $e\n'
      'Continuing; package names will have to be given explicitly.',
    );
  }

  // Create the main command runner for the distribute CLI
  final runner = CommandRunner<int>(
    'distribute',
    'Run commands to distribute your app packages.',
  );

  // Add global command line options
  runner.argParser.addFlag(
    "verbose",
    abbr: 'v',
    defaultsTo: false,
    help: "Print diagnostic detail and raw tool output.",
  );
  runner.argParser.addFlag(
    "quiet",
    abbr: 'q',
    negatable: false,
    defaultsTo: false,
    help: "Print failures only.",
  );
  runner.argParser.addFlag(
    "silent",
    negatable: false,
    defaultsTo: false,
    help:
        "Print nothing; rely on the exit code. The log file is still written.",
  );
  runner.argParser.addFlag(
    "version",
    negatable: false,
    help: "Print the distribute_cli version and exit.",
  );
  runner.argParser.addFlag(
    "color",
    defaultsTo: true,
    help: "Enable ANSI colors in the terminal output.",
  );
  runner.argParser.addOption(
    "config",
    defaultsTo: "distribution.yaml",
    help: "Path to the configuration file.",
  );
  runner.argParser.addOption(
    "log-file",
    defaultsTo: "distribution.log",
    help: "Path to the log file. Use an empty value to disable file logging.",
  );

  // Register all available commands
  runner.addCommand(InitializerCommand());
  runner.addCommand(BuilderCommand());
  runner.addCommand(PublisherCommand());
  runner.addCommand(RunnerCommand());
  runner.addCommand(CreateCommand());
  runner.addCommand(ValidateCommand());
  runner.addCommand(DoctorCommand());

  // The assistant executes real commands through this same runner rather than
  // re-implementing them or shelling out, so `ai` can never reach a code path a
  // typed command could not.
  final aiCommand = AiCommand();
  aiCommand.executor = (arguments) async => await runner.run(arguments) ?? 0;
  runner.addCommand(aiCommand);

  // Resolve the global options before running so that logging is configured
  // even when the command itself fails to parse.
  ArgResults? preParsed;
  try {
    preParsed = runner.argParser.parse(args);
  } on FormatException {
    // Let CommandRunner produce the user facing usage error below.
  }

  if (preParsed?['version'] == true) {
    stdout.writeln('distribute_cli $packageVersion');
    return;
  }

  if (preParsed?['color'] == false) ColorizeLogger.useColors = false;
  ColorizeLogger.verbosity = LogVerbosity.fromFlags(
    silent: preParsed?['silent'] as bool? ?? false,
    quiet: preParsed?['quiet'] as bool? ?? false,
    verbose: preParsed?['verbose'] as bool? ?? false,
  );
  // An explicitly empty --log-file disables file logging, as documented.
  ColorizeLogger.logFilePath =
      (preParsed?['log-file'] as String?) ?? "distribution.log";

  // Start every invocation with a clean log file carrying a run header.
  ColorizeLogger.startLogFile(args);

  final logger = ColorizeLogger();

  // Execute the command and mirror its result in the process exit code.
  try {
    final result = await runner.run(args);
    // `run` returns null when it only printed usage — either from a bare
    // invocation or `--help`. Asking for help is a success; being given no
    // command at all is a usage error, and a script that reaches this by
    // mistake must not read it as one.
    exitCode = result ?? (_isHelpRequest(args) ? 0 : 64);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on PromptAbortedException catch (e) {
    // A wizard started without a terminal — from CI, a pipe, or Ctrl-D. That is
    // the wrong way to invoke it, not a failed build.
    logger.logError(e.message);
    exitCode = 64;
  } on ArgumentError catch (e) {
    // The args package reports a missing `mandatory` option this way rather
    // than as a UsageException, so it would otherwise look like a crash.
    logger.logError(e.message.toString());
    exitCode = 64;
  } catch (e, s) {
    logger.logError(e.toString());
    logger.logDebug(s.toString());
    exitCode = 1;
  }
}

/// Whether [args] asked for help rather than omitting a command.
bool _isHelpRequest(List<String> args) =>
    args.isNotEmpty &&
    args.any((argument) =>
        argument == '-h' || argument == '--help' || argument == 'help');
