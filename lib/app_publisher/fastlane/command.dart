import 'dart:async';

import 'package:args/args.dart';

import '../../command.dart';
import 'arguments.dart';

/// Comprehensive Fastlane deployment command.
///
/// Extends the base `Commander` class to provide robust Fastlane automation
/// for multi-platform app publishing, store integration, beta distribution,
/// and advanced deployment workflows.
///
/// Key Fastlane features:
/// - Android and iOS deployment automation
/// - Google Play Store and App Store Connect publishing
/// - Beta distribution via TestFlight and Play Console
/// - Store metadata and asset management
/// - Signing and provisioning automation
/// - Automated testing and validation
/// - Deployment status notifications
///
/// Example usage:
/// ```dart
/// final command = Command();
/// final result = await command.run();
/// if (result == 0) {
///   print('Fastlane deployment completed successfully');
/// } else {
///   print('Deployment failed with exit code: $result');
/// }
/// ```
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
  Future? run() async =>
      Arguments.fromArgResults(argResults!, globalResults).publish();
}
