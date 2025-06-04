import 'dart:io';

import 'package:args/args.dart';
import 'arguments.dart';

import '../../command.dart';

/// Command to build an iOS application.
///
/// This command uses the provided arguments to configure and execute
/// the iOS build process. It is only supported on macOS.
class Command extends Commander {
  /// Description of the command.
  @override
  String get description =>
      "Build an iOS application using the specified configuration and parameters provided in the command-line arguments.";

  /// Name of the command.
  @override
  String get name => "ios";

  /// Argument parser for the command.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the command.
  ///
  /// Checks if the platform is macOS, parses the arguments, and builds the iOS application.
  /// Returns a [Future] that completes with the exit code of the build process.
  @override
  Future? run() async {
    if (!Platform.isMacOS) {
      logger.logError("This command is only supported on macOS.");
      return 1;
    }
    return Arguments.fromArgResults(argResults!, globalResults).build();
  }
}
