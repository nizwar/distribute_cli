import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'environment.dart';
import 'files.dart';
import 'logger.dart';

/// Handles app publishing for Android and iOS.
class Publisher extends Command {
  /// Environment configuration.
  late Environment environment;

  /// Logger for logging messages.
  late final ColorizeLogger logger;

  /// Enables Android distribution.
  bool isAndroidDistribute = false;

  /// Enables iOS distribution.
  bool isIOSDistribute = false;

  /// Uses Firebase for distribution.
  bool useFirebase = false;

  /// Uses Fastlane for distribution.
  bool useFastlane = false;

  /// Fastlane track for distribution.
  String fastlaneTrack = "internal";

  /// Fastlane track for promotion.
  String fastlanePromoteTrackTo = "production";

  /// Default constructor.
  Publisher();

  /// Creates a `Publisher` instance from command-line arguments.
  factory Publisher.fromArgResults(ArgResults? argResults) {
    final instance = Publisher();
    instance.environment = Environment.fromArgResults(argResults);
    instance.logger = ColorizeLogger(instance.environment);
    instance._initializeFlags();
    return instance;
  }

  /// Initializes flags from arguments or environment.
  void _initializeFlags() {
    isAndroidDistribute = argResults?["android"] ?? environment.isAndroidBuild;
    isIOSDistribute = argResults?["ios"] ?? environment.isIOSBuild;
    useFirebase = argResults?["firebase"] ?? environment.useFirebase;
    useFastlane = argResults?["fastlane"] ?? environment.useFastlane;
    fastlaneTrack =
        argResults?["fastlane_track"] ?? environment.androidPlaystoreTrack;
    fastlanePromoteTrackTo = argResults?["fastlane_promote_track_to"] ??
        environment.androidPlaystoreTrackPromoteTo;
  }

  /// Configures command-line arguments.
  @override
  ArgParser get argParser {
    environment = Environment.fromArgResults(argResults ?? globalResults);
    final argParser = ArgParser();
    argParser.addFlag("android",
        defaultsTo: environment.isAndroidBuild, help: "Build Android.");
    if (Platform.isMacOS) {
      argParser.addFlag("ios",
          defaultsTo: environment.isIOSBuild, help: "Build iOS.");
    }
    argParser.addFlag("firebase",
        defaultsTo: environment.useFirebase,
        help: "Use Firebase for distribution.");
    argParser.addFlag("fastlane",
        defaultsTo: environment.useFirebase,
        help: "Use Fastlane for distribution.");
    argParser.addOption("fastlane_track",
        defaultsTo: environment.androidPlaystoreTrack,
        help: "Playstore track for Android.");
    argParser.addOption("fastlane_args",
        defaultsTo: environment.androidPlaystoreTrack,
        help: "Playstore track for Android.");
    argParser.addOption("fastlane_promote_track_to",
        defaultsTo: environment.androidPlaystoreTrack,
        help: "Playstore track to promote to.");
    return argParser;
  }

  /// Command description.
  @override
  String get description => "Distribute the apps";

  /// Command name.
  @override
  String get name => "publish";

  /// Executes the publishing process.
  @override
  Future? run() async {
    environment = Environment.fromArgResults(globalResults);
    logger = ColorizeLogger(environment);
    _initializeFlags();

    if (!await environment.initialized) {
      logger.logError("Please run distribute init first.");
      exit(1);
    }

    if (!Platform.isMacOS && isIOSDistribute) {
      logger.logError("Only MacOS can build iOS platform.");
    }

    if (isAndroidDistribute) {
      await _executeTask(buildAndroidDocs, distributeAndroid, "Android");
    }
    if (isIOSDistribute) {
      await _executeTask(null, distributeIOS, "iOS");
    }
  }

  /// Executes a task with optional pre-task.
  Future<void> _executeTask(Future<int> Function()? preTask,
      Future<int> Function() task, String platform) async {
    if (preTask != null) await preTask();
    logger.logDebug("Start $platform distribution...");
    final result = await task();
    if (result == 0) {
      logger.logSuccess("[$platform] distribution success.");
    } else {
      logger.logError("[$platform] distribution failed.");
    }
  }

  /// Builds Android changelogs.
  Future<int> buildAndroidDocs() async {
    logger.logDebug("[ANDROID] Start building Android changelogs...");
    final docs = await Process.run(
        "git", ["log", "--pretty=format:%s", "--since=yesterday.midnight"]);
    if (docs.exitCode != 0) {
      logger.logError("[ANDROID] Failed to retrieve Git logs.");
      return 1;
    }
    final log = docs.stdout.toString().replaceAll("'", "");
    await Files.androidChangeLogs
        .writeAsString(log, encoding: utf8, flush: true);

    Files.androidDistributionMetadataDir.list().toList().then((value) {
      for (var dir in value) {
        if (dir is Directory) {
          File("${dir.path}/changelogs/default.txt")
              .writeAsString(log, encoding: utf8, flush: true)
              .then((value) {
            logger.logDebug(
                "[ANDROID] Changelogs written to ${dir.path}/changelogs/default.txt");
          }).catchError((error) {
            logger.logError(
                "[ANDROID] Failed to write changelogs to ${dir.path}/changelogs/default.txt");
          });
        }
      }
    });
    return 0;
  }

  /// Distributes Android binaries.
  Future<int> distributeAndroid() async {
    final binaries = await _collectBinaries(
        Files.androidDistributionOutputDir, ["aab", "apk"]);
    if (binaries.isEmpty) {
      logger.logError(
          "[ANDROID] No Android binaries found in ${Files.androidDistributionOutputDir.path}");
      return 1;
    }
    for (var binary in binaries) {
      logger.logInfo('[ANDROID] Distributing Android binary: $binary');
      await _distributeBinary(binary, _distributeAndroidBinary);
    }
    return 0;
  }

  /// Distributes iOS binaries.
  Future<int> distributeIOS() async {
    if (!Platform.isMacOS) {
      logger.logError("[iOS] iOS distribution is only supported on macOS.");
      return 1;
    }
    final binaries =
        await _collectBinaries(Files.iosDistributionOutputDir, ["ipa"]);
    if (binaries.isEmpty) {
      logger.logError(
          "[iOS] No iOS binaries found in ${Files.iosDistributionOutputDir.path}");
      return 1;
    }
    for (var binary in binaries) {
      logger.logInfo('[iOS] Initiating distribution for iOS binary: $binary');
      await _distributeBinary(binary, _distributeIosBinary).then((value) {});
    }
    return 0;
  }

  /// Collects binaries from the specified directory.
  Future<List<File>> _collectBinaries(
      Directory outputDir, List<String> extensions) async {
    if (!await outputDir.exists()) await outputDir.create(recursive: true);
    final files = await outputDir.list().toList();
    return files
        .where((file) => extensions.any((ext) => file.path.endsWith(ext)))
        .map((item) => File(item.path))
        .toList();
  }

  /// Distributes a binary using the specified function.
  Future<void> _distributeBinary(
      File file, Future<int> Function(File) distributeFunction) async {
    final result = await distributeFunction(file);
    if (result != 0) {
      logger.logError("Distribution failed for file: ${file.path}");
    }
  }

  /// Distributes an Android binary.
  Future<int> _distributeAndroidBinary(File file) async {
    int output = 0;
    List<Future<(String, int)>> tasks = [];
    if (useFirebase && environment.distributionInitResult!.firebase) {
      logger.logDebug("Distributing Android binary using Firebase");
      tasks.add(
        _runProcess(
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
          "Android Distribution (FIREBASE)",
          "ANDROID (Firebase)",
        ).then((value) => ("Firebase", value)),
      );
    }
    if (useFastlane &&
        environment.distributionInitResult!.fastlane &&
        environment.distributionInitResult!.fastlaneJson) {
      logger.logDebug("Distributing Android binary using Fastlane");
      tasks.add(
        _runProcess(
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
            if (argResults?['fastlane_args'] != null)
              ...argResults!['fastlane_args'].split(" "),
          ],
          "Android Distribution (FASTLANE)",
          "ANDROID (Fastlane)",
        ).then((value) => ("Fastlane", value)),
      );
    }
    if (tasks.isEmpty) {
      logger.logError("No distribution method selected for Android.");
      return 1;
    }

    await Future.wait(tasks).then((results) {
      for (var result in results) {
        if (result.$2 != 0) {
          logger.logError("[${result.$1}] Android distribution failed.");
          output = 1;
        }
      }
    });
    return output;
  }

  /// Distributes an iOS binary.
  Future<int> _distributeIosBinary(File file) async {
    logger.logDebug("Distributing iOS binary using xcrun");
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
        "iOS Distribution",
        "iOS");
  }

  /// Runs a process with the specified arguments.
  Future<int> _runProcess(String executable, List<String> arguments,
      String taskName, String platform) async {
    try {
      final process = await Process.start(executable, arguments);
      process.stdout
          .transform(utf8.decoder)
          .listen((data) => logger.logDebug("[$platform] ${data.trim()}"));

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        logger.logError("[$platform] $taskName encountered an issue.");
        logger
            .logError(await process.stderr.transform(utf8.decoder).join("\n"));
      }
      logger.logSuccess(
          "[$platform] $taskName completed successfully with exit code $exitCode.");
      return exitCode;
    } catch (e) {
      logger.logError("[$platform] An exception occurred during $taskName: $e");
      return 1;
    }
  }
}
