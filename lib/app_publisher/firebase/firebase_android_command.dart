import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_publisher/firebase/firebase_android_publisher_arguments.dart';
import '../../command.dart';
import '../app_publisher.dart';

/// Command to publish an Android application to Firebase App Distribution.
///
/// This command allows you to distribute your app to testers quickly and efficiently.
class FirebaseAndroidCommand extends Commander {
  /// Description of the command.
  ///
  /// Provides a brief explanation of what the command does.
  @override
  String get description =>
      "Publish an Android application to Firebase App Distribution, allowing you to distribute your app to testers quickly and efficiently.";

  /// Name of the command.
  ///
  /// This is the identifier used to invoke the command.
  @override
  String get name => "firebase";

  /// Argument parser for the command.
  ///
  /// Defines the arguments and options available for this command.
  @override
  ArgParser get argParser => FirebaseAndroidPublisherArguments.parser;

  /// Executes the command.
  ///
  /// - Parses the arguments.
  /// - Publishes the Android application using the [AppPublisher].
  ///
  /// Returns a [Future] that completes with the exit code of the publish process.
  @override
  Future? run() async {
    final arguments =
        FirebaseAndroidPublisherArguments.fromArgResults(argResults!);
    return AppPublisher(arguments, Platform.environment)
        .publish(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
