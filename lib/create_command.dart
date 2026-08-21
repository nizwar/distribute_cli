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
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/build_info.dart';
import 'package:distribute_cli/parsers/config_parser.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:distribute_cli/prompt.dart';
import 'package:distribute_cli/version.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_codec/yaml_codec.dart';

import '../app_publisher/fastlane/arguments.dart' as fastlane_publisher;
import '../app_publisher/firebase/arguments.dart' as firebase_publisher;
import '../app_publisher/github/arguments.dart' as github_publisher;
import '../app_publisher/huawei/arguments.dart' as huawei_publisher;
import 'parsers/task_arguments.dart';

/// Returns the argument parser shared by the job creation commands.
///
/// [CreateTaskCommand] declares its own, narrower set; this one is for
/// `create job builder` and `create job publisher`, which each add their own
/// `-P`/`-T` on top.
///
/// - `--config` or `-c` - File to write to (defaults to `distribution.yaml`)
/// - `--wizard` or `-w` - Fill in the values interactively
/// - `--task-key` or `-t` - The task the job belongs to
/// - `--name` or `-n` - Name of the job
/// - `--key` or `-k` - Key the job is addressed by, as `task.key`
/// - `--description` or `-d` - Description text
/// - `--package-name` or `-p` - Package name (auto-detected from the project)
ArgParser get creatorArgParser => ArgParser(allowTrailingOptions: true)
  ..addOption(
    'config',
    abbr: 'c',
    help: 'Path to the configuration file.',
    defaultsTo: 'distribution.yaml',
  )
  ..addFlag(
    'wizard',
    abbr: 'w',
    help: "Fill in the values interactively.",
    defaultsTo: false,
  )
  ..addOption(
    "task-key",
    abbr: 't',
    help: "Option is used to specify the task for the command.",
  )
  ..addOption("name", abbr: 'n', help: "The name of the job to create.")
  ..addOption("key", abbr: 'k', help: "The key of the job to create.")
  ..addOption(
    "description",
    abbr: 'd',
    help: "The description of the job to create.",
  )
  ..addOption(
    "package-name",
    abbr: 'p',
    help: "Package name of the app to publish.",
    defaultsTo: BuildInfo.androidPackageName ??
        BuildInfo.iosBundleId ??
        "\${ANDROID_PACKAGE}",
  );

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
  String get description => "Create a new task in the configuration.";

  /// Name of the command.
  @override
  String get name => "task";

  /// Argument parser for the command.
  @override
  final ArgParser argParser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    )
    ..addOption(
      "name",
      abbr: "n",
      help: "The name of the task to create.",
    )
    ..addOption("key", abbr: "k", help: "The key of the task to create.")
    ..addFlag(
      "wizard",
      abbr: "w",
      help: "Fill in the values interactively.",
      defaultsTo: false,
    )
    ..addOption(
      "description",
      abbr: "d",
      help: "The description of the task to create.",
    );

  /// Runs the command to create a new task and update the config file.
  ///
  /// Returns `0` on success and `1` when the task could not be created.
  @override
  Future<int> run() async {
    final configPath = super.configPath;
    final file = File(configPath);
    if (!file.existsSync()) {
      logger.logError("Configuration file not found: $configPath");
      return 1;
    }

    final Map<String, dynamic> configJson;
    try {
      configJson = _loadYamlAsJson(file);
    } on ConfigException catch (e) {
      logger.logError(e.message);
      return 1;
    }
    configJson["tasks"] ??= [];
    final tasks = configJson["tasks"] as List<dynamic>;

    String? taskKey;
    String? taskName;
    String? taskDescription;

    bool isWizard = argResults?["wizard"] ?? false;

    Prompt? wizard;
    if (isWizard) {
      final prompt = wizard = openWizard('create task', configPath);
      final taken = tasks.map((task) => "${task["key"]}").toSet();

      if (taken.isNotEmpty) {
        logger.logDetail('existing keys: ${taken.join(", ")}');
        logger.logEmpty();
      }

      taskName = prompt.text('Task name');
      taskKey = prompt.text(
        'Task key',
        defaultValue: CreatorCommand.slugify(taskName),
        validate: (value) =>
            CreatorCommand.validateKey(value, taken: taken, what: 'task'),
      );
      taskDescription = prompt.text('Description', allowEmpty: true);

      logger.logEmpty();
      prompt.summary({
        'name': taskName,
        'key': taskKey,
        'description': taskDescription,
      });
      warnIfComments(file);
      logger.logEmpty();

      if (!prompt.confirm('Add this task to $configPath?')) {
        logger.logNote('nothing was written');
        return 0;
      }
    } else {
      taskKey = argResults?["key"];
      taskName = argResults?["name"];
      taskDescription = argResults?["description"];
    }

    final keyProblem = taskKey == null || taskKey.isEmpty
        ? null
        : CreatorCommand.validateKey(taskKey, taken: const {}, what: 'task');
    if (keyProblem != null) {
      logger.logError(keyProblem);
      return 1;
    }

    if ((taskKey?.isEmpty ?? true) || (taskName?.isEmpty ?? true)) {
      logger.logError("`key` and `name` are mandatory.");
      logger.logDetail("pass -n and -k, or use -w for the wizard");
      return 1;
    }

    if (tasks.any((task) => task["key"] == taskKey)) {
      logger.logError("Task with key $taskKey already exists.");
      return 1;
    }

    tasks.add(
      Task(
        name: taskName!,
        key: taskKey!,
        // Normalised so the wizard and the option form produce the same file:
        // an unanswered question and an unpassed option are the same thing.
        description:
            (taskDescription?.isEmpty ?? true) ? null : taskDescription,
        workflows: [],
        jobs: [],
      ).toJson(),
    );

    configJson["tasks"] = tasks;
    await _writeYaml(file, configJson, warn: wizard == null);

    logger.logSuccess("added task $taskKey to $configPath");
    if (isWizard) {
      logger.logDetail(
        'add a job with `distribute create job builder -w`',
      );
    }
    return 0;
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
  ///
  /// An *empty* document yields an empty map rather than a
  /// `type 'Null' is not a subtype of Map` crash, so `create` can bootstrap a
  /// configuration that `init` has not filled in yet.
  ///
  /// A document that parses to something other than a mapping — a list, a bare
  /// scalar — is refused. Treating it as empty would mean rewriting the file
  /// with nothing but `tasks:`, silently destroying whatever it held; that is
  /// what happens when `--config` is pointed at the wrong file.
  Map<String, dynamic> _loadYamlAsJson(File file) {
    final decoded = loadYaml(file.readAsStringSync());
    if (decoded == null) return <String, dynamic>{};
    if (decoded is! Map) {
      throw ConfigException(
        "'${file.path}' is not a distribute configuration: its contents are "
        "a ${decoded is List ? 'list' : 'single value'}, not a mapping. "
        "Refusing to overwrite it.",
      );
    }
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(decoded)) as Map);
  }

  /// Writes a JSON-compatible map to a YAML file.
  ///
  /// The document is re-encoded from scratch, which drops every comment and
  /// reflows the formatting. `distribution.yaml` is hand-maintained and
  /// committed, so that has to be said out loud rather than discovered in a
  /// diff. When [wizard] is given the user is asked first; the scripted path
  /// only warns, because blocking on a question would break automation that
  /// asked for the change explicitly.
  ///
  /// Pass [warn] as false when the caller has already warned itself, which is
  /// what the wizards do so the notice appears with the review rather than
  /// after the confirm.
  Future<void> _writeYaml(
    File file,
    Map<String, dynamic> configJson, {
    bool warn = true,
  }) async {
    if (warn) warnIfComments(file);
    await file.writeAsString(
      yamlEncode(configJson),
      encoding: utf8,
      mode: FileMode.write,
      flush: true,
    );
  }

  /// Says that comments are about to be lost. Returns whether it warned.
  ///
  /// A wizard calls this before its own confirm, so the user makes one
  /// informed decision instead of answering two questions in a row.
  bool warnIfComments(File file) {
    if (!file.existsSync()) return false;
    if (!_hasComments(file.readAsStringSync())) return false;
    logger.logWarning(
      'rewriting ${file.path} will drop its comments and reformat it',
    );
    return true;
  }

  /// Whether [yaml] carries comments that re-encoding would throw away.
  ///
  /// Deliberately errs towards warning: a `#` inside a quoted value survives
  /// the round trip, so this can warn when it did not have to, but it will not
  /// stay quiet while a real comment is deleted.
  static bool _hasComments(String yaml) =>
      RegExp(r'(^|\s)#', multiLine: true).hasMatch(yaml);

  /// Runs the command to create a job and update the config file.
  ///
  /// Returns `0` on success and `1` when the job could not be created.
  @override
  Future<int> run() async {
    final configPath = super.configPath;

    final file = File(configPath);
    if (!file.existsSync()) {
      logger.logError("Configuration file not found: $configPath");
      return 1;
    }

    final Map<String, dynamic> configJson;
    try {
      configJson = _loadYamlAsJson(file);
    } on ConfigException catch (e) {
      logger.logError(e.message);
      return 1;
    }
    // `variables:` is optional, so default to an empty map instead of handing
    // a null to Variables and crashing on the first lookup.
    final Variables variables = Variables(
      Map<String, dynamic>.from((configJson["variables"] as Map?) ?? const {}),
      globalResults,
    );
    final tasks = (configJson["tasks"] as List?) ?? [];

    String? taskKey;
    String? jobKey;
    String? jobName;
    String? packageName;
    String? description;
    String? appId;

    bool isWizard = argResults?["wizard"] ?? false;

    final kind = this is CreateBuilderCommand ? 'builder' : 'publisher';
    Prompt? wizard;
    int? pickedTaskIndex;

    if (isWizard) {
      if (tasks.isEmpty) {
        logger.logError("$configPath has no task to add a job to");
        logger.logDetail("run `distribute create task -w` first");
        return 1;
      }

      wizard = openWizard('create $kind job', configPath);

      // Picked from a numbered list rather than typed: a task key that does not
      // exist used to be discovered only after the question was answered, and
      // rejecting it meant restarting the wizard.
      final choices = [
        for (var i = 0; i < tasks.length; i++)
          (index: i, task: Map<String, dynamic>.from(tasks[i] as Map)),
      ];
      final chosen = wizard.select(
        'Which task does this job belong to?',
        choices,
        label: (c) => '${c.task["name"]}  ${c.task["key"]}',
        describe: (c) {
          final existing = (c.task["jobs"] as List?) ?? const [];
          if (existing.isEmpty) return 'no jobs yet';
          return existing.map((job) => "${job["key"]}").join(', ');
        },
      );
      // The position is what identifies the task, not the key: a configuration
      // with two tasks sharing a key would otherwise write the job into the
      // first one, whichever the user pointed at.
      pickedTaskIndex = chosen.index;
      final task = chosen.task;
      taskKey = "${task["key"]}";

      final taken = ((task["jobs"] as List?) ?? const [])
          .map((job) => "${job["key"]}")
          .toSet();

      logger.logEmpty();
      jobName = wizard.text('Job name', defaultValue: _suggestedJobName(kind));
      jobKey = wizard.text(
        'Job key',
        defaultValue: CreatorCommand.slugify(jobName),
        validate: (value) =>
            CreatorCommand.validateKey(value, taken: taken, what: 'job'),
      );
      description = wizard.text('Description', allowEmpty: true);

      // The detected package name is offered as a default, not forced: a
      // project can publish under a different id than the one in the Gradle
      // file, and the old wizard never gave the user the chance to say so.
      packageName = wizard.text(
        'Package name',
        defaultValue: BuildInfo.androidPackageName ??
            BuildInfo.iosBundleId ??
            "\${ANDROID_PACKAGE}",
      );
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

    final googleServiceFile = File(
      path.join("android", "app", "google-services.json"),
    );
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
          "No Android client found in google-services.json. Please provide package name manually.",
        );
      }
    }

    // The wizard validates as it asks; the option form has to be checked here,
    // or `-k my.key` writes a job that `run -o task.my.key` can never address.
    final keyProblem = CreatorCommand.validateKey(
      jobKey,
      taken: const {},
      what: 'job',
    );
    if (jobKey.isNotEmpty && keyProblem != null) {
      logger.logError(keyProblem);
      return 1;
    }

    if ((taskKey.isEmpty) ||
        (jobKey.isEmpty) ||
        (jobName.isEmpty) ||
        (packageName.isEmpty)) {
      logger.logError(
        "`task-key`, `key`, `package_name`, and `name` are mandatory.",
      );
      return 1;
    }

    final taskIndex =
        pickedTaskIndex ?? tasks.indexWhere((task) => task["key"] == taskKey);
    if (taskIndex == -1) {
      logger.logError("Task with key $taskKey not found.");
      return 1;
    }

    var task = tasks[taskIndex];
    var jobs = task["jobs"] ?? [];

    if (jobs.any((job) => job["key"] == jobKey)) {
      logger.logError("Job with key $jobKey already exists.");
      return 1;
    }

    BuilderJob? builderJob;

    if (this is CreateBuilderCommand) {
      List<String> platforms = <String>[];
      if (isWizard) {
        // iOS builds need Xcode, so it is only offered where it can run.
        final available = [
          'android',
          if (Platform.isMacOS) 'ios',
        ];
        logger.logEmpty();
        platforms = available.length == 1
            ? available
            : wizard!.multiSelect(
                'Which platforms should this job build?',
                available,
                label: (platform) => platform,
                describe: (platform) => platform == 'android'
                    ? 'APK or AAB via Gradle'
                    : 'IPA via Xcode',
                defaults: const ['android'],
              );
      } else if (argResults!["platform"] != null) {
        platforms = (argResults!["platform"] as List<String>).toList();
      }

      final supported = platforms
          .where((platform) => platform == 'android' || platform == 'ios')
          .toList();
      if (supported.isEmpty) {
        // Constructing BuilderJob with nothing set throws a message that never
        // mentions the option the user actually has to pass.
        logger.logError("a builder job needs at least one platform");
        logger.logDetail(
          Platform.isMacOS
              ? "pass -P android and/or -P ios, or use -w for the wizard"
              : "pass -P android, or use -w for the wizard",
        );
        return 1;
      }
      platforms = supported;

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
        // This used to read stdin directly, which meant it neither validated
        // the answer nor stopped at end-of-input like every other prompt.
        const descriptions = {
          'firebase': 'Firebase App Distribution',
          'fastlane': 'Play Store, via Fastlane supply',
          'xcrun': 'App Store Connect, via altool',
          'github': 'GitHub Releases',
          'huawei': 'Huawei AppGallery',
        };
        final available = [
          'firebase',
          'fastlane',
          if (Platform.isMacOS) 'xcrun',
          'github',
          'huawei',
        ];
        logger.logEmpty();
        tools = wizard!.multiSelect(
          'Where should this job publish to?',
          available,
          label: (tool) => tool,
          describe: (tool) => descriptions[tool]!,
        );
      } else if (argResults!["tools"] != null) {
        tools = (argResults!["tools"] as List<String>).toList();
      }

      const known = {'fastlane', 'firebase', 'xcrun', 'github', 'huawei'};
      final supported = tools
          .where((tool) => known.contains(tool))
          .where((tool) => tool != 'xcrun' || Platform.isMacOS)
          .toList();
      if (supported.isEmpty) {
        logger.logError("a publisher job needs at least one tool");
        logger.logDetail(
          "pass -T with one of: "
          "${known.where((t) => t != 'xcrun' || Platform.isMacOS).join(', ')}"
          ", or use -w for the wizard",
        );
        return 1;
      }
      tools = supported;

      publisherJob = PublisherJob(
        fastlane: tools.contains("fastlane") == true
            ? fastlane_publisher.Arguments.defaultConfigs(
                packageName,
                globalResults,
              )
            : null,
        firebase: tools.contains("firebase") == true
            ? firebase_publisher.Arguments.defaultConfigs(
                appId ?? "APP_ID",
                globalResults,
              )
            : null,
        xcrun: Platform.isMacOS
            ? tools.contains("xcrun") == true
                ? xcrun_publisher.Arguments.defaultConfigs(globalResults)
                : null
            : null,
        github: tools.contains("github") == true
            ? github_publisher.Arguments.defaultConfigs(globalResults)
            : null,
        huawei: tools.contains("huawei") == true
            ? huawei_publisher.Arguments.defaultConfigs(globalResults)
            : null,
      );
    } else {
      publisherJob = null;
    }

    if (builderJob == null && publisherJob == null) {
      logger.logError("Invalid job type. Use 'builder' or 'publisher'.");
      return 1;
    }

    if (wizard != null) {
      logger.logEmpty();
      wizard.summary({
        'task': taskKey,
        'name': jobName,
        'key': jobKey,
        'description': description,
        'package': packageName,
        kind == 'builder' ? 'platforms' : 'publishes to':
            _selectedTargets(builderJob, publisherJob).join(', '),
        'reference': '$taskKey.$jobKey',
      });
      warnIfComments(file);
      logger.logEmpty();

      if (!wizard.confirm('Add this job to $configPath?')) {
        logger.logNote('nothing was written');
        return 0;
      }
    }

    jobs.add(
      Job(
        name: jobName,
        key: jobKey,
        description: description.isEmpty ? null : description,
        packageName: packageName,
        builder: builderJob,
        publisher: publisherJob,
      ).toJson(),
    );

    tasks[taskIndex]["jobs"] = jobs;

    configJson["tasks"] = tasks;
    await _writeYaml(file, configJson, warn: wizard == null);

    logger.logSuccess("added $taskKey.$jobKey to $configPath");
    if (wizard != null) {
      logger.logDetail('run it with `distribute run -o $taskKey.$jobKey`');
    }
    return 0;
  }

  /// The platforms or tools the job ended up with, for the review block.
  static List<String> _selectedTargets(
    BuilderJob? builder,
    PublisherJob? publisher,
  ) =>
      [
        if (builder?.android != null) 'android',
        if (builder?.ios != null) 'ios',
        if (publisher?.firebase != null) 'firebase',
        if (publisher?.fastlane != null) 'fastlane',
        if (publisher?.xcrun != null) 'xcrun',
        if (publisher?.github != null) 'github',
        if (publisher?.huawei != null) 'huawei',
      ];

  /// A sensible starting name so the first question can be answered with enter.
  static String _suggestedJobName(String kind) =>
      kind == 'builder' ? 'Build' : 'Publish';

  /// Prints the wizard header and returns the prompt to drive it with.
  ///
  /// Every wizard opens the same way — what is being created, and which file it
  /// will be written to — so the user knows what is about to change before
  /// answering the first question.
  Prompt openWizard(String title, String configPath) {
    // A wizard under --quiet or --silent would hide the questions, the menus
    // and the review block while still blocking on answers — the user would be
    // staring at a cursor with no idea what is being asked.
    if (ColorizeLogger.verbosity.rank < LogVerbosity.normal.rank) {
      throw PromptAbortedException(
        'the wizard needs to print its questions, so it cannot run under '
        '--quiet or --silent. Pass the values as options instead.',
      );
    }

    final sep = LogSymbols.separator;
    logger.logInfo(
      ColorizeLogger.dim(
        ['distribute $packageVersion', title, configPath].join('  $sep  '),
      ),
    );
    logger.logEmpty();
    return Prompt(logger);
  }

  /// Turns a human readable name into a usable key.
  ///
  /// Keys end up in `task.job` references on the command line, so a dot or a
  /// space in one would make the reference ambiguous.
  static String slugify(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug;
  }

  /// Rejects a key that is unusable or already taken, for [Prompt.text].
  ///
  /// Returns the message to show, or null when the key is fine.
  static String? validateKey(
    String value, {
    required Set<String> taken,
    required String what,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      return 'a $what key may only contain letters, digits, "_" and "-"';
    }
    if (taken.contains(value)) return 'that $what key is already used';
    return null;
  }
}

/// Command to create a new publisher job.
class CreatePublisherCommand extends CreatorCommand {
  /// Description of the command.
  @override
  String get description => "Create a new publisher job.";

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
        "huawei",
      ],
      allowedHelp: {
        "firebase": "Publish to Firebase App Distribution.",
        "fastlane": "Publish using Fastlane.",
        if (Platform.isMacOS)
          "xcrun": "Publish using Xcode command line tools.",
        "github": "Publish to GitHub.",
        "huawei": "Publish to Huawei AppGallery.",
      },
    );
}

/// Command to create a new builder job.
class CreateBuilderCommand extends CreatorCommand {
  /// Description of the command.
  @override
  String get description => "Create a new builder job.";

  /// Name of the command.
  @override
  String get name => "builder";

  /// Argument parser for the command.
  @override
  final ArgParser argParser = creatorArgParser
    ..addMultiOption(
      "platform",
      abbr: 'P',
      // `custom` was offered here but a builder job only ever serialises
      // `android` and `ios`, so it was accepted and then dropped — silently
      // when combined with a real platform. `distribute build custom` remains
      // available as a direct command.
      help: "The platform to build for.",
      allowed: [if (Platform.isMacOS) "ios", "android"],
      allowedHelp: {
        if (Platform.isMacOS) "ios": "Build for iOS.",
        "android": "Build for Android.",
      },
    );
}
