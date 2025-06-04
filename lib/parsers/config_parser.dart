import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

import 'job_arguments.dart';
import 'task_arguments.dart';
import 'variables.dart';

/// A parser for configuration files used in the distribution process.
///
/// The [ConfigParser] class is responsible for parsing YAML configuration files,
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

  final ArgResults? globalResults;

  /// Creates a new [ConfigParser] instance.
  ///
  /// - [tasks]: The list of tasks defined in the configuration.
  /// - [arguments]: The map of job arguments defined in the configuration.
  /// - [environments]: The environment variables used in the configuration.
  /// - [output]: The output directory for distribution files (default is "distribution/").
  ConfigParser({
    required this.tasks,
    required this.arguments,
    required this.environments,
    required this.globalResults,
    this.output = "distribution/",
  });

  /// Creates a [ConfigParser] instance from a JSON object.
  ///
  /// - [json]: The JSON object containing the configuration data.
  factory ConfigParser.fromJson(
      Map<String, dynamic> json, ArgResults? globalResults) {
    return ConfigParser(
      globalResults: globalResults,
      tasks: json["tasks"],
      environments: json["variables"] as Map<String, dynamic>,
      arguments: (json["arguments"] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as dynamic)),
    );
  }

  /// Creates a [ConfigParser] instance by parsing a YAML file.
  ///
  /// - [path]: The path to the YAML configuration file.
  ///
  /// Throws an exception if the file does not exist or if required keys are missing.
  static Future<ConfigParser> distributeYaml(
      String path, ArgResults? globalResults) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception("$path file not found, please run init command");
    }
    Map<String, dynamic> configJson =
        jsonDecode(jsonEncode(loadYaml(file.readAsStringSync())));
    List<Task> jobTasks;

    final yamlVariables = Map<String, dynamic>.from(configJson["variables"]);
    final environments = Map<String, dynamic>.from(Platform.environment.cast());
    for (var key in yamlVariables.keys) {
      await Variables.processBySystem(
              yamlVariables[key].toString(), globalResults)
          .then((value) {
        yamlVariables[key] = value;
      });
    }
    environments.addAll(yamlVariables);

    stdout.writeln(JsonEncoder.withIndent("   ").convert(environments));

    Variables variables = Variables(environments, globalResults);

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
      Map<String, dynamic>? builder =
          json.containsKey("builder") ? json["builder"] : null;
      Map<String, dynamic>? publisher =
          json.containsKey("publisher") ? json["publisher"] : null;
      final packageName = json["package_name"];
      final key = json["key"];

      if (packageName == null) {
        throw Exception("package_name is required for each job");
      }

      BuilderJob? builderArguments;
      PublisherJob? publisherArguments;

      if (builder != null) {
        builderArguments = BuilderJob.fromJson(builder, variables);
      }
      if (publisher != null) {
        publisherArguments = PublisherJob.fromJson(publisher, variables);
      }

      final output = Job(
        name: json["name"] as String,
        description: json["description"],
        packageName: packageName,
        environments: environments,
        builder: builderArguments,
        publisher: publisherArguments,
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
            workflows: item["workflows"] != null
                ? List<String>.from(item["workflows"])
                : null,
            description: item["description"],
          ),
        )
        .toList();

    return ConfigParser(
      globalResults: globalResults,
      tasks: jobTasks,
      arguments: (configJson["arguments"] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, value as dynamic)),
      environments: environments,
    );
  }
}
