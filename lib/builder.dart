import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'environment.dart';

import 'files.dart';
import 'logger.dart';
import 'publisher.dart';

/// A command to build and optionally distribute the app.
///
/// The `Builder` class provides functionality to build Android and iOS apps,
/// as well as custom platforms. It also supports optional distribution of the
/// built apps using the `Publisher` class.
///
/// To use this class, invoke the `build` command with the desired flags:
/// ```
/// distribute build --android --publish
/// ```
class Builder extends Command {
  /// The publisher instance for distributing the app.
  late final Publisher publisher;
  late final ColorizeLogger logger;

  /// The environment configuration for the build process.
  late Environment environment;

  /// Checks if the Android build flag is enabled.
  bool get buildAndroid => argResults?['android'] as bool? ?? true;

  /// Checks if the iOS build flag is enabled.
  bool get buildIOS => argResults?['ios'] as bool? ?? false;

  /// Checks if the publish flag is enabled.
  bool get publish => argResults?['publish'] as bool? ?? false;

  String get androidBinary => argResults?['android_binary'] as String? ?? "aab";

  @override

  /// Configures the argument parser for the `build` command.
  ArgParser get argParser {
    environment = Environment.fromArgResults(globalResults);
    return ArgParser()
      ..addFlag("publish",
          abbr: "p", defaultsTo: false, help: "Distribute Android")
      ..addFlag(
        "android",
        defaultsTo: environment.isAndroidBuild,
        help: "Build Android (Default value follows the config file)",
      )
      ..addFlag(
        "ios",
        defaultsTo: Platform.isMacOS ? environment.isIOSBuild : false,
        help: "Build iOS (Default value follows the config file)",
      )
      ..addOption("android_binary",
          defaultsTo: environment.androidBinary,
          help: "Arguments for Android build.")
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

  /// Provides a description of the `build` command.
  String get description => "Build the apps";

  @override

  /// The name of the `build` command.
  String get name => "build";

  @override

  /// Executes the `build` command to build and optionally distribute the app.
  Future run() async {
    environment = Environment.fromArgResults(globalResults);
    publisher = Publisher.fromArgResults(globalResults);
    logger = ColorizeLogger(environment);

    final customBuildArgs = _parseCustomArgs();
    if (!await environment.initialized) {
      logger.logError("Please run distribute init first");
      exit(1);
    }

    return _executeBuild(customBuildArgs).then((value) {
      if (value != 0) {
        logger.logError('Build failed.');
        exit(1);
      } else {
        logger.logSuccess('Build completed successfully.');
      }
    }).catchError((e) {
      logger.logError('An error occurred: $e');
      exit(1);
    }).whenComplete(() {
      logger.logSuccess('Process completed.');
    });
  }

  /// Parses custom build arguments from the command-line input.
  ///
  /// This method processes the `custom_args`, `android_args`, and `ios_args`
  /// options provided via the command-line and organizes them into a map
  /// where the keys are platform names and the values are lists of arguments.
  Map<String, List<String>> _parseCustomArgs() {
    final customArgs = argResults!['custom_args'] as String;
    final androidArgs = argResults!['android_args'] as String;
    final iosArgs = argResults!['ios_args'] as String;

    final customBuildArgs = <String, List<String>>{"android": [], "ios": []};
    if (customArgs.isNotEmpty) {
      for (var arg in customArgs.split(',')) {
        final keyValue = arg.split(':');
        if (keyValue.length == 2) {
          customBuildArgs[keyValue[0]] = keyValue[1].split(' ');
        } else {
          logger.logError('Invalid custom argument format: $arg');
        }
      }
    }
    if (androidArgs.isNotEmpty) {
      customBuildArgs['android'] = androidArgs.split(',');
    }
    if (iosArgs.isNotEmpty) customBuildArgs['ios'] = iosArgs.split(',');

    return customBuildArgs;
  }

  /// Executes the build process for the specified platforms and arguments.
  ///
  /// This method iterates over the provided `customBuildArgs` map and invokes
  /// the appropriate build method for each platform. It also handles the
  /// optional distribution process if the `publish` flag is enabled.
  Future<int> _executeBuild(Map<String, List<String>> customBuildArgs) async {
    int exitCode = 0;
    final buildResults =
        await Future.wait(customBuildArgs.entries.map((entry) async {
      final platform = entry.key;
      final args = entry.value;
      return await _buildPlatform(platform, args);
    }));

    exitCode = buildResults.fold(0, (prev, element) => prev + element.$2);

    return exitCode;
  }

  /// Builds the specified platform with the provided arguments.
  ///
  /// This method determines the appropriate build method to invoke based on
  /// the platform name (e.g., `android`, `ios`, or custom platforms).
  Future<(String, int)> _buildPlatform(
      String platform, List<String> args) async {
    try {
      if (platform == 'android') {
        return (
          platform,
          await _buildAndroid(args: args).then((value) async {
            if (value == 0) {
              if (publish && buildAndroid && environment.isAndroidDistribute) {
                if (environment.distributionInitResult?.git ?? false) {
                  await publisher.buildAndroidDocs();
                }

                return publisher.distributeAndroid();
              }
            }

            return value;
          })
        );
      } else if (platform == 'ios') {
        return (
          platform,
          await _buildIOS(args: args).then((value) async {
            if (value == 0) {
              if (publish && buildIOS && environment.isIOSDistribute) {
                return publisher.distributeIOS();
              }
            }
            return value;
          })
        );
      } else {
        return (platform, await _buildCustom(platform, args));
      }
    } catch (e) {
      logger.logError('An error occurred during $platform build: $e');
      return (platform, 1);
    }
  }

  /// Builds the app for the specified platforms and arguments.
  Future<int> build({
    List<String> androidArgs = const [],
    List<String> iosArgs = const [],
    Map<String, List<String>>? customBuildArgs,
  }) async {
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
            logger.logInfo('Android build success.');
          } else {
            logger.logError('Android build failed.');
          }
          return (platform, value);
        }).catchError((e) {
          logger.logError('An error occurred: $e');
          return (platform, 1);
        }));
      } else if (platform == 'ios') {
        buildResults.add(await _buildIOS(args: args).then((value) {
          if (value == 0) {
            logger.logInfo('iOS build success.');
          } else {
            logger.logError('iOS build failed.');
          }
          return (platform, value);
        }).catchError((e) => (platform, 1)));
      } else {
        buildResults.add(await _buildCustom(platform, args).then((value) {
          if (value == 0) {
            logger.logInfo('$platform build success.');
          } else {
            logger.logError('$platform build failed.');
          }
          return (platform, value);
        }).catchError((e) => (platform, 1)));
      }
    }

    if (publish) {
      List<(String, int)> distributionResults = [];
      for (var buildResult in buildResults) {
        stdout.writeln("Build result ${buildResult.$1} ${buildResult.$2}");
        if (buildAndroid &&
            buildResult.$1 == "android" &&
            buildResult.$2 == 0) {
          if (environment.distributionInitResult!.git) {
            await publisher.buildAndroidDocs();
          }
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
            logger.logError('Distribution failed for ${result.$1}.');
            exitCode = 1;
          } else {
            logger.logSuccess(
                'Distribution completed successfully for ${result.$1}.');
          }
        }
      } else {
        logger.logInfo('No distribution tasks to execute.');
      }
    }

    exit(exitCode);
  }

  /// Builds the Android app with the specified [args].
  Future<int> _buildAndroid({final List<String>? args}) async {
    if (buildAndroid) {
      logger.logInfo('Starting Android build process...');
      final process = await Process.start(
          'flutter', ['build', androidBinary, if (args != null) ...args]);

      process.stdout.transform(utf8.decoder).listen((data) {
        if (data.trim().isNotEmpty) logger.logDebug("[Android] $data");
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        logger.logSuccess('Android build completed successfully.');
        return await _moveAndroidBinaries();
      } else {
        logger.logError(await process.stderr.join("\n"));
      }
      return exitCode;
    }
    return 0;
  }

  /// Builds the iOS app with the specified [args].
  Future<int> _buildIOS({final List<String>? args}) async {
    if (buildIOS) {
      logger.logInfo('Starting iOS build process...');
      final process = await Process.start(
          'flutter', ['build', 'ipa', if (args != null) ...args]);

      process.stdout.transform(utf8.decoder).listen((data) {
        if (data.trim().isNotEmpty) logger.logDebug("[iOS] $data");
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        logger.logSuccess('iOS build completed successfully.');
        return await _moveIOSBinaries();
      } else {
        logger.logError(await process.stderr.join("\n"));
      }
      return exitCode;
    }
    return 0;
  }

  /// Builds a custom platform with the specified [key] and [args].
  Future<int> _buildCustom(String key, List<String> args) async {
    logger.logInfo('Start $key build...');
    final process = await Process.start('flutter', ['build', ...args]);

    process.stdout.transform(utf8.decoder).listen((data) {
      if (data.trim().isNotEmpty) logger.logDebug("[$key] $data");
    });

    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      logger.logSuccess('[$key] Build completed successfully.');
    } else {
      logger.logError(await process.stderr.transform(utf8.decoder).join("\n"));
    }
    return exitCode;
  }

  /// Moves the Android binaries to the distribution directory.
  Future<int> _moveAndroidBinaries() async {
    if (!buildAndroid) return 0;

    logger.logDebug('Moving Android binaries to the distribution directory...');
    final isAppBundle = androidBinary == "appbundle" || androidBinary == "aab";
    final outputDir =
        isAppBundle ? Files.androidOutputAppbundles : Files.androidOutputApks;
    final extension = isAppBundle ? ".aab" : ".apk";

    if (!await outputDir.exists()) {
      logger.logError('No binaries found in ${outputDir.path}');
      return 1;
    }

    final distributionDir = Files.androidDistributionOutputDir;
    if (await distributionDir.exists()) {
      await distributionDir.delete(recursive: true);
    }
    await distributionDir.create(recursive: true);

    final files = await outputDir
        .list(recursive: true)
        .where((item) => item.path.endsWith(extension))
        .toList();
    for (var file in files.whereType<File>()) {
      await file.copy("${distributionDir.path}/${file.uri.pathSegments.last}");
    }

    logger.logDebug("${files.length} files copied to ${distributionDir.path}");
    return 0;
  }

  /// Moves the iOS binaries to the distribution directory.
  Future<int> _moveIOSBinaries() async {
    if (!buildIOS) return 0;

    logger.logDebug('Moving iOS binaries to the distribution directory...');
    final distributionDir = Files.iosDistributionOutputDir;
    if (await distributionDir.exists()) {
      await distributionDir.delete(recursive: true);
    }
    await distributionDir.create(recursive: true);

    final outputDir = Files.iosOutputIPA;
    if (!await outputDir.exists()) {
      logger.logError('No ipa found in build/ios/ipa');
      return 1;
    }

    final ipas = await outputDir
        .list(recursive: true)
        .where((item) => item.path.endsWith(".ipa"))
        .cast<File>()
        .toList();

    for (var ipa in ipas) {
      await ipa.copy("${distributionDir.path}/${ipa.uri.pathSegments.last}");
    }

    logger.logDebug("${ipas.length} files copied to ${distributionDir.path}");
    return 0;
  }
}
