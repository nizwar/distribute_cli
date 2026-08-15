import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/app_builder/android/arguments.dart'
    as android_arguments;
import 'package:distribute_cli/app_publisher/fastlane/arguments.dart'
    as fastlane_publisher;
import 'package:distribute_cli/app_publisher/xcrun/arguments.dart'
    as xcrun_publisher;
import 'package:distribute_cli/files.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/build_info.dart';
import 'package:distribute_cli/parsers/compress_files.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:distribute_cli/parsers/task_arguments.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:path/path.dart' as path;
import 'package:yaml_codec/yaml_codec.dart';

import 'app_builder/ios/arguments.dart' as ios_arguments;
import 'command.dart';
import 'version.dart';

/// Command to initialize the project with configuration files and directories.
///
/// The `InitializerCommand` class sets up the necessary files and directories
/// for the distribution process, validates required tools, and prepares the environment.
/// It creates platform-specific directories, validates development tools, and generates
/// initial configuration files.
class InitializerCommand extends Commander {
  /// The description of the init command shown in help text
  @override
  String get description =>
      "Initialize the project with the necessary configuration files and directories.";

  /// The name of the command used in CLI
  @override
  String get name => "init";

  /// Argument parser for the init command with platform-specific options.
  ///
  /// Available options:
  /// - `--android-package-name` or `-a` - Package name for Android application
  /// - `--ios-package-name` or `-i` - Bundle identifier for iOS application
  /// - `--skip-tools` or `-s` - Skip tool validation during initialization
  /// - `--google-service-account` or `-g` - Google service account for Fastlane integration
  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      "android-package-name",
      abbr: 'a',
      help: 'Package name for the application.',
      defaultsTo: BuildInfo.androidPackageName,
    )
    ..addOption(
      "ios-package-name",
      abbr: 'i',
      help: 'Bundle identifier for the iOS application.',
      defaultsTo: BuildInfo.iosBundleId,
    )
    ..addFlag(
      "skip-tools",
      abbr: 's',
      help: 'Skip tool validation.',
      defaultsTo: false,
    )
    ..addOption(
      "google-service-account",
      abbr: 'g',
      help:
          'Google service for fastlane, if it validated it will be copied to the fastlane directory.',
    );

  /// Executes the initialization command to set up the project.
  ///
  /// This method performs the following tasks:
  /// - Creates necessary distribution directories
  /// - Validates required development tools
  /// - Sets up platform-specific configurations
  /// - Generates initial configuration files
  /// - Downloads metadata for Android publishing
  ///
  /// The initialization process includes:
  /// - Directory structure creation for Android and iOS (macOS only)
  /// - Tool validation for Flutter, Firebase, Git, Fastlane, and compression tools
  /// - Fastlane configuration setup
  /// - Google Play Console metadata download
  @override
  Future<int> run() async {
    final initialized = <String, bool>{};
    final configFilePath = configPath;
    _logWelcome();
    if (!_checkPubspecFile()) return 1;
    await _createDirectory(
      path.join("distribution", "android", "output"),
      initialized,
      "android_directory",
    );
    if (Platform.isMacOS) {
      await _createDirectory(
        path.join("distribution", "ios", "output"),
        initialized,
        "ios_directory",
      );
    }

    if (!(argResults!['skip-tools'] as bool)) {
      await _checkTool(
        "flutter",
        "Flutter",
        initialized,
        args: ['--version'],
      ).catchError((_) => -1);
      await _checkTool(
        "firebase",
        "Firebase",
        initialized,
      ).catchError((_) => -1);
      await _checkTool(
        "git",
        "Git",
        initialized,
        args: ['--version'],
      ).catchError((_) => -1);

      await CompressFiles.checkTools().then((value) {
        if (!value) {
          logger.logWarning("archiver  ${ColorizeLogger.dim("not found")}");
        } else {
          logger.logSuccess("archiver  ${ColorizeLogger.dim("available")}");
          initialized["compress_tool"] = true;
        }
      });

      await _checkTool(
        "fastlane",
        "Fastlane",
        initialized,
        args: ['actions'],
      ).catchError((_) => -1).then((value) async {
        if (value == 0) {
          await _validateFastlaneJson(initialized).then((value) async {
            if (value == 0) return await _downloadAndroidMetaData();
          });
        } else {
          final install = Platform.isWindows
              ? 'gem install fastlane'
              : 'sudo gem install fastlane';
          logger.logDetail('install with `$install` (requires Ruby)');
          initialized["fastlane_json"] = false;
        }
      });
      if (Platform.isMacOS) {
        await _checkTool(
          "xcrun",
          "XCRun",
          initialized,
          args: ["altool", "-h"],
        ).catchError((_) => -1);
      }
    }

    final yaml = File(configFilePath);
    if (yaml.existsSync()) {
      logger.logWarning(
          "kept     ${ColorizeLogger.dim("$configFilePath already exists")}");
    } else {
      await yaml.writeAsString(yamlEncode(structures), flush: true);
      logger.logSuccess("created  ${ColorizeLogger.dim(configFilePath)}");
    }

    await _ensureLogIsIgnored();
    return 0;
  }

  /// Adds the generated artifacts to `.gitignore` when the project uses git.
  ///
  /// `distribution.log` can contain command output from Fastlane and Firebase,
  /// so it must never be committed. The `distribution/output` folders hold
  /// signed binaries, which do not belong in version control either.
  Future<void> _ensureLogIsIgnored() async {
    final gitignore = File('.gitignore');
    if (!gitignore.existsSync()) return;

    const entries = [
      'distribution.log',
      'distribution/android/output/',
      'distribution/ios/output/',
      'distribution/google-key.json',
    ];

    final content = await gitignore.readAsString();
    final existing = content.split('\n').map((line) => line.trim()).toSet();
    final missing =
        entries.where((entry) => !existing.contains(entry)).toList();
    if (missing.isEmpty) return;

    final prefix = content.endsWith('\n') || content.isEmpty ? '' : '\n';
    await gitignore.writeAsString(
      "$prefix\n# Added by distribute_cli\n${missing.join('\n')}\n",
      mode: FileMode.append,
    );
    logger.logSuccess(
      "gitignore  ${ColorizeLogger.dim("added ${missing.length} entr(ies)")}",
    );
  }

  /// Prints the one line init header.
  void _logWelcome() {
    final sep = LogSymbols.separator;
    logger.logInfo(
      ColorizeLogger.dim(
        "distribute $packageVersion  $sep  init  $sep  ${Platform.operatingSystem}",
      ),
    );
    logger.logEmpty();
  }

  /// Checks if the `pubspec.yaml` file exists.
  ///
  /// Returns `false` instead of terminating the process, so the caller decides
  /// the exit code and the log file is flushed normally.
  bool _checkPubspecFile() {
    if (File('pubspec.yaml').existsSync()) return true;
    logger.logError(
      'The "pubspec.yaml" file was not found. Please ensure this command is executed in the root directory of your Flutter project.',
    );
    return false;
  }

  /// Creates a directory if it does not exist.
  ///
  /// [path] is the directory path.
  /// [initialized] is the map to track initialization status.
  /// [key] is the key for the directory in the map.
  Future<void> _createDirectory(
    String path,
    Map<String, bool> initialized,
    String key,
  ) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      initialized[key] = true;
      logger.logSuccess("created  ${ColorizeLogger.dim(path)}");
    }
  }

  /// Checks if a tool is installed.
  ///
  /// [command] is the tool's command.
  /// [toolName] is the name of the tool.
  /// [initialized] is the map to track initialization status.
  /// [args] are additional arguments for the tool.
  Future<int> _checkTool(
    String command,
    String toolName,
    Map<String, bool> initialized, {
    List<String> args = const [],
  }) async {
    logger.logDebug("Checking if $toolName is installed...");
    logger.logDebug("Command: $command ${args.join(" ")}");

    final exitCode = await _runTool(command, args);
    if (exitCode != 0) {
      initialized[toolName.toLowerCase()] = false;
      logger.logWarning(
        "${toolName.padRight(9)}  ${ColorizeLogger.dim("not installed")}",
      );
    } else {
      initialized[toolName.toLowerCase()] = true;
      logger.logSuccess(
        "${toolName.padRight(9)}  ${ColorizeLogger.dim("installed")}",
      );
    }
    return exitCode;
  }

  /// Runs [command] and streams both of its output streams to the logger.
  ///
  /// Draining `stderr` is not optional: a tool such as `fastlane actions` writes
  /// enough to it to fill the OS pipe buffer, and an undrained pipe blocks the
  /// child process forever. Returns `127` when the executable does not exist.
  Future<int> _runTool(String command, List<String> args) async {
    final Process process;
    try {
      process = await Process.start(
        command,
        args,
        includeParentEnvironment: true,
        runInShell: true,
      );
    } on ProcessException {
      return 127;
    }

    final drained = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(logger.logDebug),
      process.stderr.transform(utf8.decoder).forEach(logger.logDebug),
    ]);

    final exitCode = await process.exitCode;
    await drained;
    return exitCode;
  }

  /// Validates the Fastlane JSON key.
  ///
  /// [initialized] is the map to track initialization status.
  Future<int> _validateFastlaneJson(Map<String, bool> initialized) async {
    final String? jsonKeyPath =
        argResults?['google-service-account'] as String?;
    logger.logDebug("Validating Fastlane JSON key...");

    File jsonKeyFile =
        jsonKeyPath != null ? File(jsonKeyPath) : Files.fastlaneJson;

    if (!jsonKeyFile.existsSync()) {
      logger.logWarning(
        "play key   ${ColorizeLogger.dim("missing at ${jsonKeyFile.path}")}",
      );
      initialized["fastlane_json"] = false;
      return -1;
    }
    final exitCode = await _runTool("fastlane", [
      'run',
      'validate_play_store_json_key',
      'json_key:${jsonKeyPath ?? Files.fastlaneJson.path}',
    ]);

    if (exitCode != 0) {
      initialized["fastlane_json"] = false;
      logger.logError("play key   ${ColorizeLogger.dim("invalid")}");
      return -1;
    }

    initialized["fastlane_json"] = true;
    logger.logSuccess("play key   ${ColorizeLogger.dim("valid")}");
    if (jsonKeyPath != null) {
      try {
        await Files.fastlaneJson.parent.create(recursive: true);
        if (await Files.fastlaneJson.exists()) {
          await Files.fastlaneJson.delete();
        }
        await File(jsonKeyPath).copy(Files.fastlaneJson.path);
        logger.logDebug(
          "Fastlane JSON key copied to ${Files.fastlaneJson.path}",
        );
      } catch (error) {
        logger.logWarning("Failed to copy the Fastlane JSON key: $error");
      }
    }
    return 0;
  }

  /// Downloads Android metadata from the Play Store.
  ///
  /// [environment] is the environment configuration.
  Future<void> _downloadAndroidMetaData() async {
    if (await Files.androidDistributionMetadataDir.exists()) {
      await Files.androidDistributionMetadataDir.delete(recursive: true);
    }
    if (argResults?['android-package-name'] == null ||
        (argResults!['android-package-name'] as String).isEmpty) {
      logger.logError(
        "Android package name is required to download metadata. Please provide it using --android-package-name option.",
      );
      return;
    }
    logger.logDebug("Downloading Android metadata from Play Store...");
    final exitCode = await _runTool("fastlane", [
      "run",
      "download_from_play_store",
      "package_name:${argResults!['android-package-name'] as String}",
      "json_key:${Files.fastlaneJson.path}",
      "metadata_path:${Files.androidDistributionMetadataDir.path}",
    ]);

    if (exitCode != 0) {
      logger.logWarning(
        "metadata   ${ColorizeLogger.dim("download failed (exit $exitCode)")}",
      );
    } else {
      logger.logSuccess("metadata   ${ColorizeLogger.dim("downloaded")}");
    }
  }

  Map<String, dynamic> get structures => {
        "name": "Distribution CLI",
        "description": "A CLI tool to build and publish your application.",
        "variables": {
          "ANDROID_PACKAGE": argResults?['android-package-name'] as String?,
          "IOS_PACKAGE": argResults?['ios-package-name'] as String?,
          "APPLE_ID": "\${APPLE_ID}",
          "APPLE_APP_SPECIFIC_PASSWORD": "\${APPLE_APP_SPECIFIC_PASSWORD}",
        },
        "tasks": [
          Task(
            name: "Android Build and deploy",
            key: "android",
            description:
                "Build and deploy the Android application to playstore.",
            workflows: ["build", "publish"],
            jobs: [
              Job(
                name: "Build Android",
                description: "Build the Android application using Gradle.",
                key: "build",
                packageName: "\${{ANDROID_PACKAGE}}",
                builder: BuilderJob(
                  android: android_arguments.Arguments(
                    Variables.fromSystem(globalResults),
                    binaryType: "aab",
                    buildMode: "release",
                  ),
                ),
              ),
              Job(
                name: "Publish Android",
                description:
                    "Publish the Android application to playstore as internal test track.",
                key: "publish",
                packageName: "\${{ANDROID_PACKAGE}}",
                publisher: PublisherJob(
                  fastlane: fastlane_publisher.Arguments(
                    Variables.fromSystem(globalResults),
                    filePath: Files.androidDistributionOutputDir.path,
                    metadataPath: Files.androidDistributionMetadataDir.path,
                    jsonKey: Files.fastlaneJson.path,
                    track: 'internal',
                    trackPromoteTo: 'production',
                    binaryType: 'aab',
                    skipUploadImages: true,
                    skipUploadScreenshots: true,
                  ),
                ),
              ),
            ],
          ).toJson(),
          if (Platform.isMacOS)
            Task(
              name: "iOS Build and deploy",
              key: "ios",
              description: "Build and deploy the iOS application to app store.",
              jobs: [
                Job(
                  name: "Build iOS",
                  description: "Build the iOS application using Xcode.",
                  key: "build",
                  packageName: "\${{IOS_PACKAGE}}",
                  builder: BuilderJob(
                    ios: ios_arguments.Arguments(
                      Variables.fromSystem(globalResults),
                      binaryType: "ipa",
                      buildMode: "release",
                    ),
                  ),
                ),
                Job(
                  name: "Publish iOS",
                  description: "Publish the iOS application to app store.",
                  key: "publish",
                  packageName: "\${{IOS_PACKAGE}}",
                  publisher: PublisherJob(
                    xcrun: xcrun_publisher.Arguments(
                      Variables.fromSystem(globalResults),
                      filePath: Files.iosDistributionOutputDir.path,
                      username: "\${{APPLE_ID}}",
                      password: "\${{APPLE_APP_SPECIFIC_PASSWORD}}",
                    ),
                  ),
                ),
              ],
            ).toJson(),
        ],
      };
}
