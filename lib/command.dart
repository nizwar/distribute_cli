import 'package:args/command_runner.dart';
import 'package:distribute_cli/logger.dart';

abstract class Commander extends Command {
  ColorizeLogger get logger => ColorizeLogger(globalResults?['verbose'] ?? false);
}
