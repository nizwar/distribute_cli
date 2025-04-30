import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:distribute_cli/environment.dart';
import 'files.dart';
import 'logger.dart';

/// A command to initialize the distribution environment.
///
/// The `InitCommand` class sets up the necessary directories, checks for
/// required tools (e.g., Git, Firebase CLI, Fastlane), and validates the
/// configuration for the distribution process.
///
/// To use this class, invoke the `init` command:
/// ```
/// distribute init
/// ```
class InitCommand extends Command {
  /// Initializes the `InitCommand` class.
  InitCommand();

  /// Logger for logging messages.
  late final ColorizeLogger logger;

  @override

  /// Provides a description of the `init` command.
  String get description => "Initialize the distribution tool.";

  @override

  /// The name of the `init` command.
  String get name => "init";

  @override

  /// Executes the `init` command to set up the distribution environment.
  Future? run() async {
    final environment = Environment.fromArgResults(globalResults);
    final initialized = <String, bool>{};

    logger = ColorizeLogger(environment);

    _logOSInfo();
    _checkPubspecFile();
    await _createDirectory(
        "distribution/android", initialized, "android_directory");
    if (Platform.isMacOS) {
      await _createDirectory("distribution/ios", initialized, "ios_directory");
    }

    await _checkTool("git", "Git", initialized, args: ["help"]);
    await _checkTool("firebase", "Firebase", initialized);
    await _checkTool("fastlane", "Fastlane", initialized, args: ['actions']);
    await _validateFastlaneJson(initialized);
    await _downloadAndroidMetaData(environment);

    if (Platform.isMacOS) {
      await _checkTool("xcrun", "XCRun", initialized, args: ["altool", "-h"]);
    }

    await File("dist").writeAsString(jsonEncode(initialized),
        flush: true, mode: FileMode.write, encoding: utf8);
    logger.logInfo(
        "Make sure you follow the instructions to setup configurations");
    logger.logInfo(
        "Please fill in the configuration file: ${environment.configPath}");
    exit(0);
  }

  /// Logs the operating system information.
  void _logOSInfo() {
    final os = Platform.operatingSystem;
    logger
        .logInfo("Operating System: ${os[0].toUpperCase()}${os.substring(1)}");
  }

  /// Checks if the `pubspec.yaml` file exists.
  void _checkPubspecFile() {
    if (!File('pubspec.yaml').existsSync()) {
      logger.logError(
          'The "pubspec.yaml" file was not found. Please ensure this command is executed in the root directory of your Flutter project.');
      exit(1);
    }
  }

  /// Creates a directory if it does not exist.
  ///
  /// [path] is the directory path.
  /// [initialized] is the map to track initialization status.
  /// [key] is the key for the directory in the map.
  Future<void> _createDirectory(
      String path, Map<String, bool> initialized, String key) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      initialized[key] = true;
      logger.logSuccess('Created directory: $path');
    }
  }

  /// Checks if a tool is installed.
  ///
  /// [command] is the tool's command.
  /// [toolName] is the name of the tool.
  /// [initialized] is the map to track initialization status.
  /// [args] are additional arguments for the tool.
  Future<void> _checkTool(
      String command, String toolName, Map<String, bool> initialized,
      {List<String> args = const []}) async {
    await Process.run(command, args).then((value) {
      if (value.exitCode != 0) {
        initialized[toolName.toLowerCase()] = false;
        logger.logError(
            '$toolName is not installed. Please install $toolName to proceed.');
        if (toolName == "Git") exit(1);
      } else {
        initialized[toolName.toLowerCase()] = true;
        logger.logSuccess('$toolName is installed.');
      }
    });
  }

  /// Validates the Fastlane JSON key.
  ///
  /// [initialized] is the map to track initialization status.
  Future<void> _validateFastlaneJson(Map<String, bool> initialized) async {
    await Process.run("fastlane", [
      'run',
      'validate_play_store_json_key',
      'json_key:distribution/fastlane.json'
    ]).then((value) {
      if (value.exitCode != 0) {
        initialized["fastlane_json"] = false;
        logger.logError(
            "[ERROR] The Fastlane JSON key is invalid. Please ensure it is correctly configured.");
      } else {
        initialized["fastlane_json"] = true;
        logger.logSuccess('[SUCCESS] The Fastlane JSON key is valid.');
      }
    });
  }

  /// Downloads Android metadata from the Play Store.
  ///
  /// [environment] is the environment configuration.
  Future<void> _downloadAndroidMetaData(Environment environment) async {
    if (await Files.androidDistributionMetadataDir.exists()) {
      await Files.androidDistributionMetadataDir.delete(recursive: true);
    }
    await Process.run("fastlane", [
      "run",
      "download_from_play_store",
      "package_name:${environment.androidPackageName}",
      "json_key:${Files.fastlaneJson.path}",
      "metadata_path:${Files.androidDistributionMetadataDir.path}"
    ]).then((value) {
      if (value.exitCode != 0) {
        logger.logError("[ERROR] Failed to download Android metadata.");
      } else {
        logger
            .logSuccess("[SUCCESS] Android metadata downloaded successfully.");
      }
    });
  }
}
