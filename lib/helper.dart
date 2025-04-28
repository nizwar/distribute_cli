import 'dart:io';

import 'package:args/args.dart';
import 'logger.dart';

import 'environment.dart';

class Helper {
  late Environment environment;
  late String configPath;

  Future initialize(ArgResults argResults) async {
    configPath = argResults['config_path'] as String;

    final configFile = File(configPath);
    final isVerbose = argResults['verbose'] as bool;

    /// Check if the configuration file exists
    if (!await configFile.exists()) {
      await configFile.create();
      ColorizeLogger.logDebug(
          'Configuration file created at ${configFile.path}');
    }

    if ((await configFile.readAsString()).isEmpty) {
      await configFile.writeAsString(Environment.examples);
    }

    environment = Environment(configFile.path);
    environment.isVerbose = isVerbose;
  }
}
