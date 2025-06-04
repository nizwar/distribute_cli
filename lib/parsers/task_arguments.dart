import 'job_arguments.dart';

/// Represents a distribution task in the configuration.
///
/// A `Task` is a collection of related jobs that can be executed together.
/// Tasks provide a way to group build and publish operations logically,
/// such as "android-release" or "ios-beta". Each task contains multiple
/// jobs that define specific build and publish configurations.
class Task {
  /// The display name of the task
  ///
  /// Used for logging and user interface purposes
  final String name;

  /// The unique identifier for the task
  ///
  /// Used to reference the task in CLI operations and configuration
  final String key;

  /// Optional description explaining the task's purpose
  ///
  /// Provides context about what this task accomplishes
  final String? description;

  /// Optional list of workflow names associated with this task
  ///
  /// Workflows define sequences of tasks for complex deployment scenarios
  final List<String>? workflows;

  /// The list of jobs that belong to this task
  ///
  /// Each job defines specific build and publish operations
  final List<Job> jobs;

  /// Creates a new [Task] instance.
  ///
  /// [name] is the name of the task.
  /// [jobs] is the list of jobs associated with the task.
  /// [key] is the unique key of the task (optional).
  /// [description] is the description of the task (optional).
  /// [workflows] is the list of workflow names (optional).
  Task({
    required this.name,
    required this.key,
    required this.jobs,
    this.workflows,
    this.description,
  });

  /// Converts the [Task] instance to a JSON object.
  Map<String, dynamic> toJson() => {
        "name": name,
        "key": key,
        if (workflows != null) "workflows": workflows,
        "description": description,
        "jobs": jobs.map((job) => job.toJson()).toList(),
      };
}
