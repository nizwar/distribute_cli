import 'dart:io';
import 'package:args/args.dart';
import 'package:distribute_cli/command.dart';
import 'arguments.dart' as xcrun;

/// Command to publish an iOS application using the XCrun tool.
///
/// This command provides a command-line interface for interacting with Xcode and managing app distribution tasks.
class Command extends Commander {
  /// Creates a new [Command] for publishing with XCrun.
  Command();

  /// Description of the command.
  @override
  String get description => "Publish an iOS application using the XCrun tool, which provides a command-line interface for interacting with Xcode and managing app distribution tasks.";

  /// Name of the command.
  @override
  String get name => "xcrun";

  /// Argument parser for the command.
  @override
  ArgParser get argParser => xcrun.Arguments.parser;

  /// Executes the command.
  ///
  /// Parses the arguments and publishes the iOS application using the [Arguments] class.
  /// Returns a [Future] that completes with the exit code of the publish process.
  @override
  Future? run() => xcrun.Arguments.fromArgParser(argResults!).publish(Platform.environment, onVerbose: onVerbose, onError: onError);
}
