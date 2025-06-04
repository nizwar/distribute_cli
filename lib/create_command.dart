import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/app_builder/ios/arguments.dart' as ios_arguments;
import 'package:distribute_cli/app_publisher/xcrun/arguments.dart'
    as xcrun_publisher;
import 'package:distribute_cli/command.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_codec/yaml_codec.dart';

import '../app_publisher/fastlane/arguments.dart' as fastlane_publisher;
import '../app_publisher/firebase/arguments.dart' as firebase_publisher;
import '../app_publisher/github/arguments.dart' as github_publisher;
import 'parsers/task_arguments.dart';

/// Returns an [ArgParser] configured for job creation commands.
ArgParser get creatorArgParser => ArgParser(allowTrailingOptions: true)
  ..addOption("task-key",
      abbr: 't',
      help: "Option is used to specify the task for the command.",
      mandatory: true)
  ..addOption("name",
      abbr: 'n', help: "The name of the job to create.", mandatory: true)
  ..addOption("key",
      abbr: 'k', help: "The key of the job to create.", mandatory: true)
  ..addOption("description",
      abbr: 'd', help: "The description of the job to create.")
  ..addOption("package_name",
      abbr: 'p',
      help: "Package name of the app to publish.",
      defaultsTo: "com.example.app");

/// Command to create a new task or job. Entry point for 'create' subcommands.
class CreateCommand extends Commander {
  /// Creates a [CreateCommand] and adds subcommands for task and job creation.
  CreateCommand() {
    addSubcommand(CreateTaskCommand());
    addSubcommand(CreateJobCommand());
  }

  /// Description of the command.
  @override
  String get description => "Create a new task or job.";

  /// Name of the command.
  @override
  String get name => "create";
}

/// Command to create a new task.
class CreateTaskCommand extends CreatorCommand {
  /// Description of the command.
  @override
  String get description => "Create a new task or job.";

  /// Name of the command.
  @override
  String get name => "task";

  /// Argument parser for the command.
  @override
  final ArgParser argParser = ArgParser()
    ..addOption("name",
        abbr: "n",
        help: "The name of the task or job to create.",
        mandatory: true)
    ..addOption("key",
        abbr: "k",
        help: "The key of the task or job to create.",
        mandatory: true)
    ..addOption("description",
        abbr: "d", help: "The description of the task or job to create.");

  /// Runs the command to create a new task and update the config file.
  @override
  Future<void> run() async {
    final taskKey = argResults!["key"]!;
    final taskName = argResults!["name"]!;
    final taskDescription = argResults?["description"];
    final configPath = globalResults?["config"] ?? "distribution.yaml";

    final file = File(configPath);
    if (!file.existsSync()) {
      logger.logError("Configuration file not found: $configPath");
      return;
    }

    final configJson = _loadYamlAsJson(file);
    configJson["tasks"] ??= [];
    final tasks = configJson["tasks"] as List<dynamic>;

    if (tasks.any((task) => task["key"] == taskKey)) {
      logger.logError("Task with key $taskKey already exists.");
      return;
    }

    tasks.add(Task(
        name: taskName,
        key: taskKey,
        description: taskDescription,
        workflows: [],
        jobs: []).toJson());

    configJson["tasks"] = tasks;
    await _writeYaml(file, configJson);
    logger.logSuccess("Task created successfully: $taskName");
  }
}

/// Command to create a new job. Adds subcommands for publisher and builder jobs.
class CreateJobCommand extends Commander {
  /// Creates a [CreateJobCommand] and adds subcommands for publisher and builder jobs.
  CreateJobCommand() {
    addSubcommand(CreatePublisherCommand());
    addSubcommand(CreateBuilderCommand());
  }

  /// Description of the command.
  @override
  String get description => "Create a new job.";

  /// Name of the command.
  @override
  String get name => "job";
}

/// Abstract base class for commands that create jobs or tasks.
abstract class CreatorCommand extends Commander {
  /// Loads a YAML file and returns its contents as a JSON-compatible map.
  Map<String, dynamic> _loadYamlAsJson(File file) =>
      jsonDecode(jsonEncode(loadYaml(file.readAsStringSync())));

  /// Writes a JSON-compatible map to a YAML file.
  Future<void> _writeYaml(File file, Map<String, dynamic> configJson) =>
      file.writeAsString(yamlEncode(configJson),
          encoding: utf8, mode: FileMode.write, flush: true);

  /// Runs the command to create a job and update the config file.
  @override
  Future<void> run() async {
    final taskKey = argResults!["task-key"]!;
    final jobKey = argResults!["key"]!;
    final jobName = argResults!["name"]!;
    final packageName = argResults!["package_name"]!;
    final description = argResults?["description"];
    final configPath = globalResults?["config"] ?? "distribution.yaml";

    final file = File(configPath);
    if (!file.existsSync()) {
      logger.logError("Configuration file not found: $configPath");
      return;
    }

    var configJson = _loadYamlAsJson(file);
    var tasks = configJson["tasks"] ?? [];

    final taskIndex = tasks.indexWhere((task) => task["key"] == taskKey);
    if (taskIndex == -1) {
      logger.logError("Task with key $taskKey not found.");
      return;
    }

    var task = tasks[taskIndex];
    var jobs = task["jobs"] ?? [];

    if (jobs.any((job) => job["key"] == jobKey)) {
      logger.logError("Job with key $jobKey already exists.");
      return;
    }

    final builderJob = this is CreateBuilderCommand
        ? BuilderJob(
            android:
                (argResults!["platform"] as List?)?.contains("android") == true
                    ? android_arguments.Arguments.defaultConfigs()
                    : null,
            ios: (argResults!["platform"] as List?)?.contains("ios") == true
                ? ios_arguments.Arguments.defaultConfigs()
                : null,
          )
        : null;
    final publisherJob = this is CreatePublisherCommand
        ? PublisherJob(
            fastlane:
                (argResults!["tools"] as List?)?.contains("fastlane") == true
                    ? fastlane_publisher.Arguments.defaultConfigs(packageName)
                    : null,
            firebase:
                (argResults!["tools"] as List?)?.contains("firebase") == true
                    ? firebase_publisher.Arguments.defaultConfigs("APP_ID")
                    : null,
            xcrun: (argResults!["tools"] as List?)?.contains("xcrun") == true
                ? xcrun_publisher.Arguments.defaultConfigs()
                : null,
            github: (argResults!["tools"] as List?)?.contains("github") == true
                ? github_publisher.Arguments.defaultConfigs()
                : null,
          )
        : null;

    if (builderJob == null && publisherJob == null) {
      logger.logError("Invalid job type. Use 'builder' or 'publisher'.");
      return;
    }

    jobs.add(Job(
            name: jobName,
            key: jobKey,
            description: description,
            packageName: packageName,
            builder: builderJob,
            publisher: publisherJob)
        .toJson());

    tasks[taskIndex]["jobs"] = jobs;

    configJson["tasks"] = tasks;
    await _writeYaml(file, configJson);
    logger.logSuccess("Job created successfully: $jobName");
  }
}

/// Command to create a new publisher job.
class CreatePublisherCommand extends CreatorCommand {
  /// Description of the command.
  @override
  String get description => "Create a new publisher task or job.";

  /// Name of the command.
  @override
  String get name => "publisher";

  /// Argument parser for the command.
  @override
  final ArgParser argParser = creatorArgParser
    ..addMultiOption(
      "tools",
      abbr: 'T',
      help: "The tools to use for the publisher.",
      allowed: [
        "firebase",
        "fastlane",
        if (Platform.isMacOS) "xcrun",
        "github",
      ],
      allowedHelp: {
        "firebase": "Publish to Firebase App Distribution.",
        "fastlane": "Publish using Fastlane.",
        if (Platform.isMacOS)
          "xcrun": "Publish using Xcode command line tools.",
        "github": "Publish to GitHub."
      },
    );
}

/// Command to create a new builder job.
class CreateBuilderCommand extends CreatorCommand {
  /// Description of the command.
  @override
  String get description => "Create a new builder task or job.";

  /// Name of the command.
  @override
  String get name => "builder";

  /// Argument parser for the command.
  @override
  final ArgParser argParser = creatorArgParser
    ..addMultiOption(
      "platform",
      abbr: 'P',
      help: "The platform to build for.",
      allowed: [if (Platform.isMacOS) "ios", "android", "custom"],
      allowedHelp: {
        if (Platform.isMacOS) "ios": "Build for iOS.",
        "android": "Build for Android.",
        "custom": "Build for custom platforms."
      },
    );
}
