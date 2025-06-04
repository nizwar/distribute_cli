import 'dart:io';

import 'package:args/args.dart';
import 'package:dio/dio.dart';
import 'package:distribute_cli/parsers/variables.dart';
import '../publisher_arguments.dart';

import '../../files.dart';

/// Comprehensive GitHub Releases arguments for automated app distribution.
///
/// Extends `PublisherArguments` to provide GitHub-specific configuration for
/// distributing applications through GitHub repository releases. Supports
/// advanced features like release management, asset uploads, and repository
/// integration.
///
/// Key capabilities:
/// - GitHub API integration
/// - Release creation and management
/// - Asset upload and organization
/// - Authentication and security
/// - File and directory processing
/// - Error handling and recovery
///
/// Example usage:
/// ```dart
/// final args = Arguments(
///   variables,
///   filePath: '/path/to/app.apk',
///   binaryType: 'apk',
///   repoOwner: 'flutter-org',
///   repoName: 'my-flutter-app',
///   token: 'ghp_xxxxxxxxxxxxxxxxxxxx',
///   releaseName: 'v1.0.0-beta.1',
///   releaseBody: 'Beta release with new features',
/// );
/// ```
class Arguments extends PublisherArguments {
  /// GitHub repository name for release publishing.
  ///
  /// The name of the target repository where releases will be created
  /// and assets uploaded. Must be accessible with the provided token.
  /// Repository must exist and token must have appropriate permissions.
  ///
  /// Example: "my-flutter-app"
  late String repoName;

  /// GitHub repository owner or organization name.
  ///
  /// The username or organization name that owns the target repository.
  /// Combined with `repoName` to form the full repository identifier.
  /// Must match the actual repository owner on GitHub.
  ///
  /// Example: "flutter-org" or "john-doe"
  late String repoOwner;

  /// GitHub personal access token for API authentication.
  ///
  /// Personal access token with appropriate repository permissions
  /// for creating releases and uploading assets. Required scopes:
  /// - `repo` (for private repositories)
  /// - `public_repo` (for public repositories)
  ///
  /// Format: "ghp_xxxxxxxxxxxxxxxxxxxx"
  /// Can be created in GitHub Settings > Developer settings > Personal access tokens
  late String token;

  /// Name or tag for the GitHub release.
  ///
  /// Identifies the release and serves as both the release name and git tag.
  /// Should follow semantic versioning conventions. If a release with this
  /// name exists, assets will be added to it; otherwise, a new release
  /// will be created.
  ///
  /// Example: "v1.2.3" or "2024.1.0-beta"
  late String releaseName;

  /// Descriptive text content for the release.
  ///
  /// Markdown-formatted description that appears in the release notes.
  /// Describes changes, features, fixes, and other relevant information.
  /// Supports full GitHub-flavored Markdown formatting.
  ///
  /// Example: "## What's New\n- Fixed login bug\n- Added dark mode"
  late String releaseBody;

  /// HTTP client for GitHub API communications.
  ///
  /// Dio instance configured for GitHub API base URL and request handling.
  /// Automatically configured with authentication headers and error handling.
  /// Used for all API operations including release management and uploads.
  late Dio _dio;

  /// Creates a new GitHub Releases publisher arguments instance.
  ///
  /// Initializes GitHub-specific configuration for automated app distribution
  /// through repository releases. Sets up API client and authentication for
  /// GitHub operations.
  ///
  /// Required parameters:
  /// - `variables` - System and environment variables
  /// - `filePath` - Path to the file or directory to upload
  /// - `binaryType` - Type of binary file for filtering
  /// - `repoName` - GitHub repository name
  /// - `repoOwner` - GitHub repository owner/organization
  /// - `token` - GitHub personal access token
  /// - `releaseName` - Release name/tag
  ///
  /// Example:
  /// ```dart
  /// final args = Arguments(
  ///   variables,
  ///   filePath: '/path/to/app.apk',
  ///   binaryType: 'apk',
  ///   repoOwner: 'flutter-org',
  ///   repoName: 'my-app',
  ///   token: 'ghp_xxxxxxxxxxxxxxxxxxxx',
  ///   releaseName: 'v1.0.0',
  ///   releaseBody: 'Initial release',
  /// );
  /// ```
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

  /// Builds the command arguments list (not used for GitHub API).
  ///
  /// GitHub publisher uses direct API calls rather than external commands,
  /// so this method returns an empty list. The publishing workflow is
  /// handled entirely through the `publish()` method using HTTP requests.
  ///
  /// Returns empty list as GitHub operations are API-based.
  @override
  List<String> get argumentBuilder => [];

  /// Serializes Arguments instance to JSON format.
  ///
  /// Converts all configuration parameters to a JSON-serializable map
  /// for storage, transmission, or configuration file generation.
  /// Includes all GitHub-specific parameters for complete configuration.
  ///
  /// Returns map containing all configuration parameters with their
  /// current values for serialization and persistence.
  ///
  /// Example output:
  /// ```json
  /// {
  ///   "file-path": "/path/to/app.apk",
  ///   "repo-name": "my-app",
  ///   "repo-owner": "flutter-org",
  ///   "token": "ghp_xxxxxxxxxxxxxxxxxxxx",
  ///   "release-name": "v1.0.0",
  ///   "release-body": "Initial release"
  /// }
  /// ```
  @override
  Map<String, dynamic> toJson() => {
        "file-path": filePath,
        "repo-name": repoName,
        "repo-owner": repoOwner,
        "token": token,
        "release-name": releaseName,
        "release-body": releaseBody,
      };

  /// Executes the GitHub Releases publishing workflow.
  ///
  /// Performs the complete GitHub release publishing process including
  /// variable processing, release management, and asset uploads. Handles
  /// both file and directory uploads with proper error handling.
  ///
  /// Publishing workflow:
  /// 1. Process variables and configure authentication
  /// 2. Initialize GitHub API client with token
  /// 3. Find existing release or create new one
  /// 4. Upload files/directory contents as release assets
  /// 5. Handle errors and provide detailed logging
  ///
  /// File handling:
  /// - Single files: Upload directly as release asset
  /// - Directories: Upload all matching binary files
  /// - Binary type filtering: Only files matching `binaryType`
  ///
  /// Returns exit code:
  /// - 0 = Success (all assets uploaded)
  /// - 1 = Error (upload failed or file issues)
  ///
  /// Throws exception for configuration or API errors.
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

  /// Retrieves the upload URL for an existing release by name.
  ///
  /// Searches through repository releases to find one matching the
  /// configured `releaseName`. If found, returns the upload URL for
  /// adding assets to that release.
  ///
  /// API endpoint: GET /repos/{owner}/{repo}/releases
  ///
  /// Returns upload URL string if release found, null otherwise.
  /// Upload URL is cleaned of query parameter templates for direct use.
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

  /// Retrieves the upload URL for the latest repository release.
  ///
  /// Gets the most recent release from the repository and checks if its
  /// name matches the configured `repoName`. If matched, returns the
  /// upload URL for adding assets to the latest release.
  ///
  /// API endpoint: GET /repos/{owner}/{repo}/releases/latest
  ///
  /// Returns upload URL string if latest release matches, null otherwise.
  /// Used as fallback when specific release name is not found.
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

  /// Creates a new GitHub release with the configured parameters.
  ///
  /// Creates a new draft release using the configured release name as both
  /// the tag name and release title. Includes the release body content
  /// and sets the release as draft for review before publishing.
  ///
  /// API endpoint: POST /repos/{owner}/{repo}/releases
  ///
  /// Release configuration:
  /// - Tag name: Uses `releaseName`
  /// - Release name: Uses `releaseName`
  /// - Body: Formatted with release name and body content
  /// - Draft: Set to true for review workflow
  ///
  /// Returns upload URL string if creation successful, null on failure.
  /// Used when no existing release is found for asset uploads.
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

  /// Uploads a file as a release asset to GitHub.
  ///
  /// Uploads the specified file to the GitHub release using the provided
  /// upload URL. Handles multipart form data upload with proper filename
  /// and content type detection. Provides comprehensive error handling
  /// and logging for upload operations.
  ///
  /// Parameters:
  /// - `uploadUrl` - GitHub release upload URL from API
  /// - `file` - File instance to upload as release asset
  ///
  /// Upload process:
  /// 1. Extract filename from file path
  /// 2. Create multipart form data with file content
  /// 3. Send POST request to upload URL with file data
  /// 4. Handle success/error responses with logging
  ///
  /// Returns browser download URL string if upload successful, null on failure.
  /// Download URL can be used to access the uploaded asset directly.
  ///
  /// Error handling:
  /// - Network errors: Logged with request details
  /// - API errors: Logged with response message
  /// - File errors: Logged with file information
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

  /// Command-line argument parser for GitHub Releases publisher.
  ///
  /// Defines all supported command-line options for the GitHub publisher
  /// with their descriptions, types, defaults, and validation rules.
  /// Used for parsing user input and generating help documentation.
  ///
  /// Includes comprehensive options for:
  /// - File paths and upload targets
  /// - Repository identification
  /// - Authentication and security
  /// - Release management
  /// - Content and metadata
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

  /// Creates Arguments instance from command-line arguments.
  ///
  /// Parses command-line arguments and optional global results to create
  /// a fully configured GitHub Arguments instance. Handles type conversion
  /// and validation for all GitHub-specific parameters.
  ///
  /// Parameters:
  /// - `argResults` - Parsed command-line arguments
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns configured Arguments instance with parsed values.
  /// Binary type is set to empty string as it's determined during upload.
  ///
  /// Note: Binary type filtering is handled during file processing
  /// rather than at argument parsing time for flexibility.
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

  /// Creates Arguments instance from JSON configuration.
  ///
  /// Deserializes JSON configuration data to create a GitHub Arguments
  /// instance. Validates required fields and provides proper error handling
  /// for missing or invalid configuration.
  ///
  /// Parameters:
  /// - `json` - JSON configuration map
  /// - `variables` - System variables for interpolation
  ///
  /// Returns configured Arguments instance from JSON data.
  ///
  /// Throws Exception if required fields are missing:
  /// - "file-path" is required
  /// - "repo-name" is required
  /// - "repo-owner" is required
  /// - "token" is required
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "file-path": "/path/to/app.apk",
  ///   "repo-name": "my-app",
  ///   "repo-owner": "flutter-org",
  ///   "token": "ghp_xxxxxxxxxxxxxxxxxxxx",
  ///   "release-name": "v1.0.0",
  ///   "release-body": "Initial release"
  /// }
  /// ```
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

  /// Creates default GitHub configuration for basic usage.
  ///
  /// Generates a basic GitHub Arguments instance with empty configuration
  /// suitable for initial setup or testing. All required fields are set
  /// to empty strings and must be configured before use.
  ///
  /// Parameters:
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns Arguments instance with default configuration:
  /// - iOS distribution directory as file path
  /// - Empty binary type (determined during processing)
  /// - Empty repository and authentication details
  ///
  /// Note: This configuration is not functional and requires
  /// proper values for all repository and authentication parameters.
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
