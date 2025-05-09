import 'dart:io';

import 'package:args/args.dart';

import '../../command.dart';
import 'arguments.dart';

/// Command to build an Android application.
///
/// This command uses the provided arguments to configure and execute
/// the Android build process.
class Command extends Commander {
  /// Description of the command.
  ///
  /// Provides a brief explanation of what the command does.
  @override
  String get description => "Build an Android application using the specified configuration and options provided in the arguments.";

  /// Name of the command.
  ///
  /// This is the identifier used to invoke the command.
  @override
  String get name => "android";

  /// Argument parser for the command.
  ///
  /// Defines the arguments and options available for this command.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the command.
  ///
  /// - Parses the arguments.
  /// - Builds the Android application using the [AppBuilder].
  /// - Logs the success or failure of the build process.
  ///
  /// Returns a [Future] that completes with the exit code of the build process.
  @override
  Future? run() => Arguments.fromArgResults(argResults!).build(Platform.environment);
}
