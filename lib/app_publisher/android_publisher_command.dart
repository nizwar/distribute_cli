import 'package:distribute_cli/app_publisher/fastlane/android/command.dart' as fastlane_publisher;
import 'package:distribute_cli/app_publisher/firebase/android/command.dart' as firebase_publisher;

import '../command.dart';
import 'github/command.dart' as github;

/// A command to publish an Android application.
///
/// The `AndroidPublisherCommand` class provides subcommands for publishing
/// Android apps using different tools, such as Fastlane and Firebase.
class AndroidPublisherCommand extends Commander {
  AndroidPublisherCommand() {
    addSubcommand(fastlane_publisher.Command());
    addSubcommand(firebase_publisher.Command());
    addSubcommand(github.Command("android"));
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
  Future? run() async {
    super.run();
  }
}
