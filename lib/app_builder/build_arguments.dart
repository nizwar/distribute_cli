import 'dart:convert';
import 'dart:io';

import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;

import '../files.dart';
import '../logger.dart';
import '../parsers/config_parser.dart';
import '../parsers/job_arguments.dart';
import 'ios/arguments.dart' as ios_arguments;

/// Abstract class representing build arguments for the build process.
///
/// The [BuildArguments] class defines the structure for arguments
/// used in the build process, such as binary type, build mode, and
/// additional custom arguments.
abstract class BuildArguments extends JobArguments {
  /// The type of binary to build (e.g., apk, aab).
  final String binaryType;

  /// The output path for the build (optional).
  String? output;

  /// The target file to build (optional).
  final String? target;

  /// The build mode (e.g., release, debug).
  final String? buildMode;

  /// The flavor of the build (optional).
  final String? flavor;

  /// Dart defines as a string (optional).
  final String? dartDefines;

  /// Path to a file containing Dart defines (optional).
  final String? dartDefinesFile;

  /// The build name (optional).
  final String? buildName;

  /// The build number (optional).
  final String? buildNumber;

  /// Whether to run `pub get` before building.
  final bool pub;

  /// Additional custom arguments for the build process (optional).
  final List<String>? customArgs;

  /// The source directory for the build.
  final String buildSourceDir;

  late BuilderJob parent;

  /// Creates a new `BuildArguments` instance.
  ///
  /// - [binaryType]: The type of binary to build.
  /// - [buildMode]: The build mode (default is 'release').
  /// - [target]: The target file to build (optional).
  /// - [flavor]: The flavor of the build (optional).
  /// - [dartDefines]: Dart defines as a string (optional).
  /// - [dartDefinesFile]: Path to a file containing Dart defines (optional).
  /// - [customArgs]: Additional custom arguments for the build process (optional).
  /// - [buildName]: The build name (optional).
  /// - [buildNumber]: The build number (optional).
  /// - [pub]: Whether to run `pub get` before building (default is true).
  BuildArguments({
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

  /// Returns the list of arguments for the build process.
  @override
  List<String> get results => [
        if (binaryType.isNotEmpty) binaryType,
        if (target?.isNotEmpty ?? false) '--target=$target',
        if (buildMode?.isNotEmpty ?? false) '--$buildMode',
        if (flavor?.isNotEmpty ?? false) '--flavor=$flavor',
        if (dartDefines?.isNotEmpty ?? false) '--dart-defines=$dartDefines',
        if (dartDefinesFile?.isNotEmpty ?? false)
          '--dart-defines-file=$dartDefinesFile',
        if (buildName?.isNotEmpty ?? false) '--build-name=$buildName',
        if (buildNumber?.isNotEmpty ?? false) '--build-number=$buildNumber',
        if (pub) '--pub' else '--no-pub',
        if (customArgs != null) ...customArgs!,
      ];

  /// Executes the build process.
  ///
  /// - [onVerbose]: A callback function for verbose logging.
  /// - [onError]: A callback function for error logging.
  ///
  /// Returns the exit code of the build process.
  Future<int> build(final environments,
      {Function(String)? onVerbose, Function(String)? onError}) async {
    ColorizeLogger logger = ColorizeLogger(true);
    final rawArguments = toJson();
    rawArguments.removeWhere((key, value) => value == null);
    if (logger.isVerbose) {
      logger.logInfo("Running build with configurations:");
      for (var value in rawArguments.keys) {
        logger.logInfo(" - $value: ${rawArguments[value]}");
      }
      logger.logEmpty();
    }
    onVerbose?.call("Starting build with `flutter ${substituteVariables([
          "build",
          ...results
        ].join(" "), environments)}`");
    final process = await Process.start("flutter",
        ["build", ...results.map((e) => substituteVariables(e, environments))]);
    process.stdout.transform(utf8.decoder).listen(onVerbose);
    process.stderr.transform(utf8.decoder).listen(onError);
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      onError?.call("Build failed with exit code: $exitCode");
      return exitCode;
    }
    // Move the output files to the distribution directory
    final moveResult = await _moveOutputFiles(onVerbose, onError);
    if (moveResult != 0) return moveResult;

    // Generate zip symbols and put it on android's distribution directory
    if ((this is android_arguments.Arguments)) {
      if (buildMode == "release" &&
          (this as android_arguments.Arguments).generateDebugSymbols) {
        final zipResult = await _generateAndCopyZipSymbols(onVerbose);
        if (zipResult != 0) return zipResult;
      }
    }
    return exitCode;
  }

  Future<int> _moveOutputFiles(
      Function(String)? onVerbose, Function(String)? onError) async {
    if (this is android_arguments.Arguments) {
      android_arguments.Arguments androidArgs =
          this as android_arguments.Arguments;
      String target =
          androidArgs.output ?? Files.androidDistributionOutputDir.path;
      final output = await Files.copyFiles(buildSourceDir, target,
              fileType: [binaryType], mode: buildMode ?? "release")
          .catchError((e) {
        onError?.call(e.toString());
        return null;
      });
      if (output == null) {
        onError?.call("Failed to copy files from $buildSourceDir to $target");
        return 1;
      }
    } else if (this is ios_arguments.Arguments) {
      ios_arguments.Arguments iosArgs = this as ios_arguments.Arguments;
      String target = iosArgs.output ?? Files.iosDistributionOutputDir.path;
      final output = await Files.copyFiles(buildSourceDir, target,
              fileType: ["ipa"], mode: buildMode ?? "release")
          .catchError((e) => null);
      if (output == null) {
        onError?.call("Failed to copy files from $buildSourceDir to $target");
        return 1;
      }
    }
    return 0;
  }

  Future<int> _generateAndCopyZipSymbols(Function(String)? onVerbose) async {
    onVerbose?.call("Generating zip symbols");
    final outputDir = Directory(
        "build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib");
    if (!outputDir.existsSync()) {
      onVerbose?.call("Failed to generate zip symbols");
      return 1;
    }

    outputDir.listSync().forEach((value) {
      if (value is File) {
        value.deleteSync();
      }
    });
    final zipExitProcess = await Process.start(
        "zip", ["-r", "debug_symbols.zip", "."],
        workingDirectory: outputDir.path);
    zipExitProcess.stdout.transform(utf8.decoder).listen(onVerbose);
    zipExitProcess.stderr.transform(utf8.decoder).listen(onVerbose);
    final zipExitCode = await zipExitProcess.exitCode;
    if (zipExitCode != 0) {
      onVerbose
          ?.call("Failed to generate zip symbols with exit code: $zipExitCode");
      return zipExitCode;
    } else {
      final zipFile = File("${outputDir.path}/debug_symbols.zip");
      onVerbose?.call("Debug symbols generated successfully");
      try {
        if(File("$output/debug_symbols.zip").existsSync()) {
          await File("$output/debug_symbols.zip").delete();
        }
        await zipFile.copy("$output/debug_symbols.zip");
        onVerbose?.call(
            "Debug symbols generated and copied to $output/debug_symbols.zip");
      } catch (e) {
        onVerbose?.call("Failed to copy debug symbols: $e");
        return 1;
      } finally {
        zipFile.delete();
      }
    }
    return 0;
  }
}
