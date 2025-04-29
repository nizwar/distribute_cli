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
  late Environment environment;

  /// Distribution flags and configurations.
  bool isAndroidDistribute = false;
  bool isIOSDistribute = false;
  bool useFirebase = false;
  bool useFastlane = false;
  String fastlaneTrack = "internal";
  String fastlanePromoteTrackTo = "production";

  Publisher();

  factory Publisher.fromArgResults(ArgResults? argResults) {
    final instance = Publisher();
    instance.environment = Environment.fromArgResults(argResults);
    instance._initializeFlags();
    return instance;
  }

  void _initializeFlags() {
    isAndroidDistribute = argResults?["android"] ?? environment.isAndroidBuild;
    isIOSDistribute = argResults?["ios"] ?? environment.isIOSBuild;
    useFirebase = argResults?["firebase"] ?? environment.useFirebase;
    useFastlane = argResults?["fastlane"] ?? environment.useFastlane;
    fastlaneTrack = argResults?["fastlane_track"] ?? environment.androidPlaystoreTrack;
    fastlanePromoteTrackTo = argResults?["fastlane_promote_track_to"] ?? environment.androidPlaystoreTrackPromoteTo;
  }

  @override
  ArgParser get argParser {
    environment = Environment.fromArgResults(argResults ?? globalResults);
    return ArgParser()
      ..addFlag("android", defaultsTo: environment.isAndroidDistribute, help: "Build and distribute Android.")
      ..addFlag("ios", defaultsTo: Platform.isMacOS ? environment.isIOSDistribute : false, help: "Build and distribute iOS.")
      ..addOption("fastlane_track", defaultsTo: environment.androidPlaystoreTrack, help: "Playstore track for Android.")
      ..addOption("fastlane_promote_track_to", defaultsTo: environment.androidPlaystoreTrackPromoteTo, help: "Playstore track to promote to.")
      ..addOption("fastlane_args", help: "Arguments for Fastlane.")
      ..addFlag("firebase", defaultsTo: environment.useFirebase, help: "Use Firebase for distribution.")
      ..addFlag("fastlane", defaultsTo: environment.useFastlane, help: "Use Fastlane for distribution.");
  }

  @override
  String get description => "Distribute the apps";

  @override
  String get name => "publish";

  @override
  Future? run() async {
    environment = Environment.fromArgResults(globalResults);
    _initializeFlags();

    if (!await environment.initialized) {
      ColorizeLogger.logError("Please run distribute init first.");
      exit(1);
    }

    if (!Platform.isMacOS && isIOSDistribute) {
      ColorizeLogger.logError("Only MacOS can build iOS platform.");
    }

    if (isAndroidDistribute) {
      await _executeTask(buildAndroidDocs, distributeAndroid, "Android");
    }
    if (isIOSDistribute) {
      await _executeTask(null, distributeIOS, "iOS");
    }
  }

  Future<void> _executeTask(Future<int> Function()? preTask, Future<int> Function() task, String platform) async {
    if (preTask != null) await preTask();
    ColorizeLogger.logDebug("Start $platform distribution...");
    final result = await task();
    if (result == 0) {
      ColorizeLogger.logSuccess("$platform distribution success.");
    } else {
      ColorizeLogger.logError("$platform distribution failed.");
    }
  }

  Future<int> buildAndroidDocs() async {
    final docs = await Process.run("git", ["log", "--pretty=format:%s", "--since=yesterday.midnight"]);
    if (docs.exitCode != 0) {
      ColorizeLogger.logError("[ERROR] Failed to retrieve Git logs.");
      return 1;
    }
    final log = docs.stdout.toString().replaceAll("'", "");
    await Files.androidChangeLogs.writeAsString(log, encoding: utf8, flush: true);
    return 0;
  }

  Future<int> distributeAndroid() async {
    final binaries = await _collectBinaries(Files.androidDistributionOutputDir, ["aab", "apk"]);
    for (var binary in binaries) {
      ColorizeLogger.logInfo('Initiating distribution for Android binary: $binary');
      await _distributeBinary(binary, _distributeAndroidBinary);
    }
    return 0;
  }

  Future<int> distributeIOS() async {
    if (!Platform.isMacOS) {
      ColorizeLogger.logError("[ERROR] iOS distribution is only supported on macOS.");
      return 1;
    }
    final binaries = await _collectBinaries(Files.iosDistributionOutputDir, ["ipa"]);
    for (var binary in binaries) {
      ColorizeLogger.logInfo('Initiating distribution for iOS binary: $binary');
      await _distributeBinary(binary, _distributeIosBinary).then((value) {});
    }
    return 0;
  }

  Future<List<File>> _collectBinaries(Directory outputDir, List<String> extensions) async {
    if (!await outputDir.exists()) await outputDir.create(recursive: true);
    final files = await outputDir.list().toList();
    return files.where((file) => extensions.any((ext) => file.path.endsWith(ext))).map((item) => File(item.path)).toList();
  }

  Future<void> _distributeBinary(File file, Future<int> Function(File) distributeFunction) async {
    final result = await distributeFunction(file);
    if (result != 0) {
      ColorizeLogger.logError("[ERROR] Distribution failed for file: ${file.path}");
    }
  }

  Future<int> _distributeAndroidBinary(File file) async {
    int output = 0;
    if (useFirebase && environment.distributionInitResult!.firebase) {
      output = await _runProcess(
          'firebase',
          [
            'appdistribution:distribute',
            file.path,
            '--app',
            environment.androidFirebaseAppId,
            '--groups',
            environment.androidFirebaseGroups,
            '--release-notes-file',
            Files.androidChangeLogs.path,
          ],
          "Android Distribution (FIREBASE)");
    }
    if (useFastlane && environment.distributionInitResult!.fastlane && environment.distributionInitResult!.fastlaneJson) {
      output = await _runProcess(
          'fastlane',
          [
            'run',
            'upload_to_play_store',
            'aab:${file.path}',
            'package_name:${environment.androidPackageName}',
            'json_key:${Files.fastlaneJson.path}',
            'metadata_path:${Files.androidDistributionMetadataDir.path}',
            "track:$fastlaneTrack",
            "track_promote_to:$fastlanePromoteTrackTo",
            if (argResults?['fastlane_args'] != null) ...argResults!['fastlane_args'].split(" "),
          ],
          "Android Distribution (FASTLANE)");
    }
    return output;
  }

  Future<int> _distributeIosBinary(File file) async {
    return await _runProcess(
        'xcrun',
        [
          'altool',
          '--upload-app',
          '-f',
          (file.path),
          '-u',
          (environment.iosDistributionUser),
          '-p',
          (environment.iosDistributionPassword),
          '--type',
          'iphoneos',
          '--show-progress',
        ],
        "iOS Distribution");
  }

  Future<int> _runProcess(String executable, List<String> arguments, String taskName) async {
    try {
      final process = await Process.start(executable, arguments);
      if (environment.isVerbose) {
        process.stdout.transform(utf8.decoder).listen((data) => ColorizeLogger.logDebug(data.trim()));
      }
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        ColorizeLogger.logError("[ERROR] $taskName encountered an issue.");
        ColorizeLogger.logError(await process.stderr.transform(utf8.decoder).join("\n"));
      }
      ColorizeLogger.logSuccess("[SUCCESS] $taskName completed successfully with exit code $exitCode.");
      return exitCode;
    } catch (e) {
      ColorizeLogger.logError("[ERROR] An exception occurred during $taskName: $e");
      return 1;
    }
  }
}
