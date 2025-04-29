import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'environment.dart';
import 'logger.dart';

/// A command to handle the publishing process of the app.
///
/// The `Publisher` class provides functionality to build and distribute
/// Android and iOS apps using Firebase or Fastlane. It supports configuration
/// through command-line arguments and environment settings.
///
/// To use this class, invoke the `publish` command with the desired flags:
/// ```
/// distribute publish --android --firebase
/// ```
class Publisher extends Command {
  /// The environment configuration for the distribution process.
  late Environment environment;

  Publisher();

  factory Publisher.fromArgResults(ArgResults? argResults) {
    final instance = Publisher();
    instance.environment = Environment.fromArgResults(argResults);
    instance.isAndroidBuild = instance.environment.isAndroidBuild;
    instance.isIOSBuild = instance.environment.isIOSBuild;
    instance.fastlanePromoteTrackTo = instance.environment.androidPlaystoreTrackPromoteTo;
    instance.fastlaneTrack = instance.environment.androidPlaystoreTrack;
    instance.useFastlane = instance.environment.useFastlane;
    instance.useFirebase = instance.environment.useFirebase;
    return instance;
  }

  // /// Checks if the Android build flag is enabled.
  // bool get isAndroidBuild => argResults?['android'] as bool? ?? false;

  // /// Checks if the iOS build flag is enabled.
  // bool get isIOSBuild => argResults?['ios'] as bool? ?? false;

  // /// Checks if Firebase is used for distribution.
  // bool get useFirebase => argResults?['firebase'] as bool? ?? false;

  // /// Checks if Fastlane is used for distribution.
  // bool get useFastlane => argResults?['fastlane'] as bool? ?? false;

  // ///Playstore track while uploaded with fastlane
  // String get fastlaneTrack => argResults?['fastlane_track'] as String? ?? "internal";

  // ///Playstore promote track to while uploaded with fastlane
  // String get fastlanePromoteTrackTo => argResults?['fastlane_promote_track_to'] as String? ?? "production";

  /// Checks if the Android build flag is enabled.
  bool isAndroidBuild = false;

  /// Checks if the iOS build flag is enabled.
  bool isIOSBuild = false;

  /// Checks if Firebase is used for distribution.
  bool useFirebase = false;

  /// Checks if Fastlane is used for distribution.
  bool useFastlane = false;

  ///Playstore track while uploaded with fastlane
  String fastlaneTrack = "internal";

  ///Playstore promote track to while uploaded with fastlane
  String fastlanePromoteTrackTo = "production";

  @override

  /// Configures the argument parser for the `publish` command.
  ArgParser get argParser {
    environment = Environment.fromArgResults(argResults ?? globalResults);
    return ArgParser()
      ..addFlag("android", defaultsTo: environment.isAndroidDistribute, help: "Build and distribute Android (Default value follows the config file)")
      ..addOption("fastlane_track", defaultsTo: environment.androidPlaystoreTrack, help: "Playstore track for Android (Default value follows the config file)")
      ..addOption("fastlane_promote_track_to", defaultsTo: environment.androidPlaystoreTrackPromoteTo, help: "Playstore track promote to for Android (Default value follows the config file)")
      ..addOption("fastlane_args", help: "Arguments for Fastlane")
      ..addFlag("ios", defaultsTo: Platform.isMacOS ? environment.isIOSDistribute : false, help: "Build and distribute iOS (Default value follows the config file)")
      ..addFlag("firebase", defaultsTo: environment.useFirebase, help: "Use Firebase for distribution (Default value follows the config file)")
      ..addFlag("fastlane", defaultsTo: environment.useFastlane, help: "Use Fastlane for distribution (Default value follows the config file)");
  }

  /// Publishes the app by building and distributing it based on the provided flags.
  Future<int> publish() async {
    await buildAndroidDocs();
    if (isAndroidBuild) {
      return await distributeAndroid();
    } else if (isIOSBuild) {
      return await distributeIOS();
    }
    ColorizeLogger.logError("No distribution tasks to execute.");
    return 0;
  }

  /// Builds the Android changelogs based on the git logs since yesterday.
  Future<int> buildAndroidDocs() async {
    final docs = await Process.run("git", ["log", "--pretty='format:%s'", "--since=yesterday.midnight"]);
    if (docs.exitCode != 0) {
      ColorizeLogger.logError("Error while getting git logs");
      return 1;
    }
    final log = docs.stdout.toString().replaceAll("'", "");
    final metadataDir = Directory("distribution/android/metadata");

    if (!await metadataDir.exists()) {
      ColorizeLogger.logDebug("Metadata directory not found, creating...");
      await metadataDir.create(recursive: true);
      ColorizeLogger.logDebug("Metadata directory created");
      metadataDir.listSync().map((element) async {
        if (element is Directory) {
          final file = File("${element.path}/changelogs/default.txt");
          if (file.existsSync()) {
            file.deleteSync();
          }

          await file.writeAsString(log);
        }
      });
    }
    return 0;
  }

  /// Distributes the Android app bundles to the configured platforms.
  Future<int> distributeAndroid() async {
    Directory distributionDir = Directory("distribution/android/output");
    if (!await distributionDir.exists()) {
      await distributionDir.create(recursive: true);
    }

    final distributionDirList = await distributionDir.list().toList().then((value) => value.where((element) => element.path.endsWith(".aab")).toList());
    List<File> appbundles = [];

    if (distributionDirList.isEmpty) {
      Directory outputDir = Directory("build/app/outputs/bundle");
      final outputDirList = await outputDir.list().toList();
      for (var item in outputDirList) {
        if (item is Directory) {
          final files = await item.list().toList();
          final index = files.indexWhere((item) => item.path.endsWith(".aab"));
          if (index > -1) {
            final appbundle = files[index];
            if (appbundle is File) {
              ColorizeLogger.logInfo('Start distribute android 5');
              await appbundle.copy("distribution/android/output/${appbundle.path.split("/").last}");
              appbundles.add(File("distribution/android/output/${appbundle.path.split("/").last}"));
              ColorizeLogger.logDebug("${appbundles.length} copied to distribution/android/output");
            }
          }
        }
      }
    } else {
      appbundles = distributionDirList.map((e) => File(e.path)).toList();
    }

    ColorizeLogger.logDebug("${appbundles.length} appbundle(s) found, start distributing appbundle(s)...");

    for (var appbundle in appbundles) {
      ColorizeLogger.logInfo('Start distribute android $appbundle');
      await _distributeAppbundles(appbundle);
    }

    return 0;
  }

  /// Distributes the iOS app to the App Store using XCRun.
  Future<int> distributeIOS() async {
    if (!Platform.isMacOS) {
      ColorizeLogger.logError("Only MacOS can build iOS platform");
      return 1;
    }
    try {
      ColorizeLogger.logInfo('Start distribute iOS');
      final process = await Process.start('xcrun', [
        'altool',
        '--upload-app',
        '-f',
        'distribution/ios/output/*.ipa',
        '-u',
        environment.iosDistributionUser,
        '-p',
        environment.iosDistributionPassword,
        '--type',
        'iphoneos',
        '--show-progress',
      ]);
      if (environment.isVerbose) {
        process.stdout.transform(utf8.decoder).listen((data) {
          if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
        });
      }
      if (await process.exitCode != 0) {
        ColorizeLogger.logError("iOS Distribution Error");
        ColorizeLogger.logError(await process.stderr.transform(utf8.decoder).join("\n"));
      }
      return process.exitCode;
    } catch (e) {
      ColorizeLogger.logError("Error on distributeIOS\n$e");
      return 1;
    }
  }

  /// Distributes a single Android app bundle using Firebase or Fastlane.
  ///
  /// [file] The app bundle file to distribute.
  Future<int> _distributeAppbundles(File file) async {
    int output = 0;
    if (useFirebase) {
      try {
        ColorizeLogger.logInfo('Start distribute android (FIREBASE)');
        final process = await Process.start('firebase', [
          'appdistribution:distribute',
          file.path,
          '--app',
          environment.androidFirebaseAppId,
          '--groups',
          environment.androidFirebaseGroups,
        ]);
        if (environment.isVerbose) {
          process.stdout.transform(utf8.decoder).listen((data) {
            if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
          });
        }
        if (await process.exitCode != 0) {
          ColorizeLogger.logError("Android Distribution Error (FIREBASE)");
          ColorizeLogger.logError(await process.stderr.transform(utf8.decoder).join("\n"));
        }
        output = await process.exitCode;
      } catch (e) {
        ColorizeLogger.logError("Error on distributeAndroid (FIREBASE)\n$e");
      }
    }
    if (useFastlane) {
      ColorizeLogger.logInfo('Start distribute android (FASTLANE)');
      try {
        if (!(await File('distribution/fastlane.json').exists())) {
          ColorizeLogger.logError("distribution/fastlane.json is not exists, please follow the instructions to set this up");
          return 1;
        }
        final process = await Process.start('fastlane', [
          'run',
          'upload_to_play_store',
          'aab:${file.path}',
          'package_name:${environment.androidPackageName}',
          'json_key:distribution/fastlane.json',
          'metadata_path:distribution/android/metadata',
          "track:$fastlaneTrack",
          "track_promote_to:$fastlanePromoteTrackTo",
          if (argResults?['fastlane_args'] != null) ...argResults!['fastlane_args'].split(" ")
        ]);
        if (environment.isVerbose) {
          process.stdout.transform(utf8.decoder).listen((data) {
            if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
          });
        }
        if (await process.exitCode != 0) {
          ColorizeLogger.logError("Android Distribution Error (FASTLANE)");
          ColorizeLogger.logError(await process.stderr.transform(utf8.decoder).join("\n"));
        }
        output = await process.exitCode;
      } catch (e) {
        ColorizeLogger.logError("Error on distributeAndroid (FASTLANE)\n$e");
        return 1;
      }
    }
    return output;
  }

  @override

  /// Provides a description of the `publish` command.
  String get description => "Distribute the apps";

  @override

  /// The name of the `publish` command.
  String get name => "publish";

  @override

  /// Executes the `publish` command by initializing the environment and running the distribution tasks.
  Future? run() async {
    environment = Environment.fromArgResults(globalResults);
    isAndroidBuild = argResults?["android"] as bool;
    isIOSBuild = argResults?["ios"] as bool;
    useFirebase = argResults?["firebase"] as bool;
    useFastlane = argResults?["fastlane"] as bool;
    fastlaneTrack = argResults?["fastlane_track"] as String;
    fastlanePromoteTrackTo = argResults?["fastlane_promote_track_to"] as String;

    final android = argResults!['android'] as bool;
    final ios = argResults!['ios'] as bool;

    if (!await environment.initialized) {
      ColorizeLogger.logError("Please run distribute init first");
      exit(1);
    }

    if (!Platform.isMacOS && ios) {
      ColorizeLogger.logError("Only MacOS can build iOS platform");
    }
    if (android) {
      await buildAndroidDocs();
      await distributeAndroid().then((value) {
        if (value == 0) {
          ColorizeLogger.logSuccess("Android distribution success");
        }
      });
    }
    if (ios) {
      await distributeIOS().then((value) {
        if (value == 0) {
          ColorizeLogger.logSuccess("iOS distribution success");
        }
      });
    }
    return;
  }
}
