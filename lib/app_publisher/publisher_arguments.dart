import 'dart:convert';
import 'dart:io';

import 'package:distribute_cli/logger.dart';

import '../files.dart';
import '../parsers/config_parser.dart';
import '../parsers/job_arguments.dart';

/// Base class for all app publisher arguments
abstract class PublisherArguments extends JobArguments {
  final String publisher;

  /// The path to the file to upload
  String filePath;

  /// The binary type of the application to use. Valid values are apk, aab.
  final String binaryType;

  late PublisherJob parent;

  /// Constructor for the app publisher argument
  PublisherArguments(this.publisher, {required this.filePath, required this.binaryType});

  /// Start the upload process
  ///
  /// * `onVerbose` is called with the output of the process
  /// * `onError` is called with the error output of the process
  Future<int> publish(final environments, {Function(String)? onVerbose, Function(String)? onError}) async {
    await _processFilesArgs(onVerbose: onVerbose, onError: onError);

    ColorizeLogger logger = ColorizeLogger(true);
    final rawArguments = toJson();
    rawArguments.removeWhere((key, value) => value == null || ((value is List) && value.isEmpty) || value == "");
    if (logger.isVerbose) {
      logger.logInfo("Running Publish with configurations:");
      for (var value in rawArguments.keys) {
        logger.logInfo(" - $value: ${rawArguments[value]}");
      }
      logger.logEmpty();
    }
    onVerbose?.call("Starting upload with `$publisher ${results.join(" ")}`");
    final process = await Process.start(publisher, results.map((e) => substituteVariables(e, environments)).toList());
    process.stdout.transform(utf8.decoder).listen(onVerbose);
    process.stderr.transform(utf8.decoder).listen(onError);

    return await process.exitCode;
  }

  Future<void> _processFilesArgs({Function(String)? onVerbose, Function(String)? onError}) async {
    if (filePath.isEmpty) {
      onError?.call("File path is empty");
    }

    if (await FileSystemEntity.isDirectory(filePath)) {
      final binaryType = this.binaryType;
      if (Directory(filePath).existsSync() && Directory(filePath).listSync().where((item) => item.path.endsWith(binaryType)).isEmpty) {
        if ((binaryType == "apk" || binaryType == "aab")) {
          onVerbose?.call("Scanning ${this.binaryType} on ${Files.androidOutputApks.path}");
          final sourceDir = binaryType == "apk" ? Files.androidOutputApks : Files.androidOutputAppbundles;
          filePath = await Files.copyFiles(sourceDir.path, filePath, fileType: [binaryType]) ?? "";
        } else if (binaryType == "ipa") {
          onVerbose?.call("Scanning ${this.binaryType} on ${Files.iosOutputIPA.path}");
          filePath = await Files.copyFiles(Files.iosOutputIPA.path, filePath, fileType: ["ipa"]) ?? "";
        } else {
          onError?.call("Invalid binary type: $binaryType");
        }
      } else {
        filePath = Directory(filePath).listSync().firstWhere((element) => element is File && element.path.endsWith(this.binaryType)).path;
      }
    }

    if (filePath.isEmpty) {
      onError?.call("File path is empty");
    }
  }
}
