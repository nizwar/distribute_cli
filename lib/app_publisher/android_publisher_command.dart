import 'package:distribute_cli/app_publisher/fastlane/fastlane_android_command.dart';
import 'package:distribute_cli/app_publisher/firebase/firebase_android_command.dart';

import '../command.dart';

/// A command to publish an Android application.
///
/// The `AndroidPublisherCommand` class provides subcommands for publishing
/// Android apps using different tools, such as Fastlane and Firebase.
class AndroidPublisherCommand extends Commander {
  /// Creates a new `AndroidPublisherCommand` instance.
  ///
  /// Adds subcommands for Fastlane and Firebase publishers.
  AndroidPublisherCommand() {
    addSubcommand(FastlaneAndroidCommand());
    addSubcommand(FirebaseAndroidCommand());
  }

  /// A description of the command.
  @override
  String get description => "Publish android app using choosen one.";

  /// The name of the command.
  @override
  String get name => "android";

  /// Executes the `android` command.
  ///
  /// This method is currently not implemented.
  @override
  Future? run() async {}
}
