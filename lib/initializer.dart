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
    ColorizeLogger.logDebug("==========================");
    ColorizeLogger.logDebug(
        "[Info] Make sure you follow the instructions to setup fastlane and configuration");
    ColorizeLogger.logDebug(
        "[Info] Please fill in the configuration file: ${environment.configPath}");
  }

  void _logOSInfo() {
    final os = Platform.operatingSystem;
    ColorizeLogger.logDebug(
        "Operating System: ${os[0].toUpperCase()}${os.substring(1)}");
  }

  void _checkPubspecFile() {
    if (!File('pubspec.yaml').existsSync()) {
      ColorizeLogger.logError(
          '[ERROR] The "pubspec.yaml" file was not found. Please ensure this command is executed in the root directory of your Flutter project.');
      exit(1);
    }
  }

  Future<void> _createDirectory(
      String path, Map<String, bool> initialized, String key) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      initialized[key] = true;
      ColorizeLogger.logSuccess('[SUCCESS] Created directory: $path');
    }
  }

  Future<void> _checkTool(
      String command, String toolName, Map<String, bool> initialized,
      {List<String> args = const []}) async {
    await Process.run(command, args).then((value) {
      if (value.exitCode != 0) {
        initialized[toolName.toLowerCase()] = false;
        ColorizeLogger.logError(
            '[ERROR] $toolName is not installed. Please install $toolName to proceed.');
        if (toolName == "Git") exit(1);
      } else {
        initialized[toolName.toLowerCase()] = true;
        ColorizeLogger.logSuccess('[SUCCESS] $toolName is installed.');
      }
    });
  }

  Future<void> _validateFastlaneJson(Map<String, bool> initialized) async {
    await Process.run("fastlane", [
      'run',
      'validate_play_store_json_key',
      'json_key:distribution/fastlane.json'
    ]).then((value) {
      if (value.exitCode != 0) {
        initialized["fastlane_json"] = false;
        ColorizeLogger.logError(
            "[ERROR] The Fastlane JSON key is invalid. Please ensure it is correctly configured.");
      } else {
        initialized["fastlane_json"] = true;
        ColorizeLogger.logSuccess('[SUCCESS] The Fastlane JSON key is valid.');
      }
    });
  }

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
        ColorizeLogger.logError("[ERROR] Failed to download Android metadata.");
      } else {
        ColorizeLogger.logSuccess(
            "[SUCCESS] Android metadata downloaded successfully.");
      }
    });
  }
}
