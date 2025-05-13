import 'package:distribute_cli/app_builder/android/arguments.dart' as android_arguments;

import '../app_builder/ios/arguments.dart' as ios_arguments;
import '../app_publisher/fastlane/android/arguments.dart' as fastlane_publisher;
import '../app_publisher/firebase/android/arguments.dart' as firebase_publisher;
import '../app_publisher/xcrun/ios/arguments.dart' as xcrun_publisher;
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

  Map<String, dynamic> toJson();
}

class BuilderJob {
  final android_arguments.Arguments? android;
  final ios_arguments.Arguments? ios;
  late Job parent;

  BuilderJob({this.android, this.ios}) {
    if (android == null && ios == null) {
      throw Exception("Android or iOS build argument must be provided.");
    }
    android?.parent = this;
    ios?.parent = this;
  }

  factory BuilderJob.fromJson(Map<String, dynamic> json) {
    return BuilderJob(
      android: json["android"] != null ? android_arguments.Arguments.fromJson(json["android"]) : null,
      ios: json["ios"] != null ? ios_arguments.Arguments.fromJson(json["ios"]) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (android != null) "android": android?.toJson(),
        if (ios != null) "ios": ios?.toJson(),
      };
}

class PublisherJob {
  final fastlane_publisher.Arguments? fastlane;
  final firebase_publisher.Arguments? firebase;
  final xcrun_publisher.Arguments? xcrun;
  late Job parent;

  PublisherJob({this.fastlane, this.firebase, this.xcrun}) {
    if (fastlane == null && xcrun == null && firebase == null) {
      throw Exception("Fastlane, Firebase, or iOS publisher argument must be provided.");
    }
    fastlane?.parent = this;
    firebase?.parent = this;
    xcrun?.parent = this;
  }

  Map<String, dynamic> toJson() => {
        if (fastlane != null) "fastlane": fastlane?.toJson(),
        if (firebase != null) "firebase": firebase?.toJson(),
        if (xcrun != null) "xcrun": xcrun?.toJson(),
      };

  factory PublisherJob.fromJson(Map<String, dynamic> json) {
    return PublisherJob(
      fastlane: json["fastlane"] != null ? fastlane_publisher.Arguments.fromJson(json["fastlane"]) : null,
      firebase: json["firebase"] != null ? firebase_publisher.Arguments.fromJson(json["firebase"]) : null,
      xcrun: json["xcrun"] != null ? xcrun_publisher.Arguments.fromJson(json["xcrun"]) : null,
    );
  }
}

/// Represents a job in the configuration.
///
/// A `Job` consists of a name, an optional key, an optional description,
/// a platform, a mode (build or publish), a package name, and associated arguments.
class Job {
  /// The unique key of the job (optional).
  final String? key;

  /// The name of the job.
  final String name;

  final PublisherJob? publisher;
  final BuilderJob? builder;

  /// The description of the job (optional).
  final String? description;

  /// The package name associated with the job.
  final String packageName;

  /// The environment variables for the job (optional).
  final Map<String, dynamic>? environments;

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
    required this.packageName,
    this.environments,
    this.builder,
    this.publisher,
  }) : assert(
          (builder != null && publisher == null) || (builder == null && publisher != null),
          "Either builder or publisher must be provided, not both.",
        ) {
    if (builder != null) {
      builder?.parent = this;
    } else if (publisher != null) {
      publisher?.parent = this;
    } else {
      throw Exception("Either builder or publisher must be provided.");
    }
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    final packageName = json["package_name"];
    final key = json["key"];
    if (packageName == null) {
      throw Exception("package_name is required for each job");
    }

    return Job(
      name: json["name"],
      key: key,
      description: json["description"],
      environments: json["variables"],
      packageName: packageName,
    );
  }

  /// Converts the `Job` instance to a JSON object.
  Map<String, dynamic> toJson() => {
        "name": name,
        "key": key,
        "description": description,
        "package_name": packageName,
        if (builder != null) "builder": builder?.toJson(),
        if (publisher != null) "publisher": publisher?.toJson(),
      };
}
