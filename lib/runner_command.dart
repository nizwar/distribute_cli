import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'parsers/config_parser.dart';

import 'command.dart';
import 'parsers/job_arguments.dart';

/// A command to execute distribution tasks defined in the configuration file.
///
/// The `RunnerCommand` class is responsible for parsing the configuration file,
/// filtering tasks and jobs based on the provided operation key, and executing
/// the specified build and publish operations. It supports running individual
/// jobs or entire task workflows.
class RunnerCommand extends Commander {
  /// The description of the run command shown in help text
  @override
  String get description =>
      "Command to run the application using the selected platform or custom configuration. ";

  /// The name of the command used in CLI
  @override
  String get name => "run";

  /// Argument parser for the run command with configuration and operation options.
  ///
  /// Available options:
  /// - `--config` or `-c` - Path to the configuration file (defaults to "distribution.yaml")
  /// - `--operation` or `-o` - Key of the operation to run (use "TaskKey.JobKey" for specific jobs)
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

  /// The operation key used to filter which tasks or jobs to execute.
  ///
  /// Supports the following formats:
  /// - Empty string - Runs all tasks
  /// - "TaskKey" - Runs all jobs in the specified task
  /// - "TaskKey.JobKey" - Runs only the specific job within the task
  String get operationKey => argResults!['operation'] as String;

  /// Executes the run command to process distribution tasks.
  ///
  /// This method performs the following operations:
  /// - Parses the configuration file specified by `--config` option
  /// - Filters tasks and jobs based on the `--operation` key
  /// - Executes build operations for each selected job
  /// - Executes publish operations for each selected job
  /// - Logs progress and results throughout the process
  ///
  /// The execution can be filtered by operation key:
  /// - No operation key: Runs all tasks and jobs
  /// - Task key only: Runs all jobs within that task
  /// - Task.Job key: Runs only the specific job
  @override
  Future? run() async {
    final configParser = await configParserBuilder();
    if (configParser == null) {
      logger.logError("Configuration file is not valid or not found.");
      exit(1);
    }
    try {
      logger.logInfo(
          'Running application with configuration: ${argResults!['config'] as String}');
      logger.logInfo("======= Running tasks =======");
      for (var task in configParser.tasks) {
        logger.logInfo(task.name);
        if (task.description != null) logger.logInfo('${task.description}');
        logger.logEmpty();
        List<Job> jobs = List.from(task.jobs);
        if (operationKey.isEmpty) {
          if (task.workflows != null) {
            logger.logInfo(
                "Workflows:\n${task.workflows?.map((e) => "- $e").join("\n")}");
            logger.logEmpty();
            jobs = [];
            for (var workflow in task.workflows!) {
              final job =
                  task.jobs.where((job) => job.key == workflow).firstOrNull;
              if (job != null) {
                jobs.add(job);
              } else {
                logger.logError("No job found with the key: $workflow");
                exit(1);
              }
            }
          }
        }
        List<int> results = [];
        for (var value in jobs) {
          logger.logInfo(
              "[Job] : ${value.name} ${value.description != null ? "(${value.description})" : ""}");

          /// Check if both builder and publisher are null
          if (value.builder == null && value.publisher == null) {
            logger.logEmpty();
            logger.logError(
                "No builder or publisher found for the job: ${value.name}");
            break;
          }

          //Run Builder Job
          if (value.builder != null) {
            results.add(
                await runBuilder(value.builder!, configParser).then((value) {
              if (value != 0) {
                logger.logError("Build failed with exit code: $value");
              }
              return value;
            }));
          }

          //Run Publisher Job
          if (value.publisher != null) {
            results.add(await runPublisher(value.publisher!, configParser)
                .then((value) {
              if (value != 0) {
                if (logger.isVerbose) {
                  logger.logInfo("Publish failed with exit code: $value");
                } else {
                  logger.logInfo(
                      "Publish failed with exit code: $value, details is available in distribution.log");
                }
              }
              return value;
            }));
          }
        }
        if (results.isEmpty) {
          logger.logError("No results found for the task: ${task.name}");
          continue;
        }
        if (results.any((element) => element != 0)) {
          logger.logError(
              "Task ${task.name} failed with exit code: ${results.reduce((value, element) => value + element)}");
          continue;
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

  Future<ConfigParser?> configParserBuilder() async {
    final configParser = await ConfigParser.distributeYaml(
        argResults?['config'] as String? ?? 'distribution.yaml',
        globalResults!);
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
            return null;
          }
        }
      } else {
        configParser.tasks.removeWhere((task) => task.key != operationKey);
      }

      if (configParser.tasks.isEmpty) {
        logger.logError("No task found with the key: $operationKey");
        return null;
      }
    }

    return configParser;
  }

  Future<int> runBuilder(BuilderJob builder, ConfigParser config) async {
    logger.logEmpty();
    List<int> results = [];

    if (builder.android != null) {
      logger.logInfo("Building Android binary");
      final androidResult = await builder.android!.build().then((value) {
        logger.logEmpty();
        logger.logSuccess("Android build finished");
        return value;
      }).catchError((error) {
        logger.logEmpty();
        logger.logError("Android build failed with error: $error");
        return 1;
      });

      results.add(androidResult);
    }

    if (builder.ios != null) {
      logger.logInfo("Building iOS binary");
      final iosResult = await builder.ios!.build().then((value) {
        logger.logEmpty();
        logger.logSuccess("iOS build finished");
        return value;
      }).catchError((error) {
        logger.logEmpty();
        logger.logError("iOS build failed with error: $error");
        return 1;
      });
      results.add(iosResult);
    }

    if (results.isEmpty) {
      logger.logError("No build results found.");
      return 1;
    }
    return results.reduce((value, element) => value + element);
  }

  Future<int> runPublisher(PublisherJob publisher, ConfigParser config) async {
    logger.logEmpty();
    List<int> results = [];

    if (publisher.fastlane != null) {
      logger.logInfo("Publishing binary with Fastlane");
      final fastlaneResult = await publisher.fastlane!.publish().then((value) {
        logger.logEmpty();
        logger.logSuccess("Fastlane publish process finished");
        return value;
      }).catchError((error) {
        logger.logEmpty();
        logger.logError("Fastlane publish failed with error: $error");
        return 1;
      });
      results.add(fastlaneResult);
    }

    if (publisher.firebase != null) {
      logger.logInfo("Publishing Android binary with Firebase");
      final firebaseResult = await publisher.firebase!.publish().then((value) {
        logger.logEmpty();
        logger.logSuccess("Firebase publish process finished");
        return value;
      }).catchError((error) {
        logger.logEmpty();
        logger.logError("Firebase publish failed with error: $error");
        return 1;
      });
      results.add(firebaseResult);
    }

    if (publisher.xcrun != null) {
      logger.logInfo("Publishing iOS binary with Xcrun");
      final xcrunResult = await publisher.xcrun!.publish().then((value) {
        logger.logEmpty();
        logger.logSuccess("Xcrun publish process finished");
        return value;
      }).catchError((error) {
        logger.logEmpty();
        logger.logError("Xcrun publish failed with error: $error");
        return 1;
      });
      results.add(xcrunResult);
    }

    if (publisher.github != null) {
      logger.logInfo("Publishing binary with Github");
      final githubResult = await publisher.github!.publish().then((value) {
        logger.logEmpty();
        logger.logSuccess("Github publish process finished");
        return value;
      }).catchError((error) {
        logger.logEmpty();
        logger.logError("Github Publish failed with error: $error");
        return 1;
      });
      results.add(githubResult);
    }

    if (results.isEmpty) {
      logger.logError("No publish results found.");
      return 1;
    }
    return results.reduce((value, element) => value + element);
  }
}
