import 'dart:io';

import 'package:args/args.dart';
import 'package:dio/dio.dart';
import 'package:distribute_cli/app_publisher/publisher_arguments.dart';
import 'package:distribute_cli/parsers/config_parser.dart';

import '../../files.dart';
import '../../logger.dart';

/// Arguments for publishing to GitHub Releases.
///
/// This class is used to upload a release asset to a specified GitHub repository.
class Arguments extends PublisherArguments {
  /// The name of the GitHub repository.
  final String repoName;

  /// The owner of the GitHub repository.
  final String repoOwner;

  /// The GitHub token for authentication.
  final String token;

  /// The name of the release.
  final String releaseName;

  /// Dio HTTP client for API requests.
  late Dio _dio;

  /// Creates a new [Arguments] instance for GitHub publishing.
  Arguments({
    required super.filePath,
    required super.binaryType,
    required this.repoName,
    required this.repoOwner,
    required this.token,
    required this.releaseName,
  }) : super("github") {
    _dio = Dio(BaseOptions(
      baseUrl: "https://api.github.com",
    ));
  }

  @override
  List<String> get results => [];

  @override
  Map<String, dynamic> toJson() => {
        "file-path": filePath,
        "repo-name": repoName,
        "repo-owner": repoOwner,
        "token": token,
        "release-name": releaseName,
      };

  @override
  Future<int> publish(environments, {Function(String p1)? onVerbose, Function(String p1)? onError}) async {
    ColorizeLogger logger = ColorizeLogger(true);
    final rawArguments = toJson();
    _dio.options.headers["Authorization"] = "token ${substituteVariables(token, environments)}";

    rawArguments.removeWhere((key, value) => value == null || ((value is List) && value.isEmpty) || value == "");
    if (logger.isVerbose) {
      logger.logInfo("Running Publish with configurations:");
      for (var value in rawArguments.keys) {
        logger.logInfo(" - $value: ${(rawArguments[value])}");
      }
      logger.logEmpty();
    }

    onVerbose?.call("Starting upload with `$publisher ${results.join(" ")}`");
    onVerbose?.call("Initializing Github API client");
    final uploadUrl = (await _getReleaseUploadUrl().catchError((e) => null) ?? await _getLatestReleaseUploadUrl().catchError((e) => null) ?? await _createRelease().catchError((e) => null));
    if (uploadUrl == null) {
      onError?.call("Failed to get upload URL");
      return 1;
    }
    logger.logInfo("${await FileSystemEntity.isDirectory(filePath) ? "Directory" : "File"} detected on path: $filePath");
    if (await FileSystemEntity.isDirectory(filePath)) {
      logger.logInfo("Path is a directory");
      logger.logInfo("NOTE : All files in the directory will be uploaded");

      for (var file in Directory(filePath).listSync()) {
        if (file is File && file.path.endsWith(binaryType)) {
          final downloadUrl = await uploadFile(uploadUrl, file, onVerbose: onVerbose, onError: onError);
          if (downloadUrl == null) continue;
          onVerbose?.call("${file.path} uploaded successfully: $downloadUrl");
        }
      }
    } else {
      if (!await File(filePath).exists()) {
        onError?.call("File does not exist");
        return 1;
      }
      final downloadUrl = await uploadFile(uploadUrl, File(filePath), onVerbose: onVerbose, onError: onError);
      if (downloadUrl == null) return 1;

      onVerbose?.call("File uploaded successfully: $downloadUrl");
    }
    return 0;
  }

  Future<String?> _getReleaseUploadUrl() async {
    final response = await _dio.get('/repos/$repoOwner/$repoName/releases');
    if (response.statusCode == 200) {
      final releases = response.data;
      for (var release in releases) {
        if (release['name'] == releaseName) {
          return release["upload_url"].replaceAll("{?name,label}", "");
        }
      }
    }
    return null;
  }

  Future<String?> _getLatestReleaseUploadUrl() async {
    final response = await _dio.get('/repos/$repoOwner/$repoName/releases/latest');
    if (response.statusCode == 200) {
      return response.data["upload_url"].replaceAll("{?name,label}", "");
    }
    return null;
  }

  Future<String?> _createRelease() async {
    final response = await _dio.post('/repos/$repoOwner/$repoName/releases', data: {
      "tag_name": releaseName,
      "name": releaseName,
      "body": "Release $releaseName",
      "draft": true,
    });
    if (response.statusCode == 201) {
      return response.data["upload_url"].replaceAll("{?name,label}", "");
    }
    return null;
  }

  Future<String?> uploadFile(String uploadUrl, File file, {Function(String value)? onVerbose, Function(String value)? onError}) async {
    final fileName = file.path.split('/').last;
    onVerbose?.call("Uploading file: $fileName to $uploadUrl");
    try {
      final response = await _dio.post(uploadUrl, data: FormData.fromMap({"file": await MultipartFile.fromFile(file.path, filename: fileName)}), queryParameters: {"name": fileName});
      if (response.statusCode == 201) {
        return response.data["browser_download_url"];
      }
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response?.data is Map<String, dynamic>) {
          onError?.call("${e.response?.data["message"]}");
        } else {
          onError?.call("${e.response?.data}");
        }
      } else {
        onError?.call("${e.message}");
      }
    } catch (e) {
      onError?.call("$e");
    }
    return null;
  }

  static ArgParser parser = ArgParser()
    ..addOption('file-path', abbr: 'f', help: 'The path to the file to upload', mandatory: true)
    ..addOption('token', help: 'The token to use for github authentication.', mandatory: true)
    ..addOption('repo-name', help: 'The name of the repository to upload the file to.', mandatory: true)
    ..addOption('repo-owner', help: 'The owner of the repository to upload the file to.', mandatory: true)
    ..addOption('release-name', help: 'The release name to upload the file to.');

  factory Arguments.fromArgResults(ArgResults argResults) {
    return Arguments(
      filePath: argResults['file-path'] as String,
      binaryType: '', // Provide a default or derive this value as needed
      repoName: argResults['repo-name'] as String,
      repoOwner: argResults['repo-owner'] as String,
      token: argResults['token'] as String,
      releaseName: argResults['release-name'] as String,
    );
  }

  factory Arguments.fromJson(Map<String, dynamic> json) {
    if (json["file-path"] == null) throw Exception("file-path is required");
    if (json["repo-name"] == null) throw Exception("repo-name is required");
    if (json["repo-owner"] == null) throw Exception("repo-owner is required");
    if (json["token"] == null) throw Exception("token is required");

    return Arguments(
      filePath: json['file-path'] as String,
      binaryType: '', // Provide a default or derive this value as needed
      repoName: json['repo-name'] as String,
      repoOwner: json['repo-owner'] as String,
      token: json['token'] as String,
      releaseName: json['release-name'] as String,
    );
  }

  factory Arguments.defaultConfigs() => Arguments(
        filePath: Files.iosDistributionDir.parent.path,
        binaryType: '',
        repoName: '',
        repoOwner: '',
        token: '',
        releaseName: '',
      );
}
