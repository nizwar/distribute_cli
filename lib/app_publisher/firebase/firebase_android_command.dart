import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_publisher/firebase/firebase_android_publisher_arguments.dart';
import '../../command.dart';
import '../app_publisher.dart';

class FirebaseAndroidCommand extends Commander {
  @override
  String get description =>
      "Publish an Android application to Firebase App Distribution, allowing you to distribute your app to testers quickly and efficiently.";

  @override
  String get name => "firebase";

  @override
  ArgParser get argParser => FirebaseAndroidPublisherArguments.parser;

  @override
  Future? run() async {
    final arguments =
        FirebaseAndroidPublisherArguments.fromArgResults(argResults!);
    return AppPublisher(arguments, Platform.environment)
        .publish(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
