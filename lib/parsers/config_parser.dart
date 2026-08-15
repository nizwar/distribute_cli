import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

import '../changelog_command.dart';
import 'builtin_variables.dart';
import 'changelog.dart';
import 'job_arguments.dart';
import 'notification_config.dart';
import 'task_arguments.dart';
import 'variables.dart';

/// Raised when `distribution.yaml` is structurally invalid.
///
/// Carries a message that is meant to be shown directly to the user, so it
/// should always name the offending key and, when possible, how to fix it.
class ConfigException implements Exception {
  /// Human readable explanation of what is wrong with the configuration.
  final String message;

  /// Creates a configuration error carrying [message].
  ConfigException(this.message);

  @override
  String toString() => message;
}

/// A parser for YAML configuration files used in the distribution process.
///
/// The `ConfigParser` class is responsible for parsing YAML configuration files,
/// converting them into structured objects, and providing access to tasks, environments,
/// and arguments defined in the configuration. It handles variable substitution
/// and validates required configuration fields.
class ConfigParser {
  /// The output directory for distribution files
  ///
  /// Defaults to "distribution" if not specified in the configuration
  final String output;

  /// The list of tasks defined in the configuration
  ///
  /// Each task contains multiple jobs that define build and publish operations
  List<Task> tasks;

  /// The raw `arguments:` mapping, when the configuration declares one.
  ///
  /// Nothing consumes this yet — it is parsed so the key is not rejected, and
  /// `distribute validate` warns that it has no effect. It was previously typed
  /// as `Map<String, JobArguments>` while being populated with raw maps, which
  /// crashed with a type error on any configuration that used it.
  final Map<String, dynamic>? arguments;

  /// The environment variables used in the configuration
  ///
  /// Combines system environment variables with variables defined in the config file
  Map<String, dynamic> environments;

  /// Global command line argument results from the CLI parser
  ///
  /// Used for accessing global flags like verbose mode
  final ArgResults? globalResults;

  /// Notifications delivered once the whole run has finished.
  final List<NotificationConfig> notifications;

  /// Raw `changelog:` mapping, or an empty map when the section is absent.
  ///
  /// Left unparsed here so `ChangelogSettings` owns its own validation, the
  /// same way `AiConfig` owns the `ai:` section.
  final Map<String, dynamic> changelog;

  /// Raw `ai:` mapping, or an empty map when the section is absent.
  ///
  /// Left unparsed here so `AiConfig` owns the layering between this section,
  /// the machine-wide store, the environment, and the command line flags.
  final Map<String, dynamic> ai;

  /// Variable resolver bound to [environments], reused by consumers that need
  /// to expand placeholders after parsing (notifications, validation).
  final Variables variables;

  /// Creates a new ConfigParser instance.
  ///
  /// Parameters:
  /// - `tasks` - The list of tasks defined in the configuration
  /// - `arguments` - The map of job arguments defined in the configuration
  /// - `environments` - The environment variables used in the configuration
  /// - `globalResults` - Global command line argument results
  /// - `notifications` - Run level notifications
  /// - `output` - The output directory for distribution files (defaults to "distribution")
  ConfigParser({
    required this.tasks,
    required this.arguments,
    required this.environments,
    required this.globalResults,
    required this.variables,
    this.notifications = const [],
    this.ai = const {},
    this.changelog = const {},
    this.output = "distribution",
  });

  /// Creates a ConfigParser instance by parsing a YAML file.
  ///
  /// This method reads and parses a YAML configuration file, processes variables,
  /// validates required fields, and creates a complete ConfigParser instance.
  ///
  /// Parameters:
  /// - `path` - The path to the YAML configuration file
  /// - `globalResults` - Global command line argument results
  ///
  /// Returns a new ConfigParser instance with the parsed configuration
  ///
  /// Throws a [ConfigException] describing the offending key when the file is
  /// missing, is not valid YAML, or does not match the expected structure.
  static Future<ConfigParser> distributeYaml(
    String path,
    ArgResults? globalResults,
  ) async {
    final file = File(path);
    if (!file.existsSync()) {
      // A directory here is almost always a `--config` pointed one level too
      // high; saying "not found" about something that is plainly there sends
      // the reader looking for the wrong problem.
      if (FileSystemEntity.isDirectorySync(path)) {
        throw ConfigException(
          "'$path' is a directory, not a configuration file. "
          "Point --config at the YAML file itself.",
        );
      }
      throw ConfigException(
        "Configuration file '$path' not found. Run `distribute init` to create one.",
      );
    }

    final Map<String, dynamic> configJson;
    try {
      final decoded = loadYaml(file.readAsStringSync());
      if (decoded == null) {
        throw ConfigException("Configuration file '$path' is empty.");
      }
      if (decoded is! Map) {
        throw ConfigException(
          "Configuration file '$path' must contain a YAML mapping at the root.",
        );
      }
      configJson = Map<String, dynamic>.from(jsonDecode(jsonEncode(decoded)));
    } on YamlException catch (e) {
      throw ConfigException("Invalid YAML in '$path': ${e.message}");
    }

    _requireString(configJson, "name", path);
    _requireString(configJson, "description", path);

    final rawVariables = configJson["variables"];
    if (rawVariables != null && rawVariables is! Map) {
      throw ConfigException(
        "'variables' in '$path' must be a mapping of KEY: value pairs.",
      );
    }

    // `variables` is optional: an empty map keeps every downstream lookup valid.
    final yamlVariables = Map<String, dynamic>.from(
      (rawVariables as Map?) ?? const {},
    );
    final environments = Map<String, dynamic>.from(Platform.environment.cast());
    // Iterating a copy of the keys: the loop removes entries as it goes.
    for (final key in yamlVariables.keys.toList()) {
      // A key written with no value — `FIREBASE_TOKEN:` — is a declaration, not
      // an assignment. Overwriting the exported variable with an empty string
      // used to blank the real credential, resolve the placeholder to nothing,
      // and let `validate` report no problems.
      if (yamlVariables[key] == null) {
        yamlVariables.remove(key);
        continue;
      }
      yamlVariables[key] = await Variables.processBySystem(
        yamlVariables[key]?.toString(),
        globalResults,
      );
    }
    environments.addAll(yamlVariables);

    // `${{CHANGELOG}}` reads the history lazily, but it has to know the range
    // and formatting the project asked for before anything resolves it.
    final changelogSection =
        _parseSection(configJson["changelog"], "changelog", path);
    BuiltinVariables.changelogOptions = _changelogOptions(
      changelogSection,
      path,
    );
    // `changelog: ai: true` means the variable is polished on every publish.
    // Installed through a callback so this file keeps no dependency on the AI
    // adapters, and a project that never asks for it never loads them.
    try {
      installChangelogPolisher(
        changelogSection: changelogSection,
        aiSection: _parseAi(configJson["ai"], path),
      );
    } on ArgumentError catch (e) {
      throw ConfigException("${e.message} (in '$path')");
    }

    final variables = Variables(environments, globalResults);

    final rawTasks = configJson["tasks"];
    if (rawTasks == null) {
      throw ConfigException("'tasks' key not found in '$path'.");
    }
    if (rawTasks is! List) {
      throw ConfigException("'tasks' in '$path' must be a list.");
    }
    if (rawTasks.isEmpty) {
      throw ConfigException(
          "'tasks' in '$path' must contain at least one task.");
    }

    final jobTasks = <Task>[];
    final seenTaskKeys = <String>{};

    for (var taskIndex = 0; taskIndex < rawTasks.length; taskIndex++) {
      final rawTask = rawTasks[taskIndex];
      final taskLabel = "tasks[$taskIndex]";
      if (rawTask is! Map) {
        throw ConfigException("$taskLabel in '$path' must be a mapping.");
      }
      final task = Map<String, dynamic>.from(rawTask);

      final taskName = _requireString(task, "name", path, context: taskLabel);
      final taskKey = _requireString(task, "key", path, context: taskLabel);

      if (!seenTaskKeys.add(taskKey)) {
        throw ConfigException(
          "Duplicate task key '$taskKey' in '$path'. Task keys must be unique.",
        );
      }

      final rawJobs = task["jobs"];
      if (rawJobs is! List || rawJobs.isEmpty) {
        throw ConfigException(
          "$taskLabel ('$taskKey') in '$path' must define a non-empty 'jobs' list.",
        );
      }

      final jobs = <Job>[];
      final seenJobKeys = <String>{};
      for (var jobIndex = 0; jobIndex < rawJobs.length; jobIndex++) {
        final rawJob = rawJobs[jobIndex];
        final jobLabel = "$taskLabel.jobs[$jobIndex]";
        if (rawJob is! Map) {
          throw ConfigException("$jobLabel in '$path' must be a mapping.");
        }
        final job = _parseJob(
          Map<String, dynamic>.from(rawJob),
          variables: variables,
          environments: environments,
          path: path,
          label: jobLabel,
        );
        if (job.key != null && !seenJobKeys.add(job.key!)) {
          throw ConfigException(
            "Duplicate job key '${job.key}' in task '$taskKey' of '$path'. "
            "Job keys must be unique within a task.",
          );
        }
        jobs.add(job);
      }

      final rawWorkflows = task["workflows"];
      if (rawWorkflows != null && rawWorkflows is! List) {
        throw ConfigException(
          "Task '$taskKey' in '$path' has a 'workflows' that is not a list. "
          "Write it as a list of job keys.",
        );
      }
      final workflows = rawWorkflows == null
          ? null
          : [
              for (final entry in rawWorkflows as List)
                if (entry is String)
                  entry
                else
                  throw ConfigException(
                    "Task '$taskKey' in '$path' lists a workflow entry that is "
                    "not a job key: '$entry'.",
                  ),
            ];

      if (workflows != null) {
        for (final workflow in workflows) {
          if (!jobs.any((job) => job.key == workflow)) {
            throw ConfigException(
              "Task '$taskKey' in '$path' lists workflow '$workflow' but no job "
              "with that key exists. Available job keys: "
              "${jobs.map((job) => job.key).whereType<String>().join(', ')}.",
            );
          }
        }
      }

      jobTasks.add(
        Task(
          name: taskName,
          key: taskKey,
          jobs: jobs,
          workflows: workflows,
          description:
              _asString(task["description"], "$taskLabel.description", path),
        ),
      );
    }

    final rawArguments = configJson["arguments"];
    if (rawArguments != null && rawArguments is! Map) {
      throw ConfigException("'arguments' in '$path' must be a mapping.");
    }

    return ConfigParser(
      globalResults: globalResults,
      tasks: jobTasks,
      arguments: (rawArguments as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value as dynamic),
      ),
      environments: environments,
      variables: variables,
      notifications: _parseNotifications(configJson["notifications"], path),
      ai: _parseAi(configJson["ai"], path),
      changelog: changelogSection,
    );
  }

  /// Reads a YAML file as a mutable JSON-compatible map.
  ///
  /// Shared with the commands that rewrite the configuration, so they all treat
  /// an empty or non-mapping document the same way.
  static Map<String, dynamic> readRawYaml(File file) {
    final decoded = loadYaml(file.readAsStringSync());
    if (decoded is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(decoded)) as Map);
  }

  /// Validates the optional top level `ai:` section.
  static Map<String, dynamic> _parseAi(dynamic raw, String path) =>
      _parseSection(raw, "ai", path);

  /// Reads the subset of `changelog:` that `${{CHANGELOG}}` needs.
  ///
  /// The rest of the section belongs to the `changelog` command; only the
  /// options that change what the variable expands to are read here.
  static ChangelogOptions _changelogOptions(
    Map<String, dynamic> section,
    String path,
  ) {
    bool flag(String key, {bool defaultValue = false}) {
      final raw = section[key];
      if (raw == null) return defaultValue;
      if (raw is bool) return raw;
      switch (raw.toString().toLowerCase().trim()) {
        case 'true':
        case 'yes':
          return true;
        case 'false':
        case 'no':
          return false;
      }
      throw ConfigException(
        "changelog.$key in '$path' must be true or false, got '$raw'.",
      );
    }

    int? limit() {
      final raw = section['limit'];
      if (raw == null) return null;
      final parsed = raw is int ? raw : int.tryParse(raw.toString().trim());
      if (parsed == null || parsed <= 0) {
        throw ConfigException(
          "changelog.limit in '$path' must be a positive whole number, "
          "got '$raw'.",
        );
      }
      return parsed;
    }

    final from = section['from']?.toString().trim();
    final ChangelogFormat format;
    try {
      format = ChangelogFormat.parse(section['format']?.toString());
    } on ArgumentError catch (e) {
      throw ConfigException("${e.message} (in '$path')");
    }

    return ChangelogOptions(
      from: from == null || from.isEmpty ? null : from,
      group: flag('group', defaultValue: true),
      includeShas: flag('shas'),
      includeMerges: flag('merges'),
      limit: limit(),
      format: format,
    );
  }

  /// Validates an optional top level mapping, leaving its keys unparsed.
  static Map<String, dynamic> _parseSection(
    dynamic raw,
    String name,
    String path,
  ) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw ConfigException("'$name' in '$path' must be a mapping.");
    }
    return Map<String, dynamic>.from(raw);
  }

  /// Builds the optional top level `notifications:` list.
  static List<NotificationConfig> _parseNotifications(
    dynamic raw,
    String path,
  ) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw ConfigException("'notifications' in '$path' must be a list.");
    }

    final notifications = <NotificationConfig>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map) {
        throw ConfigException(
          "notifications[$index] in '$path' must be a mapping.",
        );
      }
      try {
        notifications.add(
          NotificationConfig.fromJson(Map<String, dynamic>.from(entry)),
        );
      } on ArgumentError catch (e) {
        throw ConfigException(
          "notifications[$index] in '$path' is invalid: ${e.message}",
        );
      } on TypeError catch (e) {
        throw ConfigException(
          "notifications[$index] in '$path' has a value of the wrong type: $e",
        );
      }
    }
    return notifications;
  }

  /// Builds a single [Job], validating the keys it depends on.
  static Job _parseJob(
    Map<String, dynamic> json, {
    required Variables variables,
    required Map<String, dynamic> environments,
    required String path,
    required String label,
  }) {
    final name = _requireString(json, "name", path, context: label);
    final packageName = _requireString(
      json,
      "package_name",
      path,
      context: label,
    );

    final builder = json["builder"];
    final publisher = json["publisher"];

    if (builder == null && publisher == null) {
      throw ConfigException(
        "$label ('$name') in '$path' must define either a 'builder' or a 'publisher'.",
      );
    }
    if (builder != null && publisher != null) {
      throw ConfigException(
        "$label ('$name') in '$path' defines both 'builder' and 'publisher'. "
        "Split them into two jobs so the execution order stays explicit.",
      );
    }
    if (builder != null && builder is! Map) {
      throw ConfigException("$label.builder in '$path' must be a mapping.");
    }
    if (publisher != null && publisher is! Map) {
      throw ConfigException("$label.publisher in '$path' must be a mapping.");
    }

    // Each platform section is handed straight to an argument class that takes
    // a Map, so `android: apk` would surface as a raw cast failure naming
    // neither the job nor the key.
    for (final section in [
      if (builder is Map) ('builder', builder),
      if (publisher is Map) ('publisher', publisher),
    ]) {
      for (final entry in section.$2.entries) {
        if (entry.value != null && entry.value is! Map) {
          throw ConfigException(
            "$label.${section.$1}.${entry.key} in '$path' must be a mapping of "
            "options, got ${_describeType(entry.value)}.",
          );
        }
      }
    }

    try {
      return Job(
        name: name,
        description: _asString(json["description"], "$label.description", path),
        packageName: packageName,
        environments: environments,
        key: _asString(json["key"], "$label.key", path),
        continueOnError: _asBool(
            json["continue-on-error"], "$label.continue-on-error", path),
        retry: _parseRetry(json["retry"], path, label),
        builder: builder == null
            ? null
            : BuilderJob.fromJson(
                Map<String, dynamic>.from(builder as Map),
                variables,
              ),
        publisher: publisher == null
            ? null
            : PublisherJob.fromJson(
                Map<String, dynamic>.from(publisher as Map),
                variables,
              ),
      );
    } on ConfigException {
      rethrow;
    } on ArgumentError catch (e) {
      // Platform argument classes validate with ArgumentError, which is an
      // Error rather than an Exception; both must be re-labelled with the
      // location in the YAML so the user knows which job to fix.
      throw ConfigException(
        "$label ('$name') in '$path' is invalid: ${e.message}",
      );
    } on Exception catch (e) {
      throw ConfigException("$label ('$name') in '$path' is invalid: $e");
    } on TypeError catch (e) {
      // A cast that failed somewhere below — a platform section written as a
      // scalar, a number where a string was expected. Without this the raw
      // Dart message reaches the user with no idea which job produced it.
      throw ConfigException(
        "$label ('$name') in '$path' has a value of the wrong type: $e",
      );
    }
  }

  /// Reads an optional string, naming the key when the YAML holds another type.
  ///
  /// A bare `as String?` throws a TypeError — an Error, not an Exception — so
  /// it escapes the handlers around the parse and reaches the user as a raw
  /// Dart message with no clue which key produced it. `key: 7` is an easy
  /// mistake to make and deserves a better answer than that.
  static String? _asString(dynamic value, String label, String path) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    throw ConfigException(
      "$label in '$path' must be text, got ${_describeType(value)}.",
    );
  }

  /// Reads an optional boolean, accepting the quoted spellings YAML produces.
  ///
  /// `continue-on-error: "true"` is quoted by many editors and formatters; it
  /// used to crash rather than be understood, while the neighbouring `retry`
  /// accepted its quoted form.
  static bool _asBool(dynamic value, String label, String path) {
    if (value == null) return false;
    if (value is bool) return value;
    switch (value.toString().toLowerCase().trim()) {
      case 'true':
      case 'yes':
        return true;
      case 'false':
      case 'no':
        return false;
    }
    throw ConfigException(
      "$label in '$path' must be true or false, got '$value'.",
    );
  }

  /// Names the YAML shape of [value] for an error message.
  static String _describeType(dynamic value) => switch (value) {
        List() => 'a list',
        Map() => 'a mapping',
        _ => 'a ${value.runtimeType}',
      };

  /// Validates the optional per-job `retry` count.
  static int _parseRetry(dynamic value, String path, String label) {
    if (value == null) return 0;
    final retry = value is int ? value : int.tryParse(value.toString());
    if (retry == null || retry < 0) {
      throw ConfigException(
        "$label.retry in '$path' must be a non-negative integer, got '$value'.",
      );
    }
    return retry;
  }

  /// Reads a required string key, throwing a descriptive [ConfigException].
  static String _requireString(
    Map<String, dynamic> json,
    String key,
    String path, {
    String? context,
  }) {
    final value = json[key];
    final where = context == null ? "'$path'" : "$context of '$path'";
    if (value == null) {
      throw ConfigException("'$key' key not found in $where.");
    }
    if (value is! String || value.trim().isEmpty) {
      throw ConfigException("'$key' in $where must be a non-empty string.");
    }
    return value;
  }
}
