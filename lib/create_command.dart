import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/app_builder/ios/arguments.dart' as ios_arguments;
import 'package:distribute_cli/app_publisher/xcrun/arguments.dart'
    as xcrun_publisher;
import 'package:distribute_cli/command.dart';
import 'package:distribute_cli/parsers/build_info.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_codec/yaml_codec.dart';

import '../app_publisher/fastlane/arguments.dart' as fastlane_publisher;
import '../app_publisher/firebase/arguments.dart' as firebase_publisher;
import '../app_publisher/github/arguments.dart' as github_publisher;
import 'parsers/task_arguments.dart';

/// Returns an argument parser configured for job and task creation commands.
///
/// This parser includes common options used across all creation commands:
/// - `--wizard` or `-w` - Use interactive wizard mode for creation
/// - `--task-key` or `-t` - Specify the task key for job creation
/// - `--name` or `-n` - Set the name of the task or job
/// - `--key` or `-k` - Set the unique key identifier
/// - `--description` or `-d` - Set the description text
/// - `--package-name` or `-p` - Set the package name (auto-detected from project)
ArgParser get creatorArgParser => ArgParser(allowTrailingOptions: true)
  ..addFlag('wizard',
      abbr: 'w',
      help: "Use the wizard to create a task or job.",
      defaultsTo: false)
  ..addOption("task-key",
      abbr: 't', help: "Option is used to specify the task for the command.")
  ..addOption("name", abbr: 'n', help: "The name of the job to create.")
  ..addOption("key", abbr: 'k', help: "The key of the job to create.")
  ..addOption("description",
      abbr: 'd', help: "The description of the job to create.")
  ..addOption("package-name",
      abbr: 'p',
      help: "Package name of the app to publish.",
      defaultsTo: BuildInfo.androidPackageName ??
          BuildInfo.iosBundleId ??
          "\${ANDROID_PACKAGE}");

/// Command to create new tasks and jobs for the distribution configuration.
///
/// The `CreateCommand` serves as the entry point for creation subcommands,
/// providing access to task and job creation wizards. It helps users build
/// their distribution configuration by adding new tasks and jobs interactively
/// or through command-line options.
class CreateCommand extends Commander {
  /// Creates a CreateCommand and registers task and job creation subcommands.
  ///
  /// Available subcommands:
  /// - `task` - Create a new distribution task
  /// - `job` - Create a new job within an existing task
  CreateCommand() {
    addSubcommand(CreateTaskCommand());
    addSubcommand(CreateJobCommand());
  }

  /// The description of the create command shown in help text
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
        abbr: "n", help: "The name of the task or job to create.")
    ..addOption("key", abbr: "k", help: "The key of the task or job to create.")
    ..addFlag("wizard",
        abbr: "w",
        help: "Use the wizard to create a task or job.",
        defaultsTo: false)
    ..addOption("description",
        abbr: "d", help: "The description of the task or job to create.");

  /// Runs the command to create a new task and update the config file.
  @override
  Future<void> run() async {
    final configPath = globalResults?["config"] ?? "distribution.yaml";
    final file = File(configPath);
    if (!file.existsSync()) {
      logger.logError("Configuration file not found: $configPath");
      return;
    }

    final configJson = _loadYamlAsJson(file);
    configJson["tasks"] ??= [];
    final tasks = configJson["tasks"] as List<dynamic>;

    String? taskKey;
    String? taskName;
    String? taskDescription;

    bool isWizard = argResults?["wizard"] ?? false;

    if (isWizard) {
      logger.logInfo("Starting task creation wizard...");
      logger.logInfo("Available tasks:");
      for (var task in tasks) {
        logger.logInfo("- ${task["name"]} (Key: ${task["key"]})");
      }
      logger.logEmpty();
      logger.logInfo("Please provide the following details:");
      taskName = await prompt("Enter new task name");
      taskKey = await prompt("Enter new task key");
      taskDescription =
          await prompt("Enter new task description", nullable: true);
    } else {
      taskKey = argResults?["key"];
      taskName = argResults?["name"];
      taskDescription = argResults?["description"];
    }

    if ((taskKey?.isEmpty ?? true) || (taskName?.isEmpty ?? true)) {
      logger.logError("`key` and `name` are mandatory.");
      return;
    }

    if (tasks.any((task) => task["key"] == taskKey)) {
      logger.logError("Task with key $taskKey already exists.");
      return;
    }

    tasks.add(Task(
        name: taskName!,
        key: taskKey!,
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
    String configPath = globalResults?["config"] ?? "distribution.yaml";

    final file = File(configPath);
    if (!file.existsSync()) {
      logger.logError("Configuration file not found: $configPath");
      return;
    }

    var configJson = _loadYamlAsJson(file);
    final Variables variables =
        Variables(configJson["variables"], globalResults);
    var tasks = configJson["tasks"] ?? [];

    String? taskKey;
    String? jobKey;
    String? jobName;
    String? packageName;
    String? description;
    String? appId;

    bool isWizard = argResults?["wizard"] ?? false;

    if (isWizard) {
      logger.logInfo("Starting job creation wizard...");
      logger.logInfo("Available tasks:");
      for (var task in tasks) {
        logger.logInfo("${task["key"]} (${task["name"]})");
        for (var job in task["jobs"] ?? []) {
          logger.logInfo(" | ${job["key"]} - ${job["name"]}");
        }
      }
      logger.logEmpty();
      logger.logInfo("Please provide the following details:");
      taskKey = await prompt("Enter task key");
      if (tasks.indexWhere((task) => task["key"] == taskKey) == -1) {
        logger.logError("Task with key $taskKey not found.");
        return;
      }
      jobKey = await prompt("Enter job key");
      jobName = await prompt("Enter job name");
      description = await prompt("Enter job description", nullable: true);
      packageName =
          BuildInfo.androidPackageName ?? await prompt("Enter package name");
    } else {
      taskKey = argResults?["task-key"];
      jobKey = argResults?["key"];
      jobName = argResults?["name"];
      packageName = argResults?["package-name"];
      description = argResults?["description"];
    }

    taskKey = await variables.process(taskKey ?? "");
    jobKey = await variables.process(jobKey ?? "");
    jobName = await variables.process(jobName ?? "");
    description = await variables.process(description ?? "");
    packageName = await variables.process(packageName ?? "\${ANDROID_PACKAGE}");

    final googleServiceFile =
        File(path.join("android", "app", "google-services.json"));
    if (googleServiceFile.existsSync()) {
      final googleService = jsonDecode(googleServiceFile.readAsStringSync());
      final List clients = googleService["client"];
      final client = clients.firstWhere(
        (client) =>
            client["client_info"]["android_client_info"]["package_name"] ==
            packageName,
        orElse: () => {},
      );
      if (client.isNotEmpty) {
        appId = client["client_info"]["mobilesdk_app_id"];
      } else {
        logger.logWarning(
            "No Android client found in google-services.json. Please provide package name manually.");
      }
    }

    if ((taskKey.isEmpty) ||
        (jobKey.isEmpty) ||
        (jobName.isEmpty) ||
        (packageName.isEmpty)) {
      logger.logError(
          "`task-key`, `key`, `package_name`, and `name` are mandatory.");
      return;
    }

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

    BuilderJob? builderJob;

    if (this is CreateBuilderCommand) {
      List<String> platforms = <String>[];
      if (isWizard) {
        if (Platform.isMacOS) {
          final input =
              await prompt("Enter platforms (android, ios)", nullable: true);
          if (input.isNotEmpty) {
            platforms =
                input.split(",").map((platform) => platform.trim()).toList();
          }
        } else {
          platforms.add("android");
        }
      } else if (argResults!["platform"] != null) {
        platforms = (argResults!["platform"] as List<String>).toList();
      }
      builderJob = BuilderJob(
        android: platforms.contains("android") == true
            ? android_arguments.Arguments.defaultConfigs(globalResults)
            : null,
        ios: platforms.contains("ios") == true
            ? ios_arguments.Arguments.defaultConfigs(globalResults)
            : null,
      );
    } else {
      builderJob = null;
    }

    PublisherJob? publisherJob;

    if (this is CreatePublisherCommand) {
      List<String> tools = <String>[];

      if (isWizard) {
        logger.logInfo("Available tools for publisher job:");
        logger.logInfo("- firebase: Publish to Firebase App Distribution.");
        logger.logInfo("- fastlane: Publish using Fastlane.");
        if (Platform.isMacOS) {
          logger.logInfo("- xcrun: Publish using Xcode command line tools.");
        }
        logger.logInfo("- github: Publish to GitHub.");
        logger.logEmpty();
        logger.logInfo(
            "Please select the tools you want to use (comma-separated):");
        final input = stdin.readLineSync();
        if (input != null && input.isNotEmpty) {
          tools = input.split(",").map((tool) => tool.trim()).toList();
        }
      } else if (argResults!["tools"] != null) {
        tools = (argResults!["tools"] as List<String>).toList();
      }

      publisherJob = PublisherJob(
        fastlane: tools.contains("fastlane") == true
            ? fastlane_publisher.Arguments.defaultConfigs(
                packageName, globalResults)
            : null,
        firebase: tools.contains("firebase") == true
            ? firebase_publisher.Arguments.defaultConfigs(
                appId ?? "APP_ID", globalResults)
            : null,
        xcrun: Platform.isMacOS
            ? tools.contains("xcrun") == true
                ? xcrun_publisher.Arguments.defaultConfigs(globalResults)
                : null
            : null,
        github: tools.contains("github") == true
            ? github_publisher.Arguments.defaultConfigs(globalResults)
            : null,
      );
    } else {
      publisherJob = null;
    }

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

  Future<String> prompt(String message, {bool nullable = false}) async {
    stdout.write("$message${nullable ? " (Optional)" : ""}: ");
    final value = stdin.readLineSync();
    if ((value == null || value.isEmpty) && !nullable) {
      logger.logError("Input cannot be empty.");
      return prompt(message);
    }
    return value ?? "";
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
