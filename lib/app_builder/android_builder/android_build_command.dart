import 'package:args/args.dart';
import 'package:distribute_cli/logger.dart';

import '../../command.dart';
import '../app_builder.dart';
import 'android_build_arguments.dart';

class AndroidBuildCommand extends Commander {
  @override
  String get description => "Build an Android application using the specified configuration and options provided in the arguments.";

  @override
  String get name => "android";

  @override
  ArgParser get argParser => AndroidBuildArgument.parser;

  @override
  Future? run() async {
    final arguments = AndroidBuildArgument.fromArgResults(argResults!);
    final logger = ColorizeLogger(globalResults?['verbose'] ?? false);
    return AppBuilder(arguments).build(onVerbose: logger.logDebug, onError: logger.logErrorVerbose).then((value) {
      if (value == 0) {
        logger.logSuccess("Android build completed successfully.");
      } else {
        logger.logError("Android build failed with exit code: $value");
      }
      return value;
    }).catchError((error) {
      return 1;
    });
  }
}
