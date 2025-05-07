import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_publisher/fastlane/fastlane_android_publisher_arguments.dart';

import '../../command.dart';
import '../app_publisher.dart';

/// Command to publish an Android application using Fastlane.
///
/// This command automates the deployment process, including tasks such as
/// building, signing, and uploading the app to the Google Play Store.
class FastlaneAndroidCommand extends Commander {
  /// Description of the command.
  ///
  /// Provides a brief explanation of what the command does.
  @override
  String get description =>
      "Publish an Android application using Fastlane, a tool that automates the deployment process, including tasks such as building, signing, and uploading the app to the Google Play Store.";

  /// Name of the command.
  ///
  /// This is the identifier used to invoke the command.
  @override
  String get name => "fastlane";

  /// Argument parser for the command.
  ///
  /// Defines the arguments and options available for this command.
  @override
  ArgParser get argParser => FastlaneAndroidPublisherArguments.parser;

  /// Executes the command.
  ///
  /// - Parses the arguments.
  /// - Publishes the Android application using the [AppPublisher].
  ///
  /// Returns a [Future] that completes with the exit code of the publish process.
  @override
  Future? run() async {
    final arguments =
        FastlaneAndroidPublisherArguments.fromArgResults(argResults!);
    return AppPublisher(arguments, Platform.environment)
        .publish(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
