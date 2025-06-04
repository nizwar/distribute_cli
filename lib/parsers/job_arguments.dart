import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/app_builder/build_arguments.dart';
import 'package:distribute_cli/parsers/variables.dart';

import '../app_builder/ios/arguments.dart' as ios_arguments;
import '../app_publisher/fastlane/arguments.dart' as fastlane_publisher;
import '../app_publisher/firebase/arguments.dart' as firebase_publisher;
import '../app_publisher/github/arguments.dart' as github_publisher;
import '../app_publisher/xcrun/arguments.dart' as xcrun_publisher;
import '../logger.dart';
import 'task_arguments.dart';

/// Enumeration representing the execution mode of a job.
///
/// Jobs can operate in two modes:
/// - `build` - For building applications
/// - `publish` - For publishing/distributing applications
enum JobMode {
  /// Build mode for compiling and creating application packages.
  ///
  /// Used when the job involves building the application for different
  /// platforms (Android APK/AAB, iOS IPA, etc.).
  build,

  /// Publish mode for distributing application packages.
  ///
  /// Used when the job involves publishing the built application to
  /// various distribution channels (App Store, Play Store, Firebase, etc.).
  publish;

  /// Creates a `JobMode` from a string representation.
  ///
  /// - `mode` - String value representing the job mode
  ///
  /// Returns the corresponding `JobMode` enum value.
  ///
  /// Throws `Exception` if the mode string is invalid.
  ///
  /// Supported values:
  /// - "build" -> `JobMode.build`
  /// - "publish" -> `JobMode.publish`
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

/// Abstract base class for job arguments.
///
/// Provides common functionality for all job argument types including
/// variable processing, command-line argument building, and logging.
/// This class serves as the foundation for both build and publish arguments.
///
/// Key features:
/// - Variable substitution in arguments
/// - Colorized logging with verbosity control
/// - JSON serialization support
/// - Command-line argument generation
abstract class JobArguments {
  /// Variable processor for substituting placeholders in arguments.
  final Variables variables;

  /// Raw list of command-line arguments before variable processing.
  ///
  /// Subclasses should populate this list with the appropriate arguments
  /// for their specific job type.
  List<String> argumentBuilder = [];

  /// Processes variables in arguments and returns the final command-line arguments.
  ///
  /// Returns a `Future<List<String>>` containing all arguments with variables
  /// substituted with their actual values.
  Future<List<String>> get arguments async {
    final results = List<String>.from(argumentBuilder);
    for (int i = 0; i < results.length; i++) {
      results[i] = await variables.process(results[i]);
    }
    return results;
  }

  /// Logger instance for outputting colored messages.
  ///
  /// Verbosity is controlled by the global `verbose` variable setting.
  late ColorizeLogger logger;

  /// Creates a new `JobArguments` instance.
  ///
  /// - `variables` - Variable processor for argument substitution
  ///
  /// Initializes the logger with verbosity based on global variables.
  JobArguments(this.variables) {
    logger = ColorizeLogger(variables.globalResults?['verbose'] ?? false);
  }

  /// Converts the job arguments to a JSON representation.
  ///
  /// Returns a `Map<String, dynamic>` containing all argument properties.
  /// Subclasses must implement this method to provide specific serialization.
  Map<String, dynamic> toJson();

  /// Prints job configuration information to the console.
  ///
  /// Displays the job type (Build/Publish) and all non-empty configuration
  /// values in a formatted, easy-to-read manner.
  Future printJob() async {
    final rawArguments = toJson();
    // Remove null, empty lists, and empty string values for cleaner output
    rawArguments.removeWhere((key, value) =>
        value == null || ((value is List) && value.isEmpty) || value == "");

    // Determine job type based on instance type
    String type = this is BuildArguments ? "Build" : "Publish";
    logger.logInfo("Running $type with configurations:");

    // Display each configuration key-value pair
    for (var value in rawArguments.keys) {
      logger.logInfo(" - $value: ${rawArguments[value]}");
    }
    logger.logEmpty();
  }
}

/// Container for platform-specific build arguments.
///
/// Manages build configurations for Android and iOS platforms. A `BuilderJob`
/// must contain at least one platform configuration but can support both
/// platforms simultaneously for universal builds.
///
/// The builder job establishes parent-child relationships with platform-specific
/// argument objects for proper configuration inheritance and validation.
///
/// Example usage:
/// ```dart
/// final builderJob = BuilderJob(
///   android: AndroidArguments.fromJson(androidConfig, variables: vars),
///   ios: iOSArguments.fromJson(iosConfig, variables: vars),
/// );
/// ```
class BuilderJob {
  /// Android-specific build arguments.
  ///
  /// Contains all configuration needed for building Android APK or AAB files,
  /// including signing, optimization, and target settings.
  final android_arguments.Arguments? android;

  /// iOS-specific build arguments.
  ///
  /// Contains all configuration needed for building iOS IPA files,
  /// including provisioning profiles, certificates, and target settings.
  final ios_arguments.Arguments? ios;

  /// Reference to the parent job that contains this builder.
  ///
  /// Used for accessing job-level configuration and establishing
  /// the configuration hierarchy.
  late Job parent;

  /// Creates a new `BuilderJob` instance.
  ///
  /// - `android` - Android build arguments (optional)
  /// - `ios` - iOS build arguments (optional)
  ///
  /// At least one platform must be specified. Sets up parent-child
  /// relationships for proper configuration inheritance.
  ///
  /// Throws `Exception` if both platforms are null.
  BuilderJob({this.android, this.ios}) {
    if (android == null && ios == null) {
      throw Exception("Android or iOS build argument must be provided.");
    }
    // Establish parent-child relationships for configuration hierarchy
    android?.parent = this;
    ios?.parent = this;
  }

  /// Creates a `BuilderJob` from JSON configuration.
  ///
  /// - `json` - JSON object containing build configuration
  /// - `variables` - Variable processor for argument substitution
  ///
  /// Returns a new `BuilderJob` instance with platform-specific arguments
  /// parsed from the JSON configuration.
  factory BuilderJob.fromJson(Map<String, dynamic> json, Variables variables) {
    return BuilderJob(
      android: json["android"] != null
          ? android_arguments.Arguments.fromJson(json["android"],
              variables: variables)
          : null,
      ios: json["ios"] != null
          ? ios_arguments.Arguments.fromJson(json["ios"], variables: variables)
          : null,
    );
  }

  /// Converts the builder job to JSON representation.
  ///
  /// Returns a `Map<String, dynamic>` containing only the platform
  /// configurations that are present (non-null).
  Map<String, dynamic> toJson() => {
        if (android != null) "android": android?.toJson(),
        if (ios != null) "ios": ios?.toJson(),
      };
}

/// Container for publisher-specific arguments.
///
/// Manages publishing configurations for different distribution channels.
/// A `PublisherJob` must contain at least one publisher configuration but
/// can support multiple publishers for multi-channel distribution.
///
/// Supported publishers:
/// - Fastlane - Cross-platform app automation tool
/// - Firebase - Firebase App Distribution
/// - GitHub - GitHub Releases
/// - XCrun - Apple App Store via Xcode command line tools
///
/// Example usage:
/// ```dart
/// final publisherJob = PublisherJob(
///   fastlane: FastlaneArguments.fromJson(config, variables: vars),
///   firebase: FirebaseArguments.fromJson(config, variables: vars),
/// );
/// ```
class PublisherJob {
  /// Fastlane publisher arguments for automated app deployment.
  ///
  /// Supports both Android and iOS app distribution through Fastlane lanes.
  final fastlane_publisher.Arguments? fastlane;

  /// Firebase App Distribution arguments.
  ///
  /// Used for distributing apps to testers through Firebase console.
  final firebase_publisher.Arguments? firebase;

  /// XCrun publisher arguments for App Store distribution.
  ///
  /// Handles iOS app submission to the Apple App Store using Xcode tools.
  final xcrun_publisher.Arguments? xcrun;

  /// GitHub publisher arguments for release distribution.
  ///
  /// Publishes app packages as GitHub release assets.
  final github_publisher.Arguments? github;

  /// Reference to the parent job that contains this publisher.
  ///
  /// Used for accessing job-level configuration and establishing
  /// the configuration hierarchy.
  late Job parent;

  /// Creates a new `PublisherJob` instance.
  ///
  /// - `fastlane` - Fastlane publisher arguments (optional)
  /// - `firebase` - Firebase publisher arguments (optional)
  /// - `xcrun` - XCrun publisher arguments (optional)
  /// - `github` - GitHub publisher arguments (optional)
  ///
  /// At least one publisher must be specified. Sets up parent-child
  /// relationships for proper configuration inheritance.
  ///
  /// Throws `Exception` if all publishers are null.
  PublisherJob({this.fastlane, this.firebase, this.xcrun, this.github}) {
    if (fastlane == null &&
        xcrun == null &&
        firebase == null &&
        github == null) {
      throw Exception(
          "Fastlane, Firebase, Github, or XCrun publisher argument must be provided.");
    }
    // Establish parent-child relationships for configuration hierarchy
    fastlane?.parent = this;
    firebase?.parent = this;
    xcrun?.parent = this;
    github?.parent = this;
  }

  /// Converts the publisher job to JSON representation.
  ///
  /// Returns a `Map<String, dynamic>` containing only the publisher
  /// configurations that are present (non-null).
  Map<String, dynamic> toJson() => {
        if (fastlane != null) "fastlane": fastlane?.toJson(),
        if (firebase != null) "firebase": firebase?.toJson(),
        if (xcrun != null) "xcrun": xcrun?.toJson(),
        if (github != null) "github": github?.toJson(),
      };

  /// Creates a `PublisherJob` from JSON configuration.
  ///
  /// - `json` - JSON object containing publisher configuration
  /// - `variables` - Variable processor for argument substitution
  ///
  /// Returns a new `PublisherJob` instance with publisher-specific arguments
  /// parsed from the JSON configuration.
  factory PublisherJob.fromJson(
      Map<String, dynamic> json, Variables variables) {
    return PublisherJob(
      fastlane: json["fastlane"] != null
          ? fastlane_publisher.Arguments.fromJson(json["fastlane"],
              variables: variables)
          : null,
      firebase: json["firebase"] != null
          ? firebase_publisher.Arguments.fromJson(json["firebase"],
              variables: variables)
          : null,
      xcrun: json["xcrun"] != null
          ? xcrun_publisher.Arguments.fromJson(json["xcrun"],
              variables: variables)
          : null,
      github: json["github"] != null
          ? github_publisher.Arguments.fromJson(json["github"],
              variables: variables)
          : null,
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
  /// - `name` is the name of the job.
  /// - `platform` is the platform for which the job is executed.
  /// - `mode` is the mode of the job (build or publish).
  /// - `packageName` is the package name associated with the job.
  /// - `arguments` are the arguments associated with the job.
  /// - `key` is the unique key of the job (optional).
  /// - `description` is the description of the job (optional).
  /// - `environments` are the environment variables for the job (optional).
  Job({
    required this.name,
    this.key,
    required this.description,
    required this.packageName,
    this.environments,
    this.builder,
    this.publisher,
  }) : assert(
          (builder != null && publisher == null) ||
              (builder == null && publisher != null),
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
