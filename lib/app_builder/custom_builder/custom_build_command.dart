import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/app_builder.dart';
import 'package:distribute_cli/app_builder/custom_builder/custom_build_arguments.dart';

import '../../command.dart';

class CustomBuildCommand extends Commander {
  @override
  String get description => "Build a custom application by selecting specific configurations and options tailored to your requirements.";

  @override
  String get name => "custom";

  @override
  ArgParser get argParser => CustomBuildArgument.parser;

  @override
  Future? run() async {
    final arguments = CustomBuildArgument.fromArgResults(argResults!);
    return AppBuilder(arguments, Platform.environment).build(onVerbose: logger.logDebug, onError: logger.logErrorVerbose);
  }
}
