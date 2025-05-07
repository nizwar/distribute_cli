import 'dart:convert';
import 'dart:io';
import 'package:distribute_cli/app_builder/parser.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/config_parser.dart';

class AppBuilder<T extends BuildArguments> {
  /// The environments to use for the builder
  final Map<String, dynamic> environments;

  /// The arguments to pass to the builder
  final T args;

  AppBuilder(this.args, this.environments);

  Future<int> build(
      {Function(String)? onVerbose, Function(String)? onError}) async {
    ColorizeLogger logger = ColorizeLogger(true);
    final rawArguments = args.toJson();
    rawArguments.removeWhere((key, value) => value == null);
    if (logger.isVerbose) {
      logger.logInfo("Running build with configurations:");
      for (var value in rawArguments.keys) {
        logger.logInfo(" - $value: ${rawArguments[value]}");
      }
      logger.logEmpty();
    }
    onVerbose?.call("Starting build with `flutter ${substituteVariables([
          "build",
          ...args.results
        ].join(" "), environments)}`");
    final process = await Process.start("flutter", [
      "build",
      ...args.results.map((e) => substituteVariables(e, environments))
    ]);
    process.stdout.transform(utf8.decoder).listen(onVerbose);
    process.stderr.transform(utf8.decoder).listen(onError);
    return await process.exitCode;
  }
}
