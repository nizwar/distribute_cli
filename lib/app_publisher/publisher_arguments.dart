import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import '../files.dart';
import '../logger.dart';
import '../parsers/build_info.dart';
import '../parsers/job_arguments.dart';

/// Abstract base class for all application publisher arguments.
///
/// Provides common functionality for publishing applications across different
/// platforms and services. Handles file processing, validation, and the
/// publishing workflow for various binary types.
///
/// Supported binary types:
/// - `apk` - Android Application Package
/// - `aab` - Android App Bundle
/// - `ipa` - iOS Application Archive
///
/// Example usage:
/// ```dart
/// class MyPublisher extends PublisherArguments {
///   MyPublisher(Variables variables) : super(
///     'my-publisher',
///     variables,
///     filePath: '/path/to/app.apk',
///     binaryType: 'apk',
///   );
/// }
/// ```
abstract class PublisherArguments extends JobArguments {
  /// The name identifier of the publisher platform.
  ///
  /// Specifies which publishing service to use for distribution.
  /// Common values include:
  /// - `fastlane` - Fastlane automation
  /// - `firebase` - Firebase App Distribution
  /// - `github` - GitHub Releases
  /// - `xcrun` - App Store via Xcode command line tools
  final String publisher;

  /// The file system path to the application binary to be published.
  ///
  /// Can be either:
  /// - Direct path to a specific file (e.g., `/path/to/app.apk`)
  /// - Directory path containing the binary files
  ///
  /// If a directory is provided, the system will automatically locate
  /// files matching the specified `binaryType`.
  String filePath;

  /// The type of application binary being published.
  ///
  /// Valid values:
  /// - `apk` - Android Application Package for direct installation
  /// - `aab` - Android App Bundle for Play Store distribution
  /// - `ipa` - iOS Application Archive for App Store distribution
  final String binaryType;

  /// Reference to the parent publisher job that contains this publisher.
  ///
  /// Only set when the publisher was built from `distribution.yaml`. It stays
  /// `null` for the standalone `distribute publish <tool>` commands, so it must
  /// never be dereferenced without a fallback - see [resolvePackageName].
  PublisherJob? parent;

  /// Application identifier explicitly provided for this publisher.
  ///
  /// Set from the `--package-name` option of the standalone publish commands.
  /// Configuration files normally inherit it from the surrounding job instead.
  String? packageNameOverride;

  /// The application identifier this publisher should target.
  ///
  /// Resolution order:
  /// 1. the explicit `--package-name` option,
  /// 2. the `package_name` of the enclosing job in `distribution.yaml`,
  /// 3. the `applicationId` detected in the Android Gradle files.
  ///
  /// Throws a descriptive [StateError] when none of them is available, instead
  /// of the opaque `LateInitializationError` the parent chain used to produce.
  String resolvePackageName() {
    final override = packageNameOverride;
    if (override != null && override.isNotEmpty) return override;

    final jobPackageName = parent?.parent.packageName;
    if (jobPackageName != null && jobPackageName.isNotEmpty) {
      return jobPackageName;
    }

    final detected = BuildInfo.androidPackageName;
    if (detected != null && detected.isNotEmpty) return detected;

    throw StateError(
      "Unable to determine the package name for the $publisher publisher. "
      "Pass --package-name, set `package_name` on the job, or run from a "
      "Flutter project where the applicationId can be detected.",
    );
  }

  /// Creates a new publisher arguments instance.
  ///
  /// Parameters:
  /// - `publisher` - The publisher platform identifier
  /// - `variables` - Variable processor for argument substitution
  /// - `filePath` - Path to the application binary or directory
  /// - `binaryType` - Type of binary (apk, aab, ipa)
  ///
  /// Initializes the base publisher configuration with the specified
  /// parameters and inherits job argument functionality.
  PublisherArguments(
    this.publisher,
    super.variables, {
    required this.filePath,
    required this.binaryType,
  });

  /// Initiates the application publishing process.
  ///
  /// Executes the complete publishing workflow including file processing,
  /// validation, and upload to the target platform. Provides detailed
  /// logging throughout the process for debugging and monitoring.
  ///
  /// Returns the exit code of the publishing process:
  /// - `0` - Success
  /// - Non-zero - Error occurred during publishing
  ///
  /// Process steps:
  /// 1. Process and validate file arguments
  /// 2. Display job configuration
  /// 3. Execute publisher command with arguments
  /// 4. Stream output and error logs
  /// 5. Return process exit code
  Future<int> publish() async {
    await registerSecrets();
    // `processFilesArgs` rewrites `filePath` to the resolved binary, or clears
    // it when nothing matched - so keep the configured value for the message.
    final requestedPath = filePath;
    await processFilesArgs();

    if (filePath.isEmpty) {
      // During a dry run the build step never produced anything, so a missing
      // artifact is expected and must not fail the rehearsal.
      if (JobArguments.dryRun) {
        logger.logNote("no $binaryType artifact yet (dry run)");
        return 0;
      }
      logger.logError(
        "no $binaryType artifact found for $publisher in $requestedPath",
      );
      logger.logDetail(
        "run the matching build job first, or point `file-path` at an existing binary",
      );
      return 1;
    }

    await printJob();
    final arguments = await this.arguments;
    final commandLine = "$publisher ${arguments.join(" ")}";

    logger.logCommand(commandLine);
    if (JobArguments.dryRun) return 0;

    return runProcess(arguments);
  }

  /// Runs the publisher executable with [arguments] and streams its output.
  ///
  /// Returns the process exit code, or `127` when the executable is not
  /// installed. Both output streams are always drained: leaving `stderr`
  /// unread lets a chatty tool fill the OS pipe buffer and deadlock.
  Future<int> runProcess(List<String> arguments) async {
    final Process process;
    try {
      process = await Process.start(
        publisher,
        arguments,
        runInShell: true,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (e) {
      logger.logError(
        "Unable to start `$publisher`: ${e.message}. "
        "Make sure the tool is installed and available in your PATH.",
      );
      return 127;
    }

    // Stream stdout and stderr with appropriate logging levels
    final drained = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(logger.logDebug),
      process.stderr.transform(utf8.decoder).forEach(logger.logErrorVerbose),
    ]);

    // Uploads are the longest silent stretch of a release: an IPA going to App
    // Store Connect can take minutes with nothing at all on screen.
    final exitCode = await Spinner.run(
      'uploading with $publisher',
      () async {
        final code = await process.exitCode;
        await drained;
        return code;
      },
    );
    return exitCode;
  }

  /// Processes and validates file arguments before publishing.
  ///
  /// Handles file path resolution, validation, and binary file location.
  /// Supports both direct file paths and directory scanning for matching
  /// binary types. Automatically copies files from build outputs when needed.
  ///
  /// File processing logic:
  /// - Validates file path is not empty
  /// - If directory path: scans for files matching `binaryType`
  /// - For Android (apk/aab): copies from build output directories
  /// - For iOS (ipa): copies from iOS build output directory
  /// - Updates `filePath` to point to the resolved binary file
  ///
  /// Throws errors for:
  /// - Empty file paths
  /// - Invalid binary types
  /// - Missing binary files in specified directories
  Future<void> processFilesArgs() async {
    if (filePath.isEmpty) {
      logger.logErrorVerbose.call("File path is empty");
      return;
    }

    // A direct path to an existing file needs no further resolution.
    if (await FileSystemEntity.isFile(filePath)) return;

    if (!await FileSystemEntity.isDirectory(filePath)) {
      logger.logErrorVerbose.call(
        "File path does not exist: $filePath",
      );
      filePath = "";
      return;
    }

    final binaryType = this.binaryType;
    final dir = Directory(filePath);
    final existing = dir
        .listSync()
        .whereType<File>()
        .where((item) => item.path.endsWith(".$binaryType"))
        .toList();

    if (existing.isNotEmpty) {
      // Prefer the most recently produced artifact when several are present.
      existing.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      filePath = existing.first.path;
      return;
    }

    // The output directory is empty: fall back to the raw Flutter build output.
    final sources = switch (binaryType) {
      "apk" || "aab" => _androidSourceCandidates,
      "ipa" => _iosSourceCandidates,
      _ => const <String>[],
    };

    if (sources.isEmpty) {
      logger.logErrorVerbose.call("Invalid binary type: $binaryType");
      filePath = "";
      return;
    }

    filePath = await _copyFromCandidateSources(
          targetDir: filePath,
          binaryType: binaryType,
          sources: sources,
        ) ??
        "";

    if (filePath.isEmpty) {
      logger.logErrorVerbose.call(
        "No .$binaryType artifact found in ${dir.path} or in ${sources.join(', ')}",
      );
    }
  }

  Future<String?> _copyFromCandidateSources({
    required String targetDir,
    required String binaryType,
    required List<String> sources,
  }) async {
    for (final source in sources.toSet()) {
      final output = await Files.copyFiles(
        source,
        targetDir,
        fileType: [binaryType],
      ).catchError((_) => null);
      if (output != null) {
        logger.logDebug.call(
          "Scanning ${this.binaryType} on $source",
        );
        return output;
      }
    }
    return null;
  }

  List<String> get _androidSourceCandidates => [
        Files.androidOutputApks.path,
        path.join("build", "app", "outputs", "apk"),
        Files.androidOutputAppbundles.path,
        path.join("build", "app", "outputs"),
        path.join("build", "app"),
      ];

  List<String> get _iosSourceCandidates => [
        Files.iosOutputIPA.path,
        path.join("build", "ios"),
        "build",
      ];
}
