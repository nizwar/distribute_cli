import 'package:distribute_cli/app_publisher/android_publisher_command.dart';
import 'package:distribute_cli/app_publisher/ios_publisher_command.dart';

import 'command.dart';

/// A command to publish the app to the specified platform.
///
/// The `PublisherCommand` class provides subcommands for publishing the app
/// to Android and iOS platforms using their respective publisher commands.
class PublisherCommand extends Commander {
  PublisherCommand() {
    addSubcommand(AndroidPublisherCommand());
    addSubcommand(IosPublisherCommand());
  }

  @override
  String get description => "Publish the app to the specified platform.";

  @override
  String get name => "publish";
}
