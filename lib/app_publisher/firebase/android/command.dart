import 'dart:io';

import 'package:args/args.dart';
import '../../../command.dart';
import 'arguments.dart';

/// Command to publish an Android application to Firebase App Distribution.
///
/// This command allows you to distribute your app to testers quickly and efficiently.
class Command extends Commander {
  /// Description of the command.
  ///
  /// Provides a brief explanation of what the command does.
  @override
  String get description => "Publish an Android application to Firebase App Distribution.";

  /// Name of the command.
  ///
  /// This is the identifier used to invoke the command.
  @override
  String get name => "firebase";

  /// Argument parser for the command.
  ///
  /// Defines the arguments and options available for this command.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the command.
  ///
  /// - Parses the arguments.
  /// - Publishes the Android application using the [AppPublisher].
  ///
  /// Returns a [Future] that completes with the exit code of the publish process.
  @override
  Future? run() => Arguments.fromArgResults(argResults!).publish(Platform.environment, onVerbose: onVerbose, onError: onError);
}
