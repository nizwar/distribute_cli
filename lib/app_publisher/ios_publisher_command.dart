import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_publisher/xcrun/xcrun_ios_publisher_arguments.dart';

import '../command.dart';
import 'app_publisher.dart';

/// A command to publish an iOS application using the XCrun tool.
///
/// The `IosPublisherCommand` class provides functionality to publish iOS apps
/// by interacting with Xcode and managing app distribution tasks.
class IosPublisherCommand extends Commander {
  /// A description of the command.
  @override
  String get description =>
      "Publish an iOS application using the XCrun tool, which provides a command-line interface for interacting with Xcode and managing app distribution tasks.";

  /// The name of the command.
  @override
  String get name => "ios";

  /// The argument parser for the command.
  @override
  ArgParser get argParser => XcrunIosPublisherArguments.parser;

  /// Executes the `ios` command.
  ///
  /// This method parses the arguments and uses the `AppPublisher` class
  /// to publish the iOS application.
  @override
  Future? run() async {
    final arguments = XcrunIosPublisherArguments.fromArgParser(argResults!);
    return AppPublisher(arguments, Platform.environment)
        .publish(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
