import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/parsers/compress_files.dart';

import '../files.dart';
import '../logger.dart';
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
        // Include Dart defines, one `--dart-define` per key/value pair
        ...dartDefineArguments,
        // Include Dart defines file
        if (dartDefinesFile?.isNotEmpty ?? false)
          '--dart-define-from-file=$dartDefinesFile',
        // Include build name/version
        if (buildName?.isNotEmpty ?? false) '--build-name=$buildName',
        // Include build number/version code
        if (buildNumber?.isNotEmpty ?? false) '--build-number=$buildNumber',
        // Include pub get flag
        if (pub) '--pub' else '--no-pub',
        // Include any custom arguments
        if (customArgs != null) ...customArgs!,
      ];

  /// Expands [dartDefines] into the `--dart-define` flags the Flutter CLI expects.
  ///
  /// Flutter has no `--dart-defines` option: each constant must be passed
  /// through its own repeated `--dart-define=KEY=VALUE` flag. Configuration
  /// files keep using the friendlier comma separated form
  /// (`"KEY1=VALUE1,KEY2=VALUE2"`), which is split here.
  List<String> get dartDefineArguments {
    final defines = dartDefines;
    if (defines == null || defines.trim().isEmpty) return const [];
    return defines
        .split(',')
        .map((define) => define.trim())
        .where((define) => define.isNotEmpty)
        .map((define) => '--dart-define=$define')
        .toList();
  }

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
    await registerSecrets();

    // Display build configuration before starting
    await printJob();

    // Get processed arguments with variable substitution
    final arguments = await this.arguments;
    final commandLine = ["flutter", "build", ...arguments].join(" ");

    logger.logCommand(commandLine);
    if (JobArguments.dryRun) return 0;

    // Start Flutter build process
    final Process process;
    try {
      process = await Process.start(
        "flutter",
        ["build", ...arguments],
        runInShell: true,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (e) {
      logger.logError(
        "Unable to start `flutter`: ${e.message}. "
        "Make sure the Flutter SDK is installed and available in your PATH.",
      );
      return 127;
    }

    // Stream build output to logger
    process.stdout.transform(utf8.decoder).listen(logger.logDebug);
    process.stderr.transform(utf8.decoder).listen(logger.logErrorVerbose);

    // A flutter build produces nothing on screen below --verbose and can run
    // for minutes, so without this the CLI looks hung.
    final exitCode = await Spinner.run(
      'building $binaryType'
      '${flavor == null || flavor!.isEmpty ? '' : " ($flavor)"}',
      () => process.exitCode,
    );
    if (exitCode != 0) {
      // `distribute build android` returns straight to the process exit code,
      // so without this line a failed standalone build printed nothing at all:
      // flutter's own diagnostics go to logErrorVerbose, which is hidden below
      // --verbose. The runner adds its own per-job line on top, naming the job.
      logger.logError("flutter build failed with exit code $exitCode");
      if (!logger.isVerbose) {
        logger.logDetail(
          ColorizeLogger.fileLoggingEnabled
              ? "re-run with --verbose, or see ${ColorizeLogger.logFilePath}"
              : "re-run with --verbose to see flutter's output",
        );
      }
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

      final sourceDirs = _androidArtifactSourceDirs();
      String? output;
      for (final sourceDir in sourceDirs) {
        output = await Files.copyFiles(
          sourceDir,
          target,
          fileType: [binaryType],
          mode: buildMode ?? "release",
          flavor: flavor,
        ).catchError((_) => null);

        if (output != null) {
          logger.logDebug.call(
            "Copied $binaryType artifact from $sourceDir to $target",
          );
          break;
        }
      }

      if (output == null) {
        logger.logErrorVerbose.call(
          "Failed to copy files from ${sourceDirs.join(', ')} to $target",
        );
        return 1;
      }
    } else if (this is ios_arguments.Arguments) {
      // Handle iOS build artifacts
      ios_arguments.Arguments iosArgs = this as ios_arguments.Arguments;
      String target = iosArgs.output ?? Files.iosDistributionOutputDir.path;

      final sourceDirs = _iosArtifactSourceDirs();
      String? output;
      for (final sourceDir in sourceDirs) {
        output = await Files.copyFiles(
          sourceDir,
          target,
          fileType: ["ipa"],
          mode: buildMode ?? "release",
          flavor: flavor,
        ).catchError((_) => null);

        if (output != null) {
          logger.logDebug
              .call("Copied ipa artifact from $sourceDir to $target");
          break;
        }
      }

      if (output == null) {
        logger.logErrorVerbose.call(
          "Failed to copy files from ${sourceDirs.join(', ')} to $target",
        );
        return 1;
      }
    }
    return 0;
  }

  List<String> _androidArtifactSourceDirs() {
    final outputRoot = path.join("build", "app", "outputs");
    final candidates = <String>[
      buildSourceDir,
      Files.androidOutputApks.path,
      path.join(outputRoot, "apk"),
      Files.androidOutputAppbundles.path,
      outputRoot,
      path.join("build", "app"),
    ];
    return candidates.toSet().toList();
  }

  List<String> _iosArtifactSourceDirs() {
    final candidates = <String>[
      buildSourceDir,
      Files.iosOutputIPA.path,
      path.join("build", "ios"),
      "build",
    ];
    return candidates.toSet().toList();
  }

  /// Locates the merged native libraries directory produced by Gradle.
  ///
  /// The layout cannot be hardcoded. Gradle names the intermediates directory
  /// after the *variant*, so a flavored build writes to `prodRelease` rather
  /// than `release`, and the task subdirectory
  /// (`mergeProdReleaseNativeLibs`) varies with the flavor and the Android
  /// Gradle Plugin version - older versions omit it entirely. Hardcoding
  /// `release/mergeReleaseNativeLibs` therefore silently missed every flavored
  /// build.
  ///
  /// Searches `<root>/build/app/intermediates/merged_native_libs` for a variant
  /// directory matching [mode] (and [flavor], when given), then for the `out/lib`
  /// directory beneath it. Returns `null` when nothing matches.
  static Directory? findNativeSymbolsDirectory({
    required String mode,
    String? flavor,
    Directory? root,
  }) {
    final base = Directory(
      path.join(
        root?.path ?? '.',
        "build",
        "app",
        "intermediates",
        "merged_native_libs",
      ),
    );
    if (!base.existsSync()) return null;

    final normalizedMode = mode.toLowerCase();
    final normalizedFlavor = flavor?.toLowerCase();

    // Gradle names the directory `<flavor><Mode>`, or just `<mode>` when there
    // is no flavor. Substring matching got this wrong in both directions:
    // flavor `dev` also matched `devQaRelease`, and with no flavor at all a
    // leftover `debugRelease` matched `release` and won on name length — which
    // is how a debug variant's `.so` files could be shipped as the release
    // symbol archive.
    final exact = normalizedFlavor == null || normalizedFlavor.isEmpty
        ? normalizedMode
        : '$normalizedFlavor$normalizedMode';

    final all = base.listSync().whereType<Directory>().toList();
    final variants = all.where((directory) {
      return path.basename(directory.path).toLowerCase() == exact;
    }).toList();

    if (variants.isEmpty) {
      // Nothing matched exactly. Fall back to the old, looser match so an
      // unusual Gradle setup still finds something, but order by modification
      // time: the directory this build just wrote is the one that matters,
      // and the longest name is not evidence of anything.
      variants.addAll(
        all.where((directory) {
          final name = path.basename(directory.path).toLowerCase();
          if (!name.contains(normalizedMode)) return false;
          if (normalizedFlavor != null && normalizedFlavor.isNotEmpty) {
            return name.contains(normalizedFlavor);
          }
          return true;
        }),
      );
      variants.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
    }

    for (final variant in variants) {
      final libDirectory = _findOutLib(variant);
      if (libDirectory != null) return libDirectory;
    }
    return null;
  }

  /// Finds the `out/lib` directory anywhere beneath [variant].
  static Directory? _findOutLib(Directory variant) {
    for (final entity in variant.listSync(recursive: true)) {
      if (entity is! Directory) continue;
      if (path.basename(entity.path) != 'lib') continue;
      if (path.basename(entity.parent.path) != 'out') continue;
      return entity;
    }
    return null;
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

    final outputDir = findNativeSymbolsDirectory(
      mode: buildMode ?? "release",
      flavor: flavor,
    );

    if (outputDir == null) {
      // Symbols are an aid for crash symbolication, not part of the artifact.
      // A release that built and copied successfully must not be reported as
      // failed just because Gradle laid its intermediates out differently.
      logger.logWarning(
        "no native debug symbols found; skipping the symbols archive",
      );
      logger.logDetail(
        "set `generate-debug-symbols: false` on the job to silence this",
      );
      return 0;
    }

    // Clean up any existing files in the directory
    outputDir.listSync().forEach((value) {
      if (value is File) {
        value.deleteSync();
      }
    });

    // Compress the debug symbols
    final zipExitProcess = await CompressFiles.compress(
      outputDir.path,
      "debug_symbols.zip",
    );
    final zipExitCode = zipExitProcess;

    if (zipExitCode != 0) {
      // Same reasoning as a missing symbols directory: the binary is already
      // built and copied, so a failed archive is a warning, not a build failure.
      logger.logWarning(
        "could not archive the debug symbols (exit $zipExitCode); skipping",
      );
      return 0;
    } else {
      final zipFile = File(path.join(outputDir.path, "debug_symbols.zip"));
      logger.logDebug.call("Debug symbols generated successfully");

      try {
        // Follow the job's configured output, not the default directory: the
        // fastlane publisher looks for `debug_symbols.zip` next to the binary,
        // so a custom `output:` would otherwise leave them in different places.
        final androidOutputPath =
            output ?? Files.androidDistributionOutputDir.path;
        final debugSymbolsPath = path.join(
          androidOutputPath,
          "debug_symbols.zip",
        );

        // Make sure the destination directory exists before copying into it.
        await Directory(androidOutputPath).create(recursive: true);

        // Remove existing debug symbols if present
        if (File(debugSymbolsPath).existsSync()) {
          await File(debugSymbolsPath).delete();
        }

        // Copy the new debug symbols
        await zipFile.copy(debugSymbolsPath);
        logger.logDebug.call(
          "Debug symbols generated and copied to $debugSymbolsPath",
        );
      } catch (e) {
        logger.logWarning("could not copy the debug symbols: $e");
        return 0;
      } finally {
        // Clean up the temporary zip file. Awaited so the delete cannot race
        // with the copy above or with process exit.
        if (zipFile.existsSync()) await zipFile.delete();
      }
    }
    return 0;
  }
}
