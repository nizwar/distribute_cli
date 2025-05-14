import 'dart:io';

import 'package:args/args.dart';
import 'arguments.dart';

import '../../command.dart';

/// Command to build a custom application.
///
/// This command allows users to specify custom configurations and options
/// tailored to their requirements for building the application.
class Command extends Commander {
  /// Description of the command.
  @override
  String get description =>
      "Build a custom application by selecting specific configurations and options tailored to your requirements.";

  /// Name of the command.
  @override
  String get name => "custom";

  /// Argument parser for the command.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the command.
  ///
  /// Parses the arguments and builds the application using the provided environment.
  /// Returns a [Future] that completes with the exit code of the build process.
  @override
  Future? run() =>
      Arguments.fromArgResults(argResults!).build(Platform.environment);
}
