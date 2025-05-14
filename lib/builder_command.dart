import 'package:distribute_cli/app_builder/android/command.dart' as android_command;
import 'package:distribute_cli/app_builder/custom/command.dart' as custom_command;
import 'package:distribute_cli/app_builder/ios/command.dart' as ios_command;
import 'package:distribute_cli/command.dart';

/// A command to build the application using the selected platform or custom configuration.
///
/// The [BuilderCommand] class provides subcommands for building the app
/// for Android, iOS, or using a custom configuration.
class BuilderCommand extends Commander {
  /// Creates a new [BuilderCommand] and adds subcommands for each platform.
  BuilderCommand() {
    addSubcommand(android_command.Command());
    addSubcommand(ios_command.Command());
    addSubcommand(custom_command.Command());
  }

  /// The description of the command.
  @override
  String get description => "Build the application using the selected platform or custom configuration.";

  /// The name of the command.
  @override
  String get name => "build";
}
