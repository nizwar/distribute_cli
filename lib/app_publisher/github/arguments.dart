import 'dart:io';

import 'package:args/args.dart';
import 'package:dio/dio.dart';
import 'package:distribute_cli/parsers/variables.dart';
import '../publisher_arguments.dart';

import '../../files.dart';

/// Arguments for publishing to GitHub Releases.
///
/// This class is used to upload a release asset to a specified GitHub repository.
class Arguments extends PublisherArguments {
  /// The name of the GitHub repository.
  late String repoName;

  /// The owner of the GitHub repository.
  late String repoOwner;

  /// The GitHub token for authentication.
  late String token;

  /// The name of the release.
  late String releaseName;

  /// The body of the release.
  late String releaseBody;

  /// Dio HTTP client for API requests.
  late Dio _dio;

  /// Creates a new [Arguments] instance for GitHub publishing.
  Arguments(
    Variables variables, {
    required super.filePath,
    required super.binaryType,
    required this.repoName,
    required this.repoOwner,
    required this.token,
    required this.releaseName,
    this.releaseBody = "",
  }) : super("github", variables) {
    _dio = Dio(BaseOptions(
      baseUrl: "https://api.github.com",
    ));
  }

  @override
  List<String> get argumentBuilder => [];

  @override
  Map<String, dynamic> toJson() => {
        "file-path": filePath,
        "repo-name": repoName,
        "repo-owner": repoOwner,
        "token": token,
        "release-name": releaseName,
        "release-body": releaseBody,
      };

  @override
  Future<int> publish() async {
    final argumentBuilder = Arguments.fromJson(
        await variables.processMap(toJson()),
        variables: variables);
    await argumentBuilder.printJob();

    final arguments = await argumentBuilder.arguments;

    argumentBuilder._dio.options.headers["Authorization"] =
        "token ${await variables.process(token)}";
    logger.logDebug
        .call("Starting upload with `$publisher ${arguments.join(" ")}`");
    logger.logDebug.call("Initializing Github API client");

    final uploadUrl =
        (await argumentBuilder._getReleaseUploadUrl().catchError((e) => null) ??
            await argumentBuilder
                ._getLatestReleaseUploadUrl()
                .catchError((e) => null) ??
            await argumentBuilder._createRelease().catchError((e) => null));
    if (uploadUrl == null) {
      logger.logErrorVerbose.call("Failed to get upload URL");
      return 1;
    }

    logger.logInfo(
        "${await FileSystemEntity.isDirectory(filePath) ? "Directory" : "File"} detected on path: $filePath");
    if (await FileSystemEntity.isDirectory(filePath)) {
      logger.logInfo("Path is a directory");
      logger.logInfo("NOTE : All files in the directory will be uploaded");
      for (var file in Directory(filePath).listSync()) {
        if (file is File && file.path.endsWith(binaryType)) {
          final downloadUrl = await argumentBuilder.uploadFile(uploadUrl, file);
          if (downloadUrl == null) continue;
          logger.logDebug
              .call("${file.path} uploaded successfully: $downloadUrl");
        }
      }
    } else {
      if (!await File(filePath).exists()) {
        logger.logErrorVerbose.call("File does not exist");
        return 1;
      }
      final downloadUrl =
          await argumentBuilder.uploadFile(uploadUrl, File(filePath));
      if (downloadUrl == null) return 1;

      logger.logDebug.call("File uploaded successfully: $downloadUrl");
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
    final response =
        await _dio.get('/repos/$repoOwner/$repoName/releases/latest');
    if (response.statusCode == 200) {
      if (response.data["name"] == repoName) {
        return response.data["upload_url"].replaceAll("{?name,label}", "");
      }
    }
    return null;
  }

  Future<String?> _createRelease() async {
    final response =
        await _dio.post('/repos/$repoOwner/$repoName/releases', data: {
      "tag_name": releaseName,
      "name": releaseName,
      "body": "Release $releaseName\n$releaseBody",
      "draft": true,
    });
    if (response.statusCode == 201) {
      return response.data["upload_url"].replaceAll("{?name,label}", "");
    }
    return null;
  }

  Future<String?> uploadFile(String uploadUrl, File file) async {
    final fileName = file.path.split('/').last;
    logger.logDebug.call("Uploading file: $fileName to $uploadUrl");
    try {
      final response = await _dio.post(uploadUrl,
          data: FormData.fromMap({
            "file": await MultipartFile.fromFile(file.path, filename: fileName)
          }),
          queryParameters: {"name": fileName});
      if (response.statusCode == 201) {
        return response.data["browser_download_url"];
      }
    } on DioException catch (e) {
      logger.logErrorVerbose.call("Failed to upload file: $fileName");
      if (e.response != null) {
        if (e.response?.data is Map<String, dynamic>) {
          logger.logErrorVerbose
              .call("Response : ${e.response?.data["message"]}");
        } else {
          logger.logErrorVerbose.call("Response : ${e.response?.data}");
        }
      } else {
        logger.logErrorVerbose.call("Response : ${e.message}");
      }
    } catch (e) {
      logger.logErrorVerbose.call("$e");
    }
    return null;
  }

  static ArgParser parser = ArgParser()
    ..addOption('file-path',
        abbr: 'f', help: 'The path to the file to upload', mandatory: true)
    ..addOption('token',
        help: 'The token to use for github authentication.', mandatory: true)
    ..addOption('repo-name',
        help: 'The name of the repository to upload the file to.',
        mandatory: true)
    ..addOption('repo-owner',
        help: 'The owner of the repository to upload the file to.',
        mandatory: true)
    ..addOption('release-name', help: 'The release name to upload the file to.')
    ..addOption('release-body',
        help: 'The release body to upload the file to.');

  factory Arguments.fromArgResults(
      ArgResults argResults, ArgResults? globalResults) {
    return Arguments(
      Variables.fromSystem(globalResults),
      filePath: argResults['file-path'] as String,
      binaryType: '', // Provide a default or derive this value as needed
      repoName: argResults['repo-name'] as String,
      repoOwner: argResults['repo-owner'] as String,
      token: argResults['token'] as String,
      releaseName: argResults['release-name'] as String,
      releaseBody: argResults['release-body'] ?? "",
    );
  }

  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    if (json["file-path"] == null) throw Exception("file-path is required");
    if (json["repo-name"] == null) throw Exception("repo-name is required");
    if (json["repo-owner"] == null) throw Exception("repo-owner is required");
    if (json["token"] == null) throw Exception("token is required");

    return Arguments(
      variables,
      filePath: json['file-path'] as String,
      binaryType: '', // Provide a default or derive this value as needed
      repoName: json['repo-name'] as String,
      repoOwner: json['repo-owner'] as String,
      token: json['token'] as String,
      releaseName: json['release-name'] as String,
      releaseBody: json['release-body'] ?? "",
    );
  }

  factory Arguments.defaultConfigs(ArgResults? globalResults) => Arguments(
        Variables.fromSystem(globalResults),
        filePath: Files.iosDistributionDir.parent.path,
        binaryType: '',
        repoName: '',
        repoOwner: '',
        token: '',
        releaseName: '',
        releaseBody: '',
      );
}
