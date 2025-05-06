import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/ios_builder/ios_build_arguments.dart';

import '../../command.dart';
import '../app_builder.dart';

class IOSBuildCommand extends Commander {
  @override
  String get description => "Build an iOS application using the specified configuration and parameters provided in the command-line arguments.";

  @override
  String get name => "ios";

  @override
  ArgParser get argParser => IOSBuildArgument.parser;

  @override
  Future? run() async {
    final arguments = IOSBuildArgument.fromArgResults(argResults!);
    if (!Platform.isMacOS) {
      logger.logError("This command is only supported on macOS.");
      return 1;
    }
    return AppBuilder(arguments).build(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
