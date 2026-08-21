import 'dart:io';

import 'package:distribute_cli/app_publisher/firebase/command.dart'
    as firebase_command;
import 'package:distribute_cli/app_publisher/fastlane/command.dart'
    as fastlane_command;
import 'package:distribute_cli/app_publisher/github/command.dart'
    as github_command;
import 'package:distribute_cli/app_publisher/huawei/command.dart'
    as huawei_command;
import 'package:distribute_cli/app_publisher/xcrun/command.dart'
    as xcrun_command;

import 'command.dart';

/// A command to publish the app to various distribution platforms.
///
/// The `PublisherCommand` class provides subcommands for publishing the app
/// to different platforms including Firebase App Distribution, Google Play
/// Store, App Store, GitHub releases, and Huawei AppGallery. Each subcommand
/// handles the publishing process for its respective platform.
class PublisherCommand extends Commander {
  /// Creates a new PublisherCommand and registers platform-specific publish
  /// subcommands.
  PublisherCommand() {
    addSubcommand(firebase_command.Command());
    addSubcommand(fastlane_command.Command());
    if (Platform.isMacOS) addSubcommand(xcrun_command.Command());
    addSubcommand(github_command.Command());
    addSubcommand(huawei_command.Command());
  }

  /// The description of the publish command shown in help text.
  @override
  String get description => 'Publish the app to the specified platform.';

  /// The name of the command used in CLI.
  @override
  String get name => 'publish';
}
