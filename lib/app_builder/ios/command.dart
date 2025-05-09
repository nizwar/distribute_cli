import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/ios/arguments.dart';

import '../../command.dart';

/// Command to build an iOS application.
///
/// This command uses the provided arguments to configure and execute
/// the iOS build process. It is only supported on macOS.
class Command extends Commander {
  /// Description of the command.
  ///
  /// Provides a brief explanation of what the command does.
  @override
  String get description =>
      "Build an iOS application using the specified configuration and parameters provided in the command-line arguments.";

  /// Name of the command.
  ///
  /// This is the identifier used to invoke the command.
  @override
  String get name => "ios";

  /// Argument parser for the command.
  ///
  /// Defines the arguments and options available for this command.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the command.
  ///
  /// - Checks if the platform is macOS.
  /// - Parses the arguments.
  /// - Builds the iOS application using the [AppBuilder].
  ///
  /// Returns a [Future] that completes with the exit code of the build process.
  @override
  Future? run() async {
    if (!Platform.isMacOS) {
      logger.logError("This command is only supported on macOS.");
      return 1;
    }
    return Arguments.fromArgResults(argResults!).build(Platform.environment);
  }
}
