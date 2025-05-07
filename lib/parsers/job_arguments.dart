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

class Job {
  final String name;
  final String? key;
  final String? description;
  final String platform;
  final JobMode mode;
  final String packageName;
  final Map<String, dynamic>? environments;
  final JobArguments arguments;

  late Task parent;

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
    if (mode != "build" && mode != "publish") throw Exception("Invalid mode for each job");
    if (platform == null) throw Exception("platform is required for each job");
    if (packageName == null) throw Exception("package_name is required for each job");

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
