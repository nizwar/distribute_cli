import 'dart:convert';
import 'dart:io';

import 'package:distribute_cli/app_publisher/fastlane/fastlane_android_publisher_arguments.dart';
import 'package:distribute_cli/app_publisher/xcrun/xcrun_ios_publisher_arguments.dart';
import 'package:distribute_cli/parsers/task_arguments.dart';
import 'package:yaml/yaml.dart';

import '../app_builder/android_builder/android_build_arguments.dart';
import '../app_builder/custom_builder/custom_build_arguments.dart';
import '../app_builder/ios_builder/ios_build_arguments.dart';
import '../app_publisher/firebase/firebase_android_publisher_arguments.dart';
import '../files.dart';

import 'job_arguments.dart';

/// A parser for configuration files used in the distribution process.
///
/// The `ConfigParser` class is responsible for parsing YAML configuration files,
/// converting them into structured objects, and providing access to tasks, environments,
/// and arguments defined in the configuration.
class ConfigParser {
  /// The output directory for distribution files.
  final String output;

  /// The list of tasks defined in the configuration.
  List<Task> tasks;

  /// The map of job arguments defined in the configuration.
  final Map<String, JobArguments>? arguments;

  /// The environment variables used in the configuration.
  Map<String, dynamic> environments;

  /// Creates a new `ConfigParser` instance.
  ///
  /// - [tasks]: The list of tasks defined in the configuration.
  /// - [arguments]: The map of job arguments defined in the configuration.
  /// - [environments]: The environment variables used in the configuration.
  /// - [output]: The output directory for distribution files (default is "distribution/").
  ConfigParser({
    required this.tasks,
    required this.arguments,
    required this.environments,
    this.output = "distribution/",
  });

  /// Creates a `ConfigParser` instance from a JSON object.
  ///
  /// - [json]: The JSON object containing the configuration data.
  factory ConfigParser.fromJson(Map<String, dynamic> json) {
    return ConfigParser(
      tasks: json["tasks"],
      environments: json["variables"] as Map<String, dynamic>,
      arguments: (json["arguments"] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as dynamic)),
    );
  }

  /// Creates a `ConfigParser` instance by parsing a YAML file.
  ///
  /// - [path]: The path to the YAML configuration file.
  ///
  /// Throws an exception if the file does not exist or if required keys are missing.
  factory ConfigParser.distributeYaml(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception("$path file not found, please run init command");
    }
    Map<String, dynamic> configJson =
        jsonDecode(jsonEncode(loadYaml(file.readAsStringSync())));
    List<Task> jobTasks;

    final environments = Map<String, dynamic>.from(Platform.environment.cast())
      ..addAll(
        (configJson["variables"] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(
              key, substituteVariables(value.toString(), Platform.environment)),
        ),
      );

    if (configJson["tasks"] == null) {
      throw Exception("tasks's key not found in $path");
    }
    if (configJson["name"] == null) {
      throw Exception("name key not found in $path");
    }
    if (configJson["description"] == null) {
      throw Exception("description key not found in $path");
    }

    Job parseJob(Map<String, dynamic> json) {
      final platform = json["platform"];
      final mode = json["mode"];
      final arguments = json["arguments"];
      final packageName = json["package_name"];
      final key = json["key"];

      if (mode == null) throw Exception("mode is required for each job");
      if (mode != "build" && mode != "publish") {
        throw Exception("Invalid mode for each job");
      }
      if (platform == null) {
        throw Exception("platform is required for each job");
      }
      if (packageName == null) {
        throw Exception("package_name is required for each job");
      }

      JobArguments? jobArgument;
      final isBuildMode = mode == "build";
      final isPublishMode = mode == "publish";

      if (!isBuildMode && !isPublishMode) {
        throw Exception("Invalid job mode");
      }
      switch (platform) {
        case "android":
          if (isBuildMode) {
            if (arguments != null) {
              jobArgument = AndroidBuildArgument.fromJson(
                  {...arguments, "package-name": packageName});
            } else {
              jobArgument = AndroidBuildArgument.defaultConfigs();
            }
          } else if (isPublishMode) {
            List<String>? publishers = arguments != null
                ? (arguments["publishers"] as List)
                    .map((item) => item.toString())
                    .toList()
                : null;
            if ((publishers)?.contains("fastlane") ?? false) {
              if (arguments != null) {
                jobArgument = FastlaneAndroidPublisherArguments.fromJson({
                  ...arguments,
                  "package-name": packageName,
                  "file-path":
                      arguments["file-path"] ?? Files.androidOutputApks.path,
                });
              } else {
                jobArgument = FastlaneAndroidPublisherArguments.defaultConfigs(
                    packageName);
              }
            } else if ((publishers)?.contains("firebase") ?? false) {
              if (arguments != null) {
                jobArgument = FirebaseAndroidPublisherArguments.fromJson({
                  ...arguments,
                  "package-name": packageName,
                  "file-path":
                      arguments["file-path"] ?? Files.androidOutputApks.path,
                });
              } else {
                final appId = arguments?["app"] as String?;
                if (appId == null) {
                  throw Exception("app id is required for firebase publisher");
                }
                jobArgument =
                    FirebaseAndroidPublisherArguments.defaultConfigs(appId);
              }
            } else {
              throw Exception("Invalid publisher for android");
            }
          }
          break;
        case "ios":
          if (isBuildMode) {
            jobArgument = arguments != null
                ? IOSBuildArgument.fromJson({
                    ...arguments,
                    "package-name": packageName,
                  })
                : IOSBuildArgument.defaultConfigs();
          } else if (isPublishMode) {
            if (arguments == null) {
              throw Exception("Arguments is required for ios publisher");
            }
            jobArgument = arguments != null
                ? XcrunIosPublisherArguments.fromJson({
                    ...arguments,
                    "package-name": packageName,
                    "file-path": arguments["file-path"] ??
                        Files.iosDistributionOutputDir.path,
                  })
                : XcrunIosPublisherArguments.defaultConfigs();
          }
          break;
        case "custom":
          if (arguments == null) {
            throw Exception("Custom build job must have arguments");
          }
          jobArgument = CustomBuildArgument.fromJson(
              {...arguments, "package-name": packageName});
          break;

        default:
          throw Exception(
              "Invalid platform for ${isBuildMode ? "build" : "publish"} mode");
      }

      final output = Job(
        name: json["name"] as String,
        description: json["description"],
        platform: platform,
        packageName: packageName,
        mode: JobMode.fromString(mode),
        environments: environments,
        arguments: jobArgument!,
        key: key,
      );
      return output;
    }

    jobTasks = (configJson["tasks"] as List)
        .map<Task>(
          (item) => Task(
            name: item["name"],
            jobs: (item["jobs"] as List)
                .map<Job>((item) => parseJob(item))
                .toList(),
            key: item["key"],
            description: item["description"],
          ),
        )
        .toList();

    return ConfigParser(
        tasks: jobTasks,
        arguments: (configJson["arguments"] as Map<String, dynamic>?)
            ?.map((key, value) => MapEntry(key, value as dynamic)),
        environments: environments);
  }
}

/// Substitutes variables in a string with their corresponding values from a map.
///
/// This function replaces placeholders in the format `${{VAR_NAME}}` or `${VAR_NAME}`
/// with the values of the corresponding variables from the provided map.
///
/// - [input]: The input string containing placeholders.
/// - [variables]: A map of variable names and their values (default is an empty map).
///
/// Returns the string with placeholders replaced by their corresponding values.
String substituteVariables(String? input,
    [Map<String, dynamic> variables = const {}]) {
  if (input == null) return "";

  // Pattern matches ${{VAR_NAME}} OR ${VAR_NAME}
  final pattern = RegExp(r'\$\{\{(\w+)\}\}|\$\{(\w+)\}');

  return input.replaceAllMapped(pattern, (match) {
    final varName = match.group(1) ?? match.group(2); // capture either style
    final value = variables[varName?.trim()];

    if (value != null) {
      return value.toString();
    } else {
      // If variable is not found, keep the original placeholder
      return match.group(0)!;
    }
  });
}
