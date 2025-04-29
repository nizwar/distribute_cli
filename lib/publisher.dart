import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'environment.dart';
import 'files.dart';
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
    if (environment.distributionInitResult!.git) {
      await buildAndroidDocs();
    }
    if (isAndroidBuild) {
      return await distributeAndroid();
    } else if (isIOSBuild && environment.distributionInitResult!.xcrun) {
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
    final metadataDir = Files.androidDistributionMetadataDir;

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
    await Files.androidChangeLogs.writeAsString(log, encoding: utf8, flush: true, mode: FileMode.write);
    return 0;
  }

  /// Distributes the Android app bundles to the configured platforms.
  Future<int> distributeAndroid() async {
    if (!await Files.androidDistributionOutputDir.exists()) {
      await Files.androidDistributionOutputDir.create(recursive: true);
    }

    final distributionDirList = await Files.androidDistributionOutputDir.list().toList().then((value) => value.where((element) => element.path.endsWith(".aab")).toList());
    List<File> appbundles = [];

    if (distributionDirList.isEmpty) {
      Directory outputDir = Files.androidOutputAppbundles;
      final outputDirList = await outputDir.list().toList();
      for (var item in outputDirList) {
        if (item is Directory) {
          final files = await item.list().toList();
          final index = files.indexWhere((item) => item.path.endsWith(".aab"));
          if (index > -1) {
            final appbundle = files[index];
            if (appbundle is File) {
              ColorizeLogger.logInfo('Start distribute android 5');
              await appbundle.copy("${Files.androidDistributionOutputDir.path}/${appbundle.path.split("/").last}");
              appbundles.add(File("${Files.androidDistributionOutputDir.path}/${appbundle.path.split("/").last}"));
              ColorizeLogger.logDebug("${appbundles.length} copied to ${Files.androidDistributionOutputDir.path}");
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

    if (!await Files.iosDistributionOutputDir.exists()) {
      await Files.iosDistributionOutputDir.create(recursive: true);
    }

    final distributionDirList = await Files.iosDistributionOutputDir.list().toList().then((value) => value.where((element) => element.path.endsWith(".ipa")).toList());
    List<File> ipas = [];

    if (distributionDirList.isEmpty) {
      Directory outputDir = Files.iosOutputIPA;
      final outputDirList = await outputDir.list().toList();
      for (var item in outputDirList) {
        if (item is Directory) {
          final files = await item.list().toList();
          final index = files.indexWhere((item) => item.path.endsWith(".aab"));
          if (index > -1) {
            final appbundle = files[index];
            if (appbundle is File) {
              ColorizeLogger.logInfo('Start distribute android 5');
              await appbundle.copy("${Files.iosDistributionOutputDir.path}/${appbundle.path.split("/").last}");
              ipas.add(File("${Files.iosDistributionOutputDir.path}/${appbundle.path.split("/").last}"));
              ColorizeLogger.logDebug("${ipas.length} copied to ${Files.iosDistributionOutputDir.path}");
            }
          }
        }
      }
    } else {
      ipas = distributionDirList.map((e) => File(e.path)).toList();
    }
    for (var ipa in ipas) {
      ColorizeLogger.logInfo('Start distribute IPA $ipa');
      await _distributeIpa(ipa);
    }

    ColorizeLogger.logDebug("${ipas.length} ipa(s) found, start distributing ipa(s)...");
    return 0;
  }

  /// Distributes a single Android app bundle using Firebase or Fastlane.
  ///
  /// [file] The app bundle file to distribute.
  Future<int> _distributeAppbundles(File file) async {
    int output = 0;
    if (useFirebase && environment.distributionInitResult!.firebase) {
      try {
        ColorizeLogger.logInfo('Start distribute android (FIREBASE)');
        final process = await Process.start('firebase', [
          'appdistribution:distribute',
          file.path,
          '--app',
          environment.androidFirebaseAppId,
          '--groups',
          environment.androidFirebaseGroups,
          '--release-notes-file',
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
    if (useFastlane && environment.distributionInitResult!.fastlane && environment.distributionInitResult!.fastlaneJson) {
      ColorizeLogger.logInfo('Start distribute android (FASTLANE)');
      try {
        if (!(await Files.fastlaneJson.exists())) {
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

  Future<int> _distributeIpa(File file) async {
    try {
      ColorizeLogger.logInfo('Start distribute iOS');
      final process = await Process.start('xcrun', [
        'altool',
        '--upload-app',
        '-f',
        file.path,
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
