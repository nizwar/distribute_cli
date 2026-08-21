import 'dart:async';
import 'dart:io';

import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/parsers/variables.dart';

import '../app_builder/ios/arguments.dart' as ios_arguments;
import '../app_publisher/fastlane/arguments.dart' as fastlane_publisher;
import '../app_publisher/firebase/arguments.dart' as firebase_publisher;
import '../app_publisher/github/arguments.dart' as github_publisher;
import '../app_publisher/huawei/arguments.dart' as huawei_publisher;
import '../app_publisher/xcrun/arguments.dart' as xcrun_publisher;
import '../logger.dart';
import 'task_arguments.dart';
import 'duration.dart';
import 'hooks.dart';

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

  /// When `true`, jobs resolve and print their command without executing it.
  ///
  /// Controlled by the `--dry-run` flag of `distribute run`. It is a process
  /// wide switch because a single CLI invocation is always either a real run or
  /// a rehearsal - never both.
  static bool dryRun = false;

  static final Object _processScopeKey = Object();
  static final Set<Process> _activeProcesses = <Process>{};
  static final Set<FutureOr<void> Function()> _activeCancellations =
      <FutureOr<void> Function()>{};

  /// Runs [body] with an isolated registry of child processes.
  static Future<T> withProcessScope<T>(Future<T> Function() body) async {
    final scope = _ExecutionScope();
    try {
      return await runZoned(body, zoneValues: {_processScopeKey: scope});
    } finally {
      _activeCancellations.removeAll(scope.cancellations);
    }
  }

  /// Registers a child process in the current job scope.
  static void trackProcess(Process process) {
    final scope = Zone.current[_processScopeKey] as _ExecutionScope?;
    scope?.processes.add(process);
    _activeProcesses.add(process);
    process.exitCode.whenComplete(() {
      scope?.processes.remove(process);
      _activeProcesses.remove(process);
    });
  }

  /// Registers cancellation for in-process work such as HTTP requests.
  static void trackCancellation(FutureOr<void> Function() cancel) {
    final scope = Zone.current[_processScopeKey] as _ExecutionScope?;
    scope?.cancellations.add(cancel);
    _activeCancellations.add(cancel);
  }

  /// Terminates only the child processes created by the current job scope.
  static Future<void> terminateScopedProcesses() async {
    final scope = Zone.current[_processScopeKey] as _ExecutionScope?;
    if (scope == null) return;
    for (final cancel in scope.cancellations.toList()) {
      try {
        await cancel();
      } on Object {
        // Cancellation is best effort. Continue terminating every other
        // in-process operation and child process if one callback fails.
      }
    }
    if (scope.processes.isEmpty) return;
    for (final process in scope.processes.toList()) {
      process.kill(ProcessSignal.sigterm);
    }
    await Future.any<void>([
      Future.wait(scope.processes.map((process) => process.exitCode)),
      Future<void>.delayed(const Duration(seconds: 2)),
    ]);
    for (final process in scope.processes.toList()) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// Terminates every tracked child after an external process interrupt.
  static Future<void> terminateAllProcesses() async {
    for (final cancel in _activeCancellations.toList()) {
      try {
        await cancel();
      } on Object {
        // One failing callback must not prevent the remaining work from being
        // cancelled after an external interrupt.
      }
    }
    if (_activeProcesses.isEmpty) return;
    for (final process in _activeProcesses.toList()) {
      process.kill(ProcessSignal.sigterm);
    }
    await Future.any<void>([
      Future.wait(_activeProcesses.map((process) => process.exitCode)),
      Future<void>.delayed(const Duration(seconds: 2)),
    ]);
    for (final process in _activeProcesses.toList()) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// Raw list of command-line arguments before variable processing.
  ///
  /// Subclasses should populate this list with the appropriate arguments
  /// for their specific job type.
  List<String> argumentBuilder = [];

  /// Configuration keys whose values must never be printed or logged.
  ///
  /// Subclasses holding credentials override this so [printJob] masks them and
  /// [registerSecrets] can teach the logger to redact them everywhere else,
  /// including the output streamed back from child processes.
  Set<String> get secretKeys => const <String>{};

  /// Resolves every secret value and registers it with the logger.
  ///
  /// Called before a job prints its configuration or spawns a process, so that
  /// a token echoed back by `fastlane` or `firebase` is masked as well.
  Future<void> registerSecrets() async {
    final rawArguments = toJson();
    for (final key in secretKeys) {
      final value = rawArguments[key];
      if (value == null) continue;
      ColorizeLogger.registerSecret(await variables.process(value.toString()));
    }
  }

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
    logger = ColorizeLogger();
  }

  /// Converts the job arguments to a JSON representation.
  ///
  /// Returns a `Map<String, dynamic>` containing all argument properties.
  /// Subclasses must implement this method to provide specific serialization.
  Map<String, dynamic> toJson();

  /// Prints the resolved configuration of a job.
  ///
  /// Only shown with `--verbose`: the default view prints the command line
  /// instead, which conveys the same thing in one line. Values belonging to
  /// [secretKeys] are replaced with `***`.
  Future printJob() async {
    if (!logger.isVerbose) return;

    final rawArguments = toJson();
    // Remove null, empty lists, and empty string values for cleaner output
    rawArguments.removeWhere(
      (key, value) =>
          value == null || ((value is List) && value.isEmpty) || value == "",
    );
    if (rawArguments.isEmpty) return;

    final width = rawArguments.keys
        .map((key) => key.length)
        .reduce((a, b) => a > b ? a : b);

    for (final key in rawArguments.keys) {
      final printable = secretKeys.contains(key) ? "***" : rawArguments[key];
      logger.logDebug("${key.padRight(width)}  $printable");
    }
  }
}

class _ExecutionScope {
  final Set<Process> processes = <Process>{};
  final Set<FutureOr<void> Function()> cancellations =
      <FutureOr<void> Function()>{};
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
          ? android_arguments.Arguments.fromJson(
              json["android"],
              variables: variables,
            )
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

  /// Huawei AppGallery Connect REST publisher arguments.
  final huawei_publisher.Arguments? huawei;

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
  PublisherJob({
    this.fastlane,
    this.firebase,
    this.xcrun,
    this.github,
    this.huawei,
  }) {
    if (fastlane == null &&
        xcrun == null &&
        firebase == null &&
        github == null &&
        huawei == null) {
      throw Exception(
        'Fastlane, Firebase, Github, Huawei, or XCrun publisher argument '
        'must be provided.',
      );
    }
    // Establish parent-child relationships for configuration hierarchy
    fastlane?.parent = this;
    firebase?.parent = this;
    xcrun?.parent = this;
    github?.parent = this;
    huawei?.parent = this;
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
        if (huawei != null) "huawei": huawei?.toJson(),
      };

  /// Creates a `PublisherJob` from JSON configuration.
  ///
  /// - `json` - JSON object containing publisher configuration
  /// - `variables` - Variable processor for argument substitution
  ///
  /// Returns a new `PublisherJob` instance with publisher-specific arguments
  /// parsed from the JSON configuration.
  factory PublisherJob.fromJson(
    Map<String, dynamic> json,
    Variables variables,
  ) {
    return PublisherJob(
      fastlane: json["fastlane"] != null
          ? fastlane_publisher.Arguments.fromJson(
              json["fastlane"],
              variables: variables,
            )
          : null,
      firebase: json["firebase"] != null
          ? firebase_publisher.Arguments.fromJson(
              json["firebase"],
              variables: variables,
            )
          : null,
      xcrun: json["xcrun"] != null
          ? xcrun_publisher.Arguments.fromJson(
              json["xcrun"],
              variables: variables,
            )
          : null,
      github: json["github"] != null
          ? github_publisher.Arguments.fromJson(
              json["github"],
              variables: variables,
            )
          : null,
      huawei: json["huawei"] != null
          ? huawei_publisher.Arguments.fromJson(
              json["huawei"],
              variables: variables,
            )
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

  /// Whether a failure of this job should stop the surrounding task.
  ///
  /// When `true` the task keeps going and the job is reported as `failed
  /// (ignored)` in the summary, but the overall run still succeeds. Useful for
  /// optional distribution channels such as an internal Firebase group.
  final bool continueOnError;

  /// How many additional attempts a failing job gets before it is given up on.
  ///
  /// Defaults to `0` (a single attempt). Mainly meant for publish jobs, where a
  /// flaky network or a throttled store API is a common transient failure.
  final int retry;

  /// Wait between attempts, separate from the global task-start gap.
  final Duration retryDelay;

  /// Maximum wall-clock time allowed for a single attempt.
  final Duration? timeout;

  /// Custom commands surrounding this job.
  final HookSet hooks;

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
    this.continueOnError = false,
    this.retry = 0,
    this.retryDelay = Duration.zero,
    this.timeout,
    this.hooks = const HookSet(),
  }) {
    if (builder != null && publisher != null) {
      throw Exception(
        "Job '$name' defines both a builder and a publisher; provide only one.",
      );
    }
    if (builder != null) {
      builder!.parent = this;
    } else if (publisher != null) {
      publisher!.parent = this;
    } else {
      throw Exception(
        "Job '$name' must provide either a builder or a publisher.",
      );
    }
  }

  /// A human readable label used in logs and in the run summary.
  String get label => key == null ? name : "$name ($key)";

  /// Converts the `Job` instance to a JSON object.
  Map<String, dynamic> toJson() => {
        "name": name,
        "key": key,
        "description": description,
        "package_name": packageName,
        if (continueOnError) "continue-on-error": continueOnError,
        if (retry > 0) "retry": retry,
        if (retryDelay != Duration.zero)
          "retry-delay": formatDurationValue(retryDelay),
        if (timeout != null) "timeout": formatDurationValue(timeout!),
        if (hooks.pre.isNotEmpty)
          "pre": hooks.pre.map((hook) => hook.toJson()).toList(),
        if (hooks.post.isNotEmpty)
          "post": hooks.post.map((hook) => hook.toJson()).toList(),
        if (builder != null) "builder": builder?.toJson(),
        if (publisher != null) "publisher": publisher?.toJson(),
      };
}
