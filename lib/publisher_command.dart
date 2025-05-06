import 'package:distribute_cli/app_publisher/android_publisher_command.dart';
import 'package:distribute_cli/app_publisher/ios_publisher_command.dart';

import 'command.dart';

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
