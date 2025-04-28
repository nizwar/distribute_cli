import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'environment.dart';
import 'logger.dart'; 

class Publisher extends Command {
  final Environment environment;

  Publisher(this.environment);

  @override
  ArgParser get argParser => ArgParser()
    ..addFlag("android", defaultsTo: environment.isAndroidDistribute, help: "Build and distribute Android")
    ..addFlag("ios", defaultsTo: environment.isIOSDistribute, help: "Build and distribute iOS")
    ..addFlag("firebase", defaultsTo: environment.useFirebase, help: "Use Firebase for distribution")
    ..addFlag("fastlane", defaultsTo: environment.useFastlane, help: "Use Fastlane for distribution");

  bool get isAndroidBuild => argResults?['android'] as bool? ?? false;
  bool get isIOSBuild => argResults?['ios'] as bool? ?? false;
  bool get useFirebase => argResults?['firebase'] as bool? ?? false;
  bool get useFastlane => argResults?['fastlane'] as bool? ?? false;

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

  Future<int> distributeAndroid() async {
    Directory distributionDir = Directory("distribution/android/output");
    if (!await distributionDir.exists()) {
      await distributionDir.create(recursive: true);
    }
    final distributionDirList = await distributionDir.list().toList();

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
              await appbundle.copy("distribution/android/output/${appbundle.path.split("/").last}");
              appbundles.add(File("distribution/android/output/${appbundle.path.split("/").last}"));
              ColorizeLogger.logDebug("${appbundles.length} copied to distribution/android/output");
            }
          }
        }
      }
    }

    ColorizeLogger.logDebug("${appbundles.length} appbundle(s) found, start distributing appbundle(s)...");

    for (var appbundle in appbundles) {
      await _distributeAppbundles(appbundle);
    }

    return 0;
  }

  Future<int> distributeIOS() async {
    if (!Platform.isMacOS) {
      ColorizeLogger.logError("Only MacOS can build iOS platform");
      return 1;
    }
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
      stdout.writeln(await process.stderr.transform(utf8.decoder).join("\n"));
    }
    return process.exitCode;
  }

  Future<int> _distributeAppbundles(File file) async {
    int output = 0;
    if (useFirebase) {
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
        stdout.writeln(await process.stderr.transform(utf8.decoder).join("\n"));
      }
      output = await process.exitCode;
    }
    if (useFastlane) {
      ColorizeLogger.logInfo('Start distribute android (FASTLANE)');
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
      ]);
      if (environment.isVerbose) {
        process.stdout.transform(utf8.decoder).listen((data) {
          if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
        });
      }
      if (await process.exitCode != 0) {
        ColorizeLogger.logError("Android Distribution Error (FASTLANE)");
        stdout.writeln(await process.stderr.transform(utf8.decoder).join("\n"));
      }
      output = await process.exitCode;
    }
    return output;
  }

  @override
  String get description => "Distribute the apps";

  @override
  String get name => "publish";

  @override
  Future? run() async {
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
      await distributeAndroid();
    }

    if (ios) {
      await distributeIOS();
    }
    return;
  }
}
