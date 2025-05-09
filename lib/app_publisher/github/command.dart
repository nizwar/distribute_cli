import 'dart:io';
import 'package:args/args.dart';
import '../../command.dart';
import 'arguments.dart' as github;

class Command extends Commander {
  final String platform;
  @override
  String get description => "Publish app to GitHub.";

  @override
  String get name => "github";

  @override
  ArgParser argParser = github.Arguments.parser;

  Command(this.platform);

  @override
  Future? run() => github.Arguments.fromArgResults(argResults!).publish(Platform.environment);
}
