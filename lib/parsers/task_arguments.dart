import 'job_arguments.dart';

class Task {
  final String name;
  final String? key;
  final String? description;
  final List<Job> jobs;

  Task({
    required this.name,
    required this.jobs,
    this.key,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        "name": name,
        "key": key,
        "description": description,
        "jobs": jobs.map((job) => job.toJson()).toList(),
      };
}
