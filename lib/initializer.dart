import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'logger.dart';

import 'helper.dart';

class InitCommand extends Command {
  final Helper helper;
  InitCommand(this.helper);

  @override
  String get description => "Initialize the distribution tool.";

  @override
  String get name => "init";

  @override
  FutureOr? run() async {
    final Map<String, bool> initialized = {};
    File pubspecFile = File('pubspec.yaml');
    Directory androidDirectory = Directory("distribution/android");
    Directory iosDirectory = Directory("distribution/ios");
    final file = File("dist");
    if(!await file.exists()){
      await file.create(recursive: true);
    }

    if (Platform.isMacOS) {
      ColorizeLogger.logDebug("OS : MacOS");
    } else if (Platform.isLinux) {
      ColorizeLogger.logDebug("OS : Linux");
    } else if (Platform.isWindows) {
      ColorizeLogger.logDebug("OS : Windows");
    } else {
      ColorizeLogger.logDebug("OS : Unknown OS");
    }

    /// Check if pubspec.yaml file exists
    if (!pubspecFile.existsSync()) {
      ColorizeLogger.logError('[X] pubspec.yaml file not found. Please run this command in the root directory of your Flutter project.');
      exit(1);
    }

    if (!await androidDirectory.exists()) {
      await androidDirectory.create(recursive: true);
      initialized["android_directory"] = true;
      ColorizeLogger.logSuccess('[OK] Created android distribution directory');
    }

    if (Platform.isMacOS) {
      if (!await iosDirectory.exists()) {
        await iosDirectory.create(recursive: true);
        initialized["ios_directory"] = true;
        ColorizeLogger.logSuccess('[OK] Created ios distribution directory');
      }
    }

    await Process.run("git", ["help"]).then((value) {
      if (value.exitCode != 0) {
        initialized["git"] = false;
        ColorizeLogger.logError('[X] Git is not installed. Please install Git to use this tool.');
        exit(1);
      } else {
        initialized["git"] = true;
        ColorizeLogger.logSuccess('[OK] Git is installed.');
      }
    });

    await Process.run("firebase", []).then((value) {
      if (value.exitCode != 0) {
        initialized["firebase"] = false;
        ColorizeLogger.logError('[X] Firebase CLI is not installed. Please install it to use Firebase distribution.');
      } else {
        initialized["firebase"] = true;
        ColorizeLogger.logSuccess('[OK] Firebase CLI is installed.');
      }
    });

    await Process.run("fastlane", ['actions']).then((value) {
      if (value.exitCode != 0) {
        initialized["fastlane"] = false;
        ColorizeLogger.logError('[X] Fastlane is not installed. Please install it to use Fastlane distribution.');
      } else {
        initialized["fastlane"] = true;
        ColorizeLogger.logSuccess('[OK] Fastlane is installed.');
      }
    });

    await Process.run("fastlane", ['run', 'validate_play_store_json_key', 'json_key:distribution/fastlane.json']).then((value) {
      if (value.exitCode != 0) {
        initialized["fastlane_json"] = false;
        ColorizeLogger.logError('[X] Fastlane JSON key is not valid. Please check the JSON key file.');
      } else {
        initialized["fastlane_json"] = true;
        ColorizeLogger.logSuccess('[OK] Fastlane JSON key is valid.');
      }
    });

    if (Platform.isMacOS) {
      await Process.start("xcrun", ['--version']).then((value) async {
        if (await value.exitCode != 0) {
          initialized["xcrun"] = false;
          ColorizeLogger.logError('[X] XCRun is not installed. Please install it to use iOS distribution.');
        } else {
          initialized["xcrun"] = true;
          ColorizeLogger.logSuccess('[OK] XCRun is installed.');
        }
      });
    }

    await file.writeAsString(jsonEncode(initialized), flush: true, mode: FileMode.write, encoding: utf8);
    ColorizeLogger.logDebug("==========================");
    ColorizeLogger.logDebug("[Info] Make sure you follow the instructions to setup fastlane and configuration");
    ColorizeLogger.logDebug("[Info] Please fill in the configuration file: ${helper.configPath}");
  }
}
