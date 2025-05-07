import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_publisher/xcrun/xcrun_ios_publisher_arguments.dart';

import '../command.dart';
import 'app_publisher.dart';

class IosPublisherCommand extends Commander {
  @override
  String get description =>
      "Publish an iOS application using the XCrun tool, which provides a command-line interface for interacting with Xcode and managing app distribution tasks.";

  @override
  String get name => "ios";

  @override
  ArgParser get argParser => XcrunIosPublisherArguments.parser;

  @override
  Future? run() async {
    final arguments = XcrunIosPublisherArguments.fromArgParser(argResults!);
    return AppPublisher(arguments, Platform.environment)
        .publish(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
