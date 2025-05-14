import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import '../../command.dart';
import 'arguments.dart';

/// Command to publish an Android application using Fastlane.
///
/// This command automates the deployment process, including tasks such as
/// building, signing, and uploading the app to the Google Play Store.
class Command extends Commander {
  /// Creates a new [Command] for publishing with Fastlane.
  Command();

  /// Description of the command.
  @override
  String get description =>
      "Publish an Android application using Fastlane, a tool that automates the deployment process.";

  /// Name of the command.
  @override
  String get name => "fastlane";

  /// Argument parser for the command.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the command.
  ///
  /// Parses the arguments and publishes the Android application using the [Arguments] class.
  /// Returns a [Future] that completes with the exit code of the publish process.
  @override
  Future? run() async => Arguments.fromArgResults(argResults!).publish(Platform.environment, onVerbose: onVerbose, onError: onError);
}
