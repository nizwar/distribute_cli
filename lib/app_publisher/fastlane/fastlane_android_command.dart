import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_publisher/fastlane/fastlane_android_publisher_arguments.dart';

import '../../command.dart';
import '../app_publisher.dart';

class FastlaneAndroidCommand extends Commander {
  @override
  String get description =>
      "Publish an Android application using Fastlane, a tool that automates the deployment process, including tasks such as building, signing, and uploading the app to the Google Play Store.";

  @override
  String get name => "fastlane";

  @override
  ArgParser get argParser => FastlaneAndroidPublisherArguments.parser;

  @override
  Future? run() async {
    final arguments =
        FastlaneAndroidPublisherArguments.fromArgResults(argResults!);
    return AppPublisher(arguments, Platform.environment)
        .publish(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
