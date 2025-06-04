import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/parsers/compress_files.dart';

import '../files.dart';
import '../parsers/job_arguments.dart';
import 'ios/arguments.dart' as ios_arguments;

/// Abstract base class for Flutter application build arguments.
///
/// Provides common functionality and configuration for building Flutter
/// applications across different platforms. This class extends `JobArguments`
/// to inherit variable processing and logging capabilities.
///
/// Key responsibilities:
/// - Managing build configuration parameters
/// - Generating Flutter CLI command arguments
/// - Orchestrating the build process
/// - Handling output file management
/// - Supporting debug symbol generation
///
/// Platform-specific implementations should extend this class to provide
/// additional platform-specific functionality and validation.
abstract class BuildArguments extends JobArguments {
  /// Type of binary to build (e.g., 'apk', 'aab', 'ipa').
  ///
  /// Determines the output format of the built application package.
  final String binaryType;

  /// Custom output path for the build artifacts.
  ///
  /// If not specified, defaults to platform-specific distribution directories.
  String? output;

  /// Target Dart file to build from.
  ///
  /// Typically points to the main entry point (e.g., 'lib/main.dart').
  /// If not specified, uses the default target.
  final String? target;

  /// Build mode for the application.
  ///
  /// Common values include 'release', 'debug', and 'profile'.
  /// Defaults to 'release' for optimized production builds.
  final String? buildMode;

  /// Build flavor for multi-flavor applications.
  ///
  /// Allows building different variants of the app with different
  /// configurations (e.g., 'development', 'staging', 'production').
  final String? flavor;

  /// Dart compilation defines as a single string.
  ///
  /// Provides compile-time constants to the Dart code in the format
  /// 'KEY1=VALUE1,KEY2=VALUE2'.
  final String? dartDefines;

  /// Path to a file containing Dart compilation defines.
  ///
  /// Alternative to `dartDefines` for managing large numbers of defines
  /// or sensitive configuration values stored in external files.
  final String? dartDefinesFile;

  /// Version name for the application build.
  ///
  /// Sets the user-visible version string for the application.
  final String? buildName;

  /// Version code/build number for the application.
  ///
  /// Sets the internal version number used for app store management.
  final String? buildNumber;

  /// Whether to run `flutter pub get` before building.
  ///
  /// Ensures dependencies are up-to-date before compilation.
  /// Defaults to `true` for reliable builds.
  final bool pub;

  /// Additional custom arguments for the Flutter build command.
  ///
  /// Allows passing platform-specific or advanced build options
  /// not covered by the standard parameters.
  final List<String>? customArgs;

  /// Source directory where build artifacts are initially created.
  ///
  /// Platform-specific build output location before copying to
  /// the final distribution directory.
  final String buildSourceDir;

  /// Reference to the parent builder job.
  ///
  /// Used for accessing builder-level configuration and establishing
  /// the configuration hierarchy.
  late BuilderJob parent;

  /// Creates a new `BuildArguments` instance.
  ///
  /// - `variables` - Variable processor for argument substitution
  /// - `binaryType` - Type of binary to build (required)
  /// - `buildSourceDir` - Source directory for build artifacts (required)
  /// - `buildMode` - Build mode (defaults to 'release')
  /// - `output` - Custom output path (optional)
  /// - `target` - Target Dart file (optional)
  /// - `flavor` - Build flavor (optional)
  /// - `dartDefines` - Dart defines string (optional)
  /// - `dartDefinesFile` - Path to defines file (optional)
  /// - `customArgs` - Additional build arguments (optional)
  /// - `buildName` - Version name (optional)
  /// - `buildNumber` - Version code (optional)
  /// - `pub` - Whether to run pub get (defaults to true)
  BuildArguments(
    super.variables, {
    this.buildMode = 'release',
    this.output,
    this.target,
    required this.binaryType,
    required this.buildSourceDir,
    this.flavor,
    this.dartDefines,
    this.dartDefinesFile,
    this.customArgs,
    this.buildName,
    this.buildNumber,
    this.pub = true,
  });

  /// Generates the command-line arguments for the Flutter build command.
  ///
  /// Returns a list of strings that will be passed to `flutter build`.
  /// Arguments are conditionally included based on their values.
  @override
  List<String> get argumentBuilder => [
        // Include binary type if not empty
        if (binaryType.isNotEmpty) binaryType,
        // Include target file specification
        if (target?.isNotEmpty ?? false) '--target=$target',
        // Include build mode flag
        if (buildMode?.isNotEmpty ?? false) '--$buildMode',
        // Include flavor specification
        if (flavor?.isNotEmpty ?? false) '--flavor=$flavor',
        // Include Dart defines
        if (dartDefines?.isNotEmpty ?? false) '--dart-defines=$dartDefines',
        // Include Dart defines file
        if (dartDefinesFile?.isNotEmpty ?? false)
          '--dart-defines-file=$dartDefinesFile',
        // Include build name/version
        if (buildName?.isNotEmpty ?? false) '--build-name=$buildName',
        // Include build number/version code
        if (buildNumber?.isNotEmpty ?? false) '--build-number=$buildNumber',
        // Include pub get flag
        if (pub) '--pub' else '--no-pub',
        // Include any custom arguments
        if (customArgs != null) ...customArgs!,
      ];

  /// Executes the complete build process.
  ///
  /// Orchestrates the entire build workflow including:
  /// 1. Logging build configuration
  /// 2. Running Flutter build command
  /// 3. Moving output files to distribution directories
  /// 4. Generating debug symbols (for Android release builds)
  ///
  /// Returns the process exit code (0 indicates success).
  ///
  /// The build process includes proper error handling and logging
  /// at each step to facilitate debugging build issues.
  Future<int> build() async {
    // Display build configuration before starting
    await printJob();

    // Get processed arguments with variable substitution
    final arguments = await this.arguments;
    logger.logDebug.call(
        "Starting build with flutter ${["build", ...arguments].join(" ")}");

    // Start Flutter build process
    final process = await Process.start("flutter", ["build", ...arguments],
        runInShell: true, includeParentEnvironment: true);

    // Stream build output to logger
    process.stdout.transform(utf8.decoder).listen(logger.logDebug);
    process.stderr.transform(utf8.decoder).listen(logger.logErrorVerbose);

    // Wait for build completion
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      logger.logDebug.call("Build failed with exit code: $exitCode");
      return exitCode;
    }

    // Move output files to distribution directory
    final moveResult = await _moveOutputFiles();
    if (moveResult != 0) return moveResult;

    // Generate debug symbols for Android release builds
    if ((this is android_arguments.Arguments)) {
      if (buildMode == "release" &&
          (this as android_arguments.Arguments).generateDebugSymbols) {
        final zipResult = await _generateAndCopyZipSymbols();
        if (zipResult != 0) return zipResult;
      }
    }
    return exitCode;
  }

  /// Moves build output files to the appropriate distribution directories.
  ///
  /// Platform-specific implementation that copies built artifacts from
  /// the build source directory to the final distribution location.
  ///
  /// Returns 0 on success, 1 on failure.
  Future<int> _moveOutputFiles() async {
    if (this is android_arguments.Arguments) {
      // Handle Android build artifacts
      android_arguments.Arguments androidArgs =
          this as android_arguments.Arguments;
      String target =
          androidArgs.output ?? Files.androidDistributionOutputDir.path;

      final output = await Files.copyFiles(buildSourceDir, target,
              fileType: [binaryType], mode: buildMode ?? "release")
          .catchError((e) {
        logger.logErrorVerbose.call(e.toString());
        return null;
      });

      if (output == null) {
        logger.logErrorVerbose
            .call("Failed to copy files from $buildSourceDir to $target");
        return 1;
      }
    } else if (this is ios_arguments.Arguments) {
      // Handle iOS build artifacts
      ios_arguments.Arguments iosArgs = this as ios_arguments.Arguments;
      String target = iosArgs.output ?? Files.iosDistributionOutputDir.path;

      final output = await Files.copyFiles(buildSourceDir, target,
              fileType: ["ipa"], mode: buildMode ?? "release")
          .catchError((e) => null);

      if (output == null) {
        logger.logErrorVerbose
            .call("Failed to copy files from $buildSourceDir to $target");
        return 1;
      }
    }
    return 0;
  }

  /// Generates and copies debug symbols for Android release builds.
  ///
  /// Creates a compressed ZIP file containing native library debug symbols
  /// for crash reporting and debugging purposes. The symbols are packaged
  /// and copied to the Android distribution directory.
  ///
  /// Returns 0 on success, 1 on failure.
  Future<int> _generateAndCopyZipSymbols() async {
    logger.logDebug.call("Generating zip symbols");

    // Locate the native libraries directory containing debug symbols
    final outputDir = Directory(path.join(
        "build",
        "app",
        "intermediates",
        "merged_native_libs",
        "release",
        "mergeReleaseNativeLibs",
        "out",
        "lib"));

    if (!outputDir.existsSync()) {
      logger.logDebug.call("Failed to generate zip symbols");
      return 1;
    }

    // Clean up any existing files in the directory
    outputDir.listSync().forEach((value) {
      if (value is File) {
        value.deleteSync();
      }
    });

    // Compress the debug symbols
    final zipExitProcess =
        await CompressFiles.compress(outputDir.path, "debug_symbols.zip");
    final zipExitCode = zipExitProcess;

    if (zipExitCode != 0) {
      logger.logDebug
          .call("Failed to generate zip symbols with exit code: $zipExitCode");
      return zipExitCode;
    } else {
      final zipFile = File(path.join(outputDir.path, "debug_symbols.zip"));
      logger.logDebug.call("Debug symbols generated successfully");

      try {
        // Copy debug symbols to Android distribution directory
        final androidOutputPath = Files.androidDistributionOutputDir.path;
        final debugSymbolsPath =
            path.join(androidOutputPath, "debug_symbols.zip");

        // Remove existing debug symbols if present
        if (File(debugSymbolsPath).existsSync()) {
          await File(debugSymbolsPath).delete();
        }

        // Copy the new debug symbols
        await zipFile.copy(debugSymbolsPath);
        logger.logDebug
            .call("Debug symbols generated and copied to $debugSymbolsPath");
      } catch (e) {
        logger.logDebug.call("Failed to copy debug symbols: $e");
        return 1;
      } finally {
        // Clean up temporary zip file
        zipFile.delete();
      }
    }
    return 0;
  }
}
