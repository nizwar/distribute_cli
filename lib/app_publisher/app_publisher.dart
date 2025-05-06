import 'dart:convert';
import 'dart:io';

import 'package:distribute_cli/app_publisher/fastlane/fastlane_android_publisher_arguments.dart';
import 'package:distribute_cli/app_publisher/firebase/firebase_android_publisher_arguments.dart';
import 'package:distribute_cli/files.dart';

import '../logger.dart';
import '../parsers/job_arguments.dart';
import 'xcrun/xcrun_ios_publisher_arguments.dart';

/// Base class for all app publishers
///
/// This class is used to upload the app to a specific platform.
/// The class is generic and takes a type parameter `T` which extends `AppPublisherArgument`.
/// This allows for different types of arguments to be passed to the publisher.
class AppPublisher<T extends PublisherArguments> {
  /// The arguments to pass to the publisher
  final T args;

  /// Constructor for the app publisher
  AppPublisher(this.args);

  /// The uploader command to use

  /// Check if the uploader is valid
  Future<bool> uploaderIsValid(List<String> args) async {
    final process = await Process.start(this.args.publisher, args);
    final exitCode = await process.exitCode;
    return exitCode == 0;
  }

  /// Start the upload process
  ///
  /// * `onVerbose` is called with the output of the process
  /// * `onError` is called with the error output of the process
  Future<int> publish({Function(String)? onVerbose, Function(String)? onError}) async {
    if (args.filePath.isEmpty) {
      onError?.call("File path is empty");
      return 1;
    }

    Future<String?> copyFiles(Directory sourceDir, String fileType, String errorMessage, String target) async {
      final files = await sourceDir.list().toList();
      final output = <String>[];
      if (files.isEmpty) {
        onError?.call(errorMessage);
        return "";
      }
      for (var item in files) {
        if (item is Directory) {
          return copyFiles(item, fileType, errorMessage, target);
        } else {
          if (item is File && item.path.endsWith(fileType)) {
            onVerbose?.call("Copying ${item.path} to $target");
            if (args.publisher == "firebase" || args.publisher == "fastlane") {
              await item.copy("$target/${item.path.split("/").last}");
              output.add(item.path);
            } else if (args.publisher == "xcrun") {
              await item.copy("$target/${item.path.split("/").last}");
              output.add(item.path);
            }
          }
        }
      }

      return output.first;
    }

    if (args is FastlaneAndroidPublisherArguments || args is FirebaseAndroidPublisherArguments) {
      if (args.binaryType == "aab" || args.binaryType == "appbundle") {
        onVerbose?.call("Scanning aab on ${Files.androidOutputAppbundles.path}");
        args.filePath = await copyFiles(Files.androidOutputAppbundles, ".aab", "No aab found in ${Files.androidOutputAppbundles.path}", args.filePath) ?? "";
      } else if (args.binaryType == "apk") {
        onVerbose?.call("Scanning apk on ${Files.androidOutputApks.path}");
        final outputApks = await Files.androidOutputApks.list().toList();
        String filePath = "";
        for (var dir in outputApks) {
          if (dir is Directory) {
            filePath = await copyFiles(dir, ".apk", "No apk found in ${dir.path}", args.filePath) ?? "";
            break;
          }
        }
        if (filePath.isEmpty) {
          onError?.call("No apk found in ${Files.androidOutputApks.path}");
          return 1;
        }
        args.filePath = filePath;
      } else {
        onError?.call("Invalid binary type: ${args.binaryType}");
        return 1;
      }
    } else if (args is XcrunIosPublisherArguments) {
      if (args.binaryType == "ipa") {
        onVerbose?.call("Scanning ipa on ${Files.iosOutputIPA.path}");
        args.filePath = await copyFiles(Files.iosOutputIPA, ".ipa", "No ipa found in ${Files.iosOutputIPA.path}", args.filePath) ?? "";
      } else {
        onError?.call("Invalid binary type: ${args.binaryType}");
        return 1;
      }
    }

    if (args.filePath.isEmpty) {
      onError?.call("File path is empty");
      return 1;
    }

    ColorizeLogger logger = ColorizeLogger(true);
    final rawArguments = args.toJson();
    rawArguments.removeWhere((key, value) => value == null || ((value is List) && value.isEmpty) || value == "");
    if (logger.isVerbose) {
      logger.logInfo("Running Publish with configurations:");
      for (var value in rawArguments.keys) {
        logger.logInfo(" - $value: [${rawArguments[value]}]");
      }
      logger.logEmpty();
    }
    onVerbose?.call("Starting upload with `${args.publisher} ${args.results.join(" ")}`");
    final process = await Process.start(args.publisher, args.results);
    process.stdout.transform(utf8.decoder).listen(onVerbose);
    process.stderr.transform(utf8.decoder).listen(onError);

    return await process.exitCode;
  }
}

/// Base class for all app publisher arguments
abstract class PublisherArguments extends JobArguments {
  final String publisher;

  /// The path to the file to upload
  String filePath;

  /// The binary type of the application to use. Valid values are apk, aab.
  final String binaryType;

  /// Constructor for the app publisher argument
  PublisherArguments(this.publisher, {required this.filePath, required this.binaryType});

  @override
  JobMode get jobMode => JobMode.publish;
}
