import 'dart:io';
import 'package:args/args.dart';
import 'package:distribute_cli/command.dart';
import 'arguments.dart' as xcrun;

class Command extends Commander {
  @override
  String get description => "Publish an iOS application using the XCrun tool, which provides a command-line interface for interacting with Xcode and managing app distribution tasks.";

  @override
  String get name => "xcrun";

  @override
  ArgParser get argParser => xcrun.Arguments.parser;

  @override
  Future? run() => xcrun.Arguments.fromArgParser(argResults!).publish(Platform.environment, onVerbose: onVerbose, onError: onError);
}
