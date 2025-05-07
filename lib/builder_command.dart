import 'package:distribute_cli/app_builder/android_builder/android_build_command.dart';
import 'package:distribute_cli/app_builder/custom_builder/custom_build_command.dart';
import 'package:distribute_cli/app_builder/ios_builder/ios_build_command.dart';
import 'package:distribute_cli/command.dart';

class BuilderCommand extends Commander {
  BuilderCommand() {
    addSubcommand(AndroidBuildCommand());
    addSubcommand(IOSBuildCommand());
    addSubcommand(CustomBuildCommand());
  }

  @override
  String get description =>
      "Build the application using the selected platform or custom configuration.";

  @override
  String get name => "build";
}
