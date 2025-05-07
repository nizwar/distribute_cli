import 'dart:async';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/app_builder.dart';
import 'package:distribute_cli/app_builder/parser.dart';
import 'package:distribute_cli/app_publisher/app_publisher.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/config_parser.dart';

import 'command.dart';
import 'parsers/job_arguments.dart';

class RunnerCommand extends Commander {
  @override
  String get description =>
      "Command to run the application using the selected platform or custom configuration. ";

  @override
  String get name => "run";

  @override
  ArgParser get argParser => ArgParser()
    ..addOption('config',
        abbr: 'c',
        help: 'Path to the configuration file.',
        defaultsTo: 'distribution.yaml')
    ..addOption('operation',
        abbr: 'o',
        help:
            'Key of the operation to run, use OperationKey.JobKey to run spesifict job.',
        defaultsTo: '');

  @override
  Future? run() async {
    final logger = ColorizeLogger(globalResults?['verbose'] ?? false);
    final operationKey = argResults!['operation'] as String;
    try {
      final configParser = ConfigParser.distributeYaml(
          argResults?['config'] as String? ?? 'distribution.yaml');

      if (operationKey.isNotEmpty) {
        if (operationKey.contains(".")) {
          final key = operationKey.split('.');
          configParser.tasks.removeWhere((task) => task.key != key[0]);
          if (key.isNotEmpty) {
            for (var task in configParser.tasks) {
              task.jobs.removeWhere((job) => job.key != key[1]);
            }
            if (configParser.tasks.every((task) => task.jobs.isEmpty)) {
              logger.logError(
                  "No jobs found for the specified operation key: $operationKey");
              return 1;
            }
          }
        } else {
          configParser.tasks.removeWhere((task) => task.key != operationKey);
        }

        if (configParser.tasks.isEmpty) {
          logger.logError("No task found with the key: $operationKey");
          return 1;
        }
      }

      logger.logInfo(
          'Running application with configuration: ${argResults!['config'] as String}');
      logger.logInfo("======= Running tasks =======");
      for (var task in configParser.tasks) {
        logger.logInfo(task.name);
        if (task.description != null) logger.logInfo('${task.description}');
        logger.logEmpty();
        for (var value in task.jobs) {
          logger.logInfo(
              "[Job] : ${value.name} ${value.description != null ? "(${value.description})" : ""}");
          logger.logEmpty();
          if (value.arguments.jobMode == JobMode.build) {
            await AppBuilder(value.arguments as BuildArguments,
                    configParser.environments)
                .build(
                    onError: logger.logErrorVerbose, onVerbose: logger.logDebug)
                .then((value) {
              logger.logEmpty();
              logger.logSuccess("Build completed successfully.");
            }).catchError((error) {
              logger.logEmpty();
              logger.logError("Build failed with error: $error");
            });
          } else if (value.arguments.jobMode == JobMode.publish) {
            await AppPublisher(value.arguments as PublisherArguments,
                    configParser.environments)
                .publish(
                    onError: logger.logErrorVerbose, onVerbose: logger.logDebug)
                .then((value) {
              logger.logEmpty();
              logger.logSuccess("Publish completed successfully.");
            }).catchError((error) {
              logger.logEmpty();
              logger.logError("Publish failed with error: $error");
            });
          } else {
            logger.logEmpty();
            logger.logError('Unknown job mode: ${value.arguments.jobMode}');
          }
        }
        logger.logSuccess("==============================");
      }
    } catch (e, s) {
      logger.logError('Error: $e\n$s');
      logger.logError('Please check your configuration file and try again.');
    } finally {
      logger.logSuccess("======= Finished tasks =======");
    }

    return;
  }
}
