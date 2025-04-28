import 'package:args/command_runner.dart';
import 'package:distribute_cli/builder.dart';
import 'package:distribute_cli/initializer.dart';

import 'package:distribute_cli/publisher.dart';

void main(List<String> args) async {
  final runner = CommandRunner(
      'distribute', 'Run commands to distribute your app packages.');
  runner.argParser
    ..addOption("config_path",
        defaultsTo: ".distribution.env",
        help: "Path to the configuration file.")
    ..addFlag("verbose",
        abbr: 'v', defaultsTo: false, help: "Enable verbose output.")
    ..addFlag("process_logs",
        abbr: 'l', defaultsTo: false, help: "Enable process logs.");

  runner.addCommand(InitCommand());
  runner.addCommand(Builder());
  runner.addCommand(Publisher());
  runner.run(args);
}
