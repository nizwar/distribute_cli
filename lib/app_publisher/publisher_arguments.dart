import 'dart:convert';
import 'dart:io';
import '../files.dart';
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
  /// Used for accessing job-level configuration and establishing
  /// the configuration hierarchy between jobs and publishers.
  late PublisherJob parent;

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
  PublisherArguments(this.publisher, super.variables,
      {required this.filePath, required this.binaryType});

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
    await processFilesArgs();
    await printJob();
    final arguments = await this.arguments;
    logger.logDebug
        .call("Starting upload with `$publisher ${(arguments).join(" ")}`");

    // Start the publisher process with arguments
    final process = await Process.start(publisher, arguments,
        runInShell: true, includeParentEnvironment: true);

    // Stream stdout and stderr with appropriate logging levels
    process.stdout.transform(utf8.decoder).listen(logger.logDebug);
    process.stderr.transform(utf8.decoder).listen(logger.logErrorVerbose);

    return await process.exitCode;
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
    }

    // Check if the file path is a directory
    if (await FileSystemEntity.isDirectory(filePath)) {
      final binaryType = this.binaryType;
      final dir = Directory(filePath);

      // If directory exists but doesn't contain binary files of the specified type
      if (dir.existsSync() &&
          dir
              .listSync()
              .where((item) => item.path.endsWith(binaryType))
              .isEmpty) {
        // Handle Android binary types (APK and AAB)
        if ((binaryType == "apk" || binaryType == "aab")) {
          logger.logDebug.call(
              "Scanning ${this.binaryType} on ${Files.androidOutputApks.path}");
          final sourceDir = binaryType == "apk"
              ? Files.androidOutputApks
              : Files.androidOutputAppbundles;
          filePath = await Files.copyFiles(sourceDir.path, filePath,
                  fileType: [binaryType]) ??
              "";
        }
        // Handle iOS binary type (IPA)
        else if (binaryType == "ipa") {
          logger.logDebug.call(
              "Scanning ${this.binaryType} on ${Files.iosOutputIPA.path}");
          filePath = await Files.copyFiles(Files.iosOutputIPA.path, filePath,
                  fileType: ["ipa"]) ??
              "";
        } else {
          logger.logErrorVerbose.call("Invalid binary type: $binaryType");
        }
      } else {
        // Find the first file matching the binary type in the directory
        filePath = Directory(filePath)
            .listSync()
            .firstWhere((element) =>
                element is File && element.path.endsWith(this.binaryType))
            .path;
      }
    }

    // Final validation that file path is not empty
    if (filePath.isEmpty) {
      logger.logErrorVerbose.call("File path is empty");
    }
  }
}
