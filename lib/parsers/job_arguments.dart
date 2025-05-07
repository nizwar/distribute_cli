import 'task_arguments.dart';

enum JobMode {
  build,
  publish;

  static JobMode fromString(String mode) {
    switch (mode) {
      case "build":
        return JobMode.build;
      case "publish":
        return JobMode.publish;
      default:
        throw Exception("Invalid job mode");
    }
  }
}

abstract class JobArguments {
  List<String> get results;
  List<String> get argKeys;
  JobMode get jobMode;

  late Job parent;

  Map<String, dynamic> toJson();
}

/// Represents a job in the configuration.
///
/// A `Job` consists of a name, an optional key, an optional description,
/// a platform, a mode (build or publish), a package name, and associated arguments.
class Job {
  /// The name of the job.
  final String name;

  /// The unique key of the job (optional).
  final String? key;

  /// The description of the job (optional).
  final String? description;

  /// The platform for which the job is executed (e.g., android, ios).
  final String platform;

  /// The mode of the job (build or publish).
  final JobMode mode;

  /// The package name associated with the job.
  final String packageName;

  /// The environment variables for the job (optional).
  final Map<String, dynamic>? environments;

  /// The arguments associated with the job.
  final JobArguments arguments;

  /// The parent task of the job.
  late Task parent;

  /// Creates a new `Job` instance.
  ///
  /// [name] is the name of the job.
  /// [platform] is the platform for which the job is executed.
  /// [mode] is the mode of the job (build or publish).
  /// [packageName] is the package name associated with the job.
  /// [arguments] are the arguments associated with the job.
  /// [key] is the unique key of the job (optional).
  /// [description] is the description of the job (optional).
  /// [environments] are the environment variables for the job (optional).
  Job({
    required this.name,
    this.key,
    required this.description,
    required this.arguments,
    required this.packageName,
    required this.platform,
    required this.mode,
    this.environments,
  }) {
    arguments.parent = this;
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    final platform = json["platform"];
    final mode = json["mode"];
    final packageName = json["package_name"];
    final key = json["key"];

    if (mode == null) throw Exception("mode is required for each job");
    if (mode != "build" && mode != "publish")
      throw Exception("Invalid mode for each job");
    if (platform == null) throw Exception("platform is required for each job");
    if (packageName == null)
      throw Exception("package_name is required for each job");

    JobArguments? task;
    final isBuildMode = mode == "build";
    final isPublishMode = mode == "publish";

    if (!isBuildMode && !isPublishMode) {
      throw Exception("Invalid job mode");
    }

    return Job(
      name: json["name"],
      key: key,
      description: json["description"],
      arguments: task!,
      environments: json["variables"],
      packageName: packageName,
      platform: platform,
      mode: JobMode.fromString(mode),
    );
  }

  /// Converts the `Job` instance to a JSON object.
  Map<String, dynamic> toJson() => {
        "name": name,
        "key": key,
        "description": description,
        "package_name": packageName,
        "platform": platform,
        "mode": mode.name,
        "arguments": arguments.toJson(),
      };
}
