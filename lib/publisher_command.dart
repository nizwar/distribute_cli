import 'package:distribute_cli/app_publisher/firebase/command.dart'
    as firebase_command;
import 'package:distribute_cli/app_publisher/fastlane/command.dart'
    as fastlane_command;
import 'package:distribute_cli/app_publisher/github/command.dart'
    as github_command;
import 'package:distribute_cli/app_publisher/xcrun/command.dart'
    as xcrun_command;

import 'command.dart';

/// A command to publish the app to the specified platform.
///
/// The [PublisherCommand] class provides subcommands for publishing the app
/// to Android and iOS platforms using their respective publisher commands.
class PublisherCommand extends Commander {
  /// Creates a new [PublisherCommand] and adds subcommands for each publisher.
  PublisherCommand() {
    addSubcommand(firebase_command.Command());
    addSubcommand(fastlane_command.Command());
    addSubcommand(xcrun_command.Command());
    addSubcommand(github_command.Command());
  }

  /// The description of the command.
  @override
  String get description => "Publish the app to the specified platform.";

  /// The name of the command.
  @override
  String get name => "publish";
}
