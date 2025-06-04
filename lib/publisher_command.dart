import 'dart:io';

import 'package:distribute_cli/app_publisher/firebase/command.dart'
    as firebase_command;
import 'package:distribute_cli/app_publisher/fastlane/command.dart'
    as fastlane_command;
import 'package:distribute_cli/app_publisher/github/command.dart'
    as github_command;
import 'package:distribute_cli/app_publisher/xcrun/command.dart'
    as xcrun_command;

import 'command.dart';

/// A command to publish the app to various distribution platforms.
///
/// The `PublisherCommand` class provides subcommands for publishing the app
/// to different platforms including Firebase App Distribution, Google Play Store,
/// App Store, and GitHub releases. Each subcommand handles the specific
/// publishing process for its respective platform.
class PublisherCommand extends Commander {
  /// Creates a new PublisherCommand and registers platform-specific publish subcommands.
  ///
  /// Available subcommands:
  /// - `firebase` - Publish to Firebase App Distribution
  /// - `fastlane` - Publish using Fastlane automation
  /// - `xcrun` - Publish to App Store using Xcode tools (macOS only)
  /// - `github` - Publish as GitHub release
  PublisherCommand() {
    // Add Firebase App Distribution publisher (available on all platforms)
    addSubcommand(firebase_command.Command());

    // Add Fastlane publisher (available on all platforms)
    addSubcommand(fastlane_command.Command());

    // Add Xcrun publisher for App Store (only available on macOS)
    if (Platform.isMacOS) addSubcommand(xcrun_command.Command());

    // Add GitHub releases publisher (available on all platforms)
    addSubcommand(github_command.Command());
  }

  /// The description of the publish command shown in help text
  @override
  String get description => "Publish the app to the specified platform.";

  /// The name of the command used in CLI
  @override
  String get name => "publish";
}
