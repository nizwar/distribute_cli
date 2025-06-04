import 'dart:io';

import 'package:distribute_cli/app_builder/android/command.dart'
    as android_command;
import 'package:distribute_cli/app_builder/custom/command.dart'
    as custom_command;
import 'package:distribute_cli/app_builder/ios/command.dart' as ios_command;
import 'package:distribute_cli/command.dart';

/// A command to build the application using the selected platform or custom configuration.
///
/// The `BuilderCommand` class provides subcommands for building the app
/// for different platforms including Android, iOS (macOS only), and custom configurations.
/// Each subcommand handles the specific build process for its respective platform.
class BuilderCommand extends Commander {
  /// Creates a new BuilderCommand and registers platform-specific build subcommands.
  ///
  /// Available subcommands:
  /// - `android` - Build Android APK or AAB files
  /// - `ios` - Build iOS IPA files (only available on macOS)
  /// - `custom` - Build using custom configuration
  BuilderCommand() {
    // Add Android build command (available on all platforms)
    addSubcommand(android_command.Command());

    // Add iOS build command (only available on macOS)
    if (Platform.isMacOS) addSubcommand(ios_command.Command());

    // Add custom build command (available on all platforms)
    addSubcommand(custom_command.Command());
  }

  /// The description of the build command shown in help text
  @override
  String get description =>
      "Build the application using the selected platform or custom configuration.";

  /// The name of the command used in CLI
  @override
  String get name => "build";
}
