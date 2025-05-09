import 'package:args/args.dart';
import 'package:dio/dio.dart';
import 'package:distribute_cli/app_publisher/publisher_arguments.dart';

class Arguments extends PublisherArguments {
  final String repoName;
  final String repoOwner;
  final String repoToken;
  final String releaseName;
  late Dio _dio;

  Arguments({
    required super.filePath,
    required super.binaryType,
    required this.repoName,
    required this.repoOwner,
    required this.repoToken,
    required this.releaseName,
  }) : super("github") {
    _dio = Dio(BaseOptions(
      headers: {"Authorization": "token $repoToken", "Accept": "application/vnd.github.v3+json"},
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
        "repo-token": repoToken,
        "release-name": releaseName,
      };

  @override
  Future<int> publish(environments, {Function(String p1)? onVerbose, Function(String p1)? onError}) async {
    final uploadUrl = await _getReleaseUploadUrl() ?? await _getLatestReleaseUploadUrl() ?? await _createRelease();
    if (uploadUrl == null) {
      onError?.call("Failed to get upload URL");
      return 1;
    }
    final downloadUrl = await uploadFile(uploadUrl, onVerbose: onVerbose);
    if (downloadUrl == null) {
      onError?.call("Failed to upload file");
      return 1;
    }
    onVerbose?.call("File uploaded successfully: $downloadUrl");
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

  Future<String?> uploadFile(String uploadUrl, {Function(String value)? onVerbose}) async {
    final fileName = filePath.split('/').last;
    final response = await _dio.post(
      "$uploadUrl/?name=$releaseName",
      data: FormData.fromMap({
        "file": await MultipartFile.fromFile(filePath, filename: fileName),
      }),
      options: Options(headers: {"Content-Type": "application/octet-stream"}),
      onSendProgress: (count, total) {
        if (total > 0) {
          final progress = (count / total * 100).toStringAsFixed(0);
          onVerbose?.call("Github Uploading: $progress%");
        }
      },
    );
    if (response.statusCode == 201) {
      return response.data["browser_download_url"];
    }
    return null;
  }

  static ArgParser parser = ArgParser()
    ..addOption('file-path', abbr: 'f', help: 'The path to the file to upload', mandatory: true)
    ..addOption('repo-name', help: 'The name of the repository to upload the file to.', mandatory: true)
    ..addOption('repo-owner', help: 'The owner of the repository to upload the file to.', mandatory: true)
    ..addOption('repo-token', help: 'The token to use for authentication.', mandatory: true)
    ..addOption('release-name', help: 'The release name to upload the file to.');

  factory Arguments.fromArgResults(ArgResults argResults) {
    return Arguments(
      filePath: argResults['file-path'] as String,
      binaryType: '', // Provide a default or derive this value as needed
      repoName: argResults['repo-name'] as String,
      repoOwner: argResults['repo-owner'] as String,
      repoToken: argResults['repo-token'] as String,
      releaseName: argResults['release-name'] as String,
    );
  }
}
