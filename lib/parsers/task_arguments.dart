import 'job_arguments.dart';

/// Represents a task in the configuration.
///
/// A [Task] consists of a name, an optional key, an optional description,
/// and a list of jobs associated with the task.
class Task {
  /// The name of the task.
  final String name;

  /// The unique key of the task (optional).
  final String key;

  /// The description of the task (optional).
  final String? description;

  /// The list of workflow names associated with the task (optional).
  final List<String>? workflows;

  /// The list of jobs associated with the task.
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
