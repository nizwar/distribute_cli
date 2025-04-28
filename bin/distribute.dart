import 'package:args/command_runner.dart';
import 'package:distribute_cli/builder.dart';
import 'package:distribute_cli/initializer.dart';
import 'package:distribute_cli/helper.dart';
import 'package:distribute_cli/publisher.dart';

late Helper helper;
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

  helper = Helper();
  await helper.initialize(runner.argParser.parse(args));
  runner.addCommand(InitCommand(helper));
  runner.addCommand(Builder(helper.environment));
  runner.addCommand(Publisher(helper.environment));
  runner.run(args);
}
