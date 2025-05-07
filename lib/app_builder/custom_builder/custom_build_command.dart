import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/app_builder.dart';
import 'package:distribute_cli/app_builder/custom_builder/custom_build_arguments.dart';

import '../../command.dart';

/// Command to build a custom application.
///
/// This command allows users to specify custom configurations and options
/// tailored to their requirements for building the application.
class CustomBuildCommand extends Commander {
  /// Description of the command.
  ///
  /// Provides a brief explanation of what the command does.
  @override
  String get description =>
      "Build a custom application by selecting specific configurations and options tailored to your requirements.";

  /// Name of the command.
  ///
  /// This is the identifier used to invoke the command.
  @override
  String get name => "custom";

  /// Argument parser for the command.
  ///
  /// Defines the arguments and options available for this command.
  @override
  ArgParser get argParser => CustomBuildArgument.parser;

  /// Executes the command.
  ///
  /// - Parses the arguments.
  /// - Builds the application using the [AppBuilder].
  ///
  /// Returns a [Future] that completes with the exit code of the build process.
  @override
  Future? run() async {
    final arguments = CustomBuildArgument.fromArgResults(argResults!);
    return AppBuilder(arguments, Platform.environment)
        .build(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
