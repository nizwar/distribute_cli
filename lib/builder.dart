import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'environment.dart';

import 'logger.dart';
import 'publisher.dart';

class Builder extends Command {
  late final Publisher publisher;
  late Environment environment;

  bool get buildAndroid => argResults?['android'] as bool? ?? true;
  bool get buildIOS => argResults?['ios'] as bool? ?? false;
  bool get publish => argResults?['publish'] as bool? ?? false;

  @override
  ArgParser get argParser {
    environment = Environment.fromArgResults(globalResults);
    return ArgParser()
      ..addFlag("publish",
          abbr: "p", defaultsTo: false, help: "Distribute Android")
      ..addFlag("android",
          defaultsTo: environment.isAndroidBuild, help: "Build Android")
      ..addFlag("ios",
          defaultsTo: Platform.isMacOS ? environment.isIOSBuild : false,
          help: "Build iOS")
      ..addOption("android_args",
          defaultsTo: "", help: "Arguments for Android build.")
      ..addOption("ios_args", defaultsTo: "", help: "Arguments for iOS build.")
      ..addOption(
        'custom_args',
        defaultsTo: "",
        help:
            "Custom arguments key:args,key:args, it will executed as `flutter build <args>`",
        valueHelp: "macos:macos,windows:windows,ios:ipa,android_apk:apk",
      );
  }

  @override
  String get description => "Build the apps";

  @override
  String get name => "build";

  @override
  Future run() async {
    environment = Environment.fromArgResults(globalResults);
    final androidArgs = argResults!['android_args'] as String;
    final iosArgs = argResults!['ios_args'] as String;
    final customArgs = argResults!['custom_args'] as String;
    final customBuildArgs = <String, List<String>>{};

    if (!await environment.initialized) {
      ColorizeLogger.logError(
          "Please run distribute init first ${await environment.initialized}");
      exit(1);
    }

    if (customArgs.isNotEmpty) {
      final args = customArgs.split(',');
      for (var arg in args) {
        final keyValue = arg.split(':');
        if (keyValue.length == 2) {
          final key = keyValue[0];
          final value = keyValue[1].split(',');
          customBuildArgs[key] = value;
        } else {
          ColorizeLogger.logError('Invalid custom argument format: $arg');
        }
      }
    }
    if (androidArgs.isNotEmpty)
      customBuildArgs['android'] = androidArgs.split(',');
    if (iosArgs.isNotEmpty) customBuildArgs['ios'] = iosArgs.split(',');

    return build(
            androidArgs: customBuildArgs['android'] ?? [],
            iosArgs: customBuildArgs['ios'] ?? [],
            customBuildArgs: customBuildArgs)
        .then((value) {
      if (value != 0) {
        ColorizeLogger.logError('Build failed.');
        exit(1);
      } else {
        ColorizeLogger.logSuccess('Build completed successfully.');
      }
    }).catchError((e) {
      ColorizeLogger.logError('An error occurred: $e');
      exit(1);
    }).whenComplete(() {
      ColorizeLogger.logSuccess('Process completed.');
    });
  }

  Future<int> build(
      {List<String> androidArgs = const [],
      List<String> iosArgs = const [],
      Map<String, List<String>>? customBuildArgs}) async {
    customBuildArgs ??= {};
    int exitCode = 0;

    if (buildAndroid) customBuildArgs['android'] = androidArgs;
    if (buildIOS) customBuildArgs['ios'] = iosArgs;

    List<(String, int)> buildResults = [];

    for (final entry in customBuildArgs.entries) {
      final platform = entry.key;
      final args = entry.value;
      if (platform == 'android') {
        buildResults.add(await _buildAndroid(args: args).then((value) {
          if (value == 0) {
            ColorizeLogger.logInfo('Android build success.');
          } else {
            ColorizeLogger.logError('Android build failed.');
          }
          return (platform, value);
        }).catchError((e) => (platform, 1)));
      } else if (platform == 'ios') {
        buildResults.add(await _buildIOS(args: args).then((value) {
          if (value == 0) {
            ColorizeLogger.logInfo('iOS build success.');
          } else {
            ColorizeLogger.logError('iOS build failed.');
          }
          return (platform, value);
        }).catchError((e) => (platform, 1)));
      } else {
        buildResults.add(await _buildCustom(platform, args).then((value) {
          if (value == 0) {
            ColorizeLogger.logInfo('$platform build success.');
          } else {
            ColorizeLogger.logError('$platform build failed.');
          }
          return (platform, value);
        }).catchError((e) => (platform, 1)));
      }
    }

    if (publish) {
      List<(String, int)> distributionResults = [];
      for (var buildResult in buildResults) {
        if (buildAndroid &&
            buildResult.$1 == "android" &&
            buildResult.$2 == 0) {
          publisher.buildAndroidDocs();
          distributionResults.add(await publisher
              .distributeAndroid()
              .then((value) => (buildResult.$1, value))
              .catchError((e) => (buildResult.$1, 1)));
        }
        if (buildIOS && buildResult.$1 == "ios" && buildResult.$2 == 0) {
          distributionResults.add(await publisher
              .distributeIOS()
              .then((value) => (buildResult.$1, value))
              .catchError((e) => (buildResult.$1, 1)));
        }
      }

      if (distributionResults.isNotEmpty) {
        for (var result in distributionResults) {
          if (result.$2 != 0) {
            ColorizeLogger.logError('Distribution failed for ${result.$1}.');
            exitCode = 1;
          } else {
            ColorizeLogger.logSuccess(
                'Distribution completed successfully for ${result.$1}.');
          }
        }
      } else {
        ColorizeLogger.logDebug('No distribution tasks to execute.');
      }
    }

    exit(exitCode);
  }

  Future<int> _buildAndroid({final List<String>? args}) async {
    if (buildAndroid) {
      ColorizeLogger.logDebug('Start android build...');
      final process = await Process.start(
          'flutter', ['build', 'aab', if (args != null) ...args]);
      if (environment.isVerbose) {
        process.stdout.transform(utf8.decoder).listen((data) {
          if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
        });
      }
      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        return await _moveAndroidBinaries();
      }
      return exitCode;
    }
    return 0;
  }

  Future<int> _buildIOS({final List<String>? args}) async {
    if (buildIOS) {
      final process = await Process.start(
          'flutter', ['build', 'ipa', if (args != null) ...args]);
      ColorizeLogger.logDebug('Start ios build...');
      if (environment.isVerbose) {
        process.stdout.transform(utf8.decoder).listen((data) {
          if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
        });
      }
      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        return await _moveIOSBinaries();
      }
      return exitCode;
    }
    return 0;
  }

  Future<int> _buildCustom(String key, List<String> args) async {
    ColorizeLogger.logInfo('Start $key build...');
    final process = await Process.start('flutter', ['build', ...args]);
    if (environment.isVerbose) {
      process.stdout.transform(utf8.decoder).listen((data) {
        if (data.trim().isNotEmpty) ColorizeLogger.logDebug(data);
      });
    }
    return process.exitCode;
  }

  Future<int> _moveAndroidBinaries() async {
    if (buildAndroid) {
      Directory distributionDir = Directory("distribution/android/output");
      if (await distributionDir.exists()) {
        await distributionDir.delete(recursive: true);
      }
      await distributionDir.create(recursive: true);
      final distributionDirList = await distributionDir.list().toList();
      List<File> appbundles = [];

      if (distributionDirList.isEmpty) {
        Directory outputDir = Directory("build/app/outputs/bundle");
        if (!await outputDir.exists()) {
          ColorizeLogger.logError(
              'No appbundle found in build/app/outputs/bundle');
          return 1;
        }
        final outputDirList = await outputDir.list().toList();

        for (var item in outputDirList) {
          if (item is Directory) {
            final files = await item.list().toList();
            final index =
                files.indexWhere((item) => item.path.endsWith(".aab"));
            if (index > -1) {
              final appbundle = files[index];
              if (appbundle is File) {
                await appbundle.copy(
                    "distribution/android/output/${appbundle.path.split("/").last}");
                appbundles.add(File(
                    "distribution/android/output/${appbundle.path.split("/").last}"));
                ColorizeLogger.logDebug(
                    "${appbundles.length} copied to distribution/android/output");
              }
            }
          }
        }
      }
    }

    return 0;
  }

  Future<int> _moveIOSBinaries() async {
    if (buildIOS) {
      Directory distributionDir = Directory("distribution/ios/output");
      if (await distributionDir.exists()) {
        await distributionDir.delete(recursive: true);
      }
      await distributionDir.create(recursive: true);

      final distributionDirList = await distributionDir.list().toList();
      List<File> ipas = [];

      if (distributionDirList.isEmpty) {
        Directory outputDir = Directory("build/ios/ipa");
        final outputDirList = await outputDir.list().toList();
        if (!await outputDir.exists()) {
          ColorizeLogger.logError('No ipa found in build/ios/ipa');
          return 1;
        }

        for (var item in outputDirList) {
          if (item is Directory) {
            final files = await item.list().toList();
            final index =
                files.indexWhere((item) => item.path.endsWith(".ipa"));
            if (index > -1) {
              final ipa = files[index];
              if (ipa is File) {
                await ipa.copy(
                    "distribution/ios/output/${ipa.path.split("/").last}");
                ipas.add(File(
                    "distribution/ios/output/${ipa.path.split("/").last}"));
                ColorizeLogger.logDebug(
                    "${ipas.length} copied to distribution/ios/output");
              }
            }
          }
        }
      }
    }

    return 0;
  }
}
