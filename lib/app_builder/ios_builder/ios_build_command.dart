import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/ios_builder/ios_build_arguments.dart';

import '../../command.dart';
import '../app_builder.dart';

/// Command to build an iOS application.
///
/// This command uses the provided arguments to configure and execute
/// the iOS build process. It is only supported on macOS.
class IOSBuildCommand extends Commander {
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
  ArgParser get argParser => IOSBuildArgument.parser;

  /// Executes the command.
  ///
  /// - Checks if the platform is macOS.
  /// - Parses the arguments.
  /// - Builds the iOS application using the [AppBuilder].
  ///
  /// Returns a [Future] that completes with the exit code of the build process.
  @override
  Future? run() async {
    final arguments = IOSBuildArgument.fromArgResults(argResults!);
    if (!Platform.isMacOS) {
      logger.logError("This command is only supported on macOS.");
      return 1;
    }
    return AppBuilder(arguments, Platform.environment)
        .build(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
