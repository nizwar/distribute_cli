import 'dart:io';

import 'package:args/args.dart';
import 'package:distribute_cli/parsers/build_info.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:path/path.dart' as path;

import '../../files.dart';
import '../publisher_arguments.dart';

/// Comprehensive Fastlane publisher arguments for automated app distribution.
///
/// Extends `PublisherArguments` to provide Fastlane-specific configuration for
/// deploying applications to Google Play Store and Apple App Store. Supports
/// advanced features like release tracks, rollouts, metadata management, and
/// debug symbol uploads.
///
/// Key capabilities:
/// - Multi-track deployment (production, beta, alpha, internal)
/// - Gradual rollout with percentage controls
/// - Metadata and asset synchronization
/// - Debug symbol and mapping file uploads
/// - Validation and preview modes
/// - Service account authentication
///
/// Example usage:
/// ```dart
/// final args = Arguments(
///   variables,
///   filePath: '/path/to/app.aab',
///   binaryType: 'aab',
///   metadataPath: '/path/to/fastlane/metadata',
///   jsonKey: '/path/to/service-account.json',
///   track: 'beta',
///   rollout: 0.25, // 25% rollout
/// );
/// ```
class Arguments extends PublisherArguments {
  /// Application version name for the release.
  ///
  /// Used when uploading new APK/AAB files to identify the version.
  /// Should match the version specified in the app's build configuration.
  /// Example: "1.2.3"
  final String? versionName;

  /// Application version code for the release.
  ///
  /// Integer version identifier used for version ordering and updates.
  /// Must be higher than the previous release for updates to work properly.
  /// Example: 42
  final int? versionCode;

  /// Release status for the uploaded version.
  ///
  /// Controls the state of the release in the store:
  /// - `completed` - Release is live and available to users
  /// - `draft` - Release is saved but not published
  /// - `halted` - Release is paused/stopped
  /// - `inProgress` - Release is being processed
  final String? releaseStatus;

  /// Distribution track for the application release.
  ///
  /// Determines which user group receives the release:
  /// - `production` - All users (public release)
  /// - `beta` - Beta testing users
  /// - `alpha` - Alpha testing users
  /// - `internal` - Internal testing team only
  ///
  /// Default: "production"
  final String track;

  /// Percentage of users to receive the rollout (0.0 to 1.0).
  ///
  /// When specified, enables gradual rollout where only a percentage
  /// of users receive the update initially. Useful for monitoring
  /// stability before full deployment.
  ///
  /// Example: 0.25 = 25% of users
  final double? rollout;

  /// Path to the directory containing Fastlane metadata files.
  ///
  /// Should contain subdirectories for each locale (e.g., en-US, es-ES)
  /// with metadata files like title.txt, short_description.txt, full_description.txt,
  /// and screenshots organized by device type.
  ///
  /// Example structure:
  /// ```
  /// metadata/
  ///   android/
  ///     en-US/
  ///       title.txt
  ///       short_description.txt
  ///       full_description.txt
  ///       images/
  ///         phoneScreenshots/
  /// ```
  final String metadataPath;

  /// Path to the Google Play service account JSON key file.
  ///
  /// Contains credentials for authenticating with Google Play Console API.
  /// Required for uploading to Google Play Store. Can be downloaded from
  /// Google Cloud Console under Service Accounts.
  final String jsonKey;

  /// Raw service account JSON data as a string.
  ///
  /// Alternative to `jsonKey` file path. Contains the service account
  /// credentials directly as JSON string data. Useful when credentials
  /// are stored as environment variables or secrets.
  final String? jsonKeyData;

  /// Path to a specific APK file to upload.
  ///
  /// Used when uploading a single APK file. Mutually exclusive with
  /// `apkPaths` for multiple APK uploads.
  final String? apk;

  /// Array of paths to multiple APK files to upload.
  ///
  /// Used for uploading multiple APK files in a single release.
  /// Useful for ABI-split APKs or multiple variants.
  final List<String>? apkPaths;

  /// Path to a specific AAB (Android App Bundle) file to upload.
  ///
  /// Used when uploading a single AAB file. AAB is the preferred
  /// format for Google Play Store distribution.
  final String? aab;

  /// Array of paths to multiple AAB files to upload.
  ///
  /// Used for uploading multiple AAB files in a single release.
  /// Less common than single AAB uploads.
  final List<String>? aabPaths;

  /// Whether to skip uploading APK files during publishing.
  ///
  /// When `true`, skips the APK upload step entirely, useful when only
  /// updating metadata or when APK is already uploaded separately.
  /// Default: `false`
  final bool skipUploadApk;

  /// Whether to skip uploading AAB (Android App Bundle) files during publishing.
  ///
  /// When `true`, skips the AAB upload step entirely, useful when only
  /// updating metadata or when AAB is already uploaded separately.
  /// Default: `false`
  final bool skipUploadAab;

  /// Whether to skip uploading metadata files during publishing.
  ///
  /// When `true`, skips uploading app metadata like descriptions, titles,
  /// and other store listing information. Changelogs are not included
  /// and controlled separately by `skipUploadChangelogs`.
  /// Default: `false`
  final bool skipUploadMetadata;

  /// Whether to skip uploading changelog files during publishing.
  ///
  /// When `true`, skips uploading release notes and changelog information.
  /// Metadata upload is controlled separately by `skipUploadMetadata`.
  /// Default: `false`
  final bool skipUploadChangelogs;

  /// Whether to skip uploading image assets during publishing.
  ///
  /// When `true`, skips uploading promotional images and graphics.
  /// Screenshots are not included and controlled separately by
  /// `skipUploadScreenshots`.
  /// Default: `false`
  final bool skipUploadImages;

  /// Whether to skip uploading screenshot images during publishing.
  ///
  /// When `true`, skips uploading app screenshots for all device types.
  /// Other image assets are controlled separately by `skipUploadImages`.
  /// Default: `false`
  final bool skipUploadScreenshots;

  /// Whether to use SHA256 comparison for intelligent image uploading.
  ///
  /// When `true`, compares SHA256 hashes of local images and screenshots
  /// with those already in Google Play Store to skip uploading identical
  /// files, improving upload efficiency and speed.
  /// Default: `false`
  final bool syncImageUpload;

  /// Target track for promoting an existing release.
  ///
  /// Specifies which track to promote a release to from its current track.
  /// Available tracks:
  /// - `production` - Public release to all users
  /// - `beta` - Beta testing track
  /// - `alpha` - Alpha testing track
  /// - `internal` - Internal testing track
  ///
  /// Used for track promotion workflows.
  final String? trackPromoteTo;

  /// Release status when promoting between tracks.
  ///
  /// Controls the status of the promoted release:
  /// - `completed` - Release is active and available
  /// - `draft` - Release is saved but not published
  /// - `halted` - Release is paused/stopped
  /// - `inProgress` - Release is being processed
  ///
  /// Default: "completed"
  final String? trackPromoteReleaseStatus;

  /// Whether to validate changes without actually publishing.
  ///
  /// When `true`, performs validation checks with Google Play Console
  /// without committing the changes. Useful for testing configurations
  /// and catching errors before actual deployment.
  /// Default: `false`
  final bool validateOnly;

  /// Path to the ProGuard mapping file or debug symbols.
  ///
  /// Points to a single mapping file (mapping.txt) or debug symbols archive
  /// (native-debug-symbols.zip) for crash reporting and debugging.
  /// Used for deobfuscation of crash reports in Google Play Console.
  final String? mapping;

  /// Array of paths to multiple mapping files or debug symbols.
  ///
  /// Specifies multiple mapping files (mapping.txt) or debug symbol archives
  /// (native-debug-symbols.zip) for uploading. Useful when dealing with
  /// multiple build variants or library mappings.
  final List<String>? mappingPaths;

  /// Custom root URL for Google Play API calls.
  ///
  /// Overrides the default Google Play API endpoint
  /// (https://www.googleapis.com/) with a custom URL. Useful for
  /// proxy configurations or custom API gateways.
  final String? rootUrl;

  /// Network timeout duration for API operations in seconds.
  ///
  /// Sets the timeout for read, open, and send operations when
  /// communicating with Google Play Console API. Higher values
  /// may be needed for large file uploads or slow connections.
  /// Default: 300 seconds (5 minutes)
  final int timeout;

  /// Array of version codes to retain during new APK publishing.
  ///
  /// Specifies which existing version codes should remain active
  /// when publishing a new APK. Useful for maintaining multiple
  /// active versions for different device configurations or
  /// gradual rollouts.
  final List<int>? versionCodesToRetain;

  /// Whether changes require manual review approval.
  ///
  /// When `true`, indicates that changes in this edit will not be
  /// automatically reviewed and must be explicitly sent for review
  /// from the Google Play Console UI. Used for policy-sensitive
  /// changes or complex releases.
  /// Default: `false`
  final bool changesNotSentForReview;

  /// Whether to automatically retry with recommended configuration.
  ///
  /// When `true`, catches `changes_not_sent_for_review` errors during
  /// edit commits and automatically retries with the configuration
  /// recommended in the error message. Helps handle policy requirements
  /// automatically.
  /// Default: `true`
  final bool rescueChangesNotSentForReview;

  /// In-app update priority level for new APKs.
  ///
  /// Sets the priority level for in-app updates for all newly added
  /// APKs in the release. Higher values indicate more urgent updates.
  /// Valid range: 0-5, where:
  /// - 0 = Default priority (no special handling)
  /// - 5 = Highest priority (immediate update recommendation)
  final int? inAppUpdatePriority;

  /// References version for the main expansion file.
  ///
  /// Specifies the version code that the main expansion file (OBB)
  /// references. Used for large games or apps that require additional
  /// asset files beyond the base APK size limits.
  final int? obbMainReferencesVersion;

  /// Size of the main expansion file in bytes.
  ///
  /// Specifies the exact file size of the main expansion file (OBB)
  /// in bytes. Required for proper expansion file handling and
  /// download verification on user devices.
  final int? obbMainFileSize;

  /// References version for the patch expansion file.
  ///
  /// Specifies the version code that the patch expansion file (OBB)
  /// references. Used for incremental updates to expansion file
  /// content without re-downloading the entire main expansion.
  final int? obbPatchReferencesVersion;

  /// Size of the patch expansion file in bytes.
  ///
  /// Specifies the exact file size of the patch expansion file (OBB)
  /// in bytes. Required for proper expansion file handling and
  /// download verification on user devices.
  final int? obbPatchFileSize;

  /// Whether to acknowledge bundle installation warnings.
  ///
  /// Must be set to `true` if the bundle installation may trigger
  /// warnings on user devices (e.g., "can only be downloaded over wifi").
  /// Typically required for bundles over 150MB. Acknowledges that
  /// users may see download restrictions.
  /// Default: `false`
  final bool? ackBundleInstallationWarning;

  /// Whether to upload debug symbols for crash reporting.
  ///
  /// When `true`, automatically uploads debug symbols and mapping files
  /// to Google Play Console for enhanced crash reporting and analysis.
  /// Enables deobfuscation of crash reports for easier debugging.
  /// Default: `true`
  final bool uploadDebugSymbols;

  /// Creates a new Fastlane publisher arguments instance.
  ///
  /// Initializes Fastlane-specific configuration for automated app distribution
  /// to Google Play Store and Apple App Store. Requires core publishing
  /// parameters and platform-specific authentication.
  ///
  /// Required parameters:
  /// - `variables` - System and environment variables
  /// - `filePath` - Path to the APK/AAB file to upload
  /// - `metadataPath` - Directory containing Fastlane metadata
  /// - `jsonKey` - Google service account key file path
  /// - `binaryType` - Type of binary file (apk/aab)
  ///
  /// Example:
  /// ```dart
  /// final args = Arguments(
  ///   variables,
  ///   filePath: '/path/to/app.aab',
  ///   binaryType: 'aab',
  ///   metadataPath: '/path/to/fastlane/metadata',
  ///   jsonKey: '/path/to/service-account.json',
  ///   track: 'beta',
  ///   rollout: 0.5, // 50% rollout
  /// );
  /// ```
  Arguments(
    Variables variables, {
    required super.filePath,
    required this.metadataPath,
    required this.jsonKey,
    required super.binaryType,
    this.releaseStatus,
    this.versionName,
    this.versionCode,
    this.track = "production",
    this.rollout,
    this.jsonKeyData,
    this.apk,
    this.apkPaths,
    this.aab,
    this.aabPaths,
    this.skipUploadApk = false,
    this.skipUploadAab = false,
    this.skipUploadMetadata = false,
    this.skipUploadChangelogs = false,
    this.skipUploadImages = false,
    this.skipUploadScreenshots = false,
    this.syncImageUpload = false,
    this.trackPromoteTo,
    this.trackPromoteReleaseStatus = "completed",
    this.validateOnly = false,
    this.mapping,
    this.mappingPaths,
    this.rootUrl,
    this.timeout = 300,
    this.versionCodesToRetain,
    this.changesNotSentForReview = false,
    this.rescueChangesNotSentForReview = true,
    this.inAppUpdatePriority,
    this.obbMainReferencesVersion,
    this.obbMainFileSize,
    this.obbPatchReferencesVersion,
    this.obbPatchFileSize,
    this.ackBundleInstallationWarning = false,
    this.uploadDebugSymbols = true,
  }) : super("fastlane", variables);

  /// Creates Arguments instance from command-line arguments.
  ///
  /// Parses command-line arguments and optional global results to create
  /// a fully configured Fastlane Arguments instance. Handles type conversion
  /// and validation for all supported parameters.
  ///
  /// Parameters:
  /// - `argResults` - Parsed command-line arguments
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns configured Arguments instance with parsed values.
  ///
  /// Throws Exception if required parameters are missing or invalid.
  factory Arguments.fromArgResults(
          ArgResults argResults, ArgResults? globalResults) =>
      Arguments(
        Variables.fromSystem(globalResults),
        filePath: argResults['file-path'],
        binaryType: argResults['binary-type'],
        versionName: argResults['version-name'],
        versionCode: int.tryParse(argResults['version-code'].toString()),
        releaseStatus: argResults['release-status'],
        track: argResults['track'] ?? "production",
        rollout: double.tryParse(argResults['rollout'] ?? ''),
        metadataPath: argResults['metadata-path'],
        jsonKey: argResults['json-key'],
        jsonKeyData: argResults['json-key-data'],
        apk: argResults['apk'],
        apkPaths: argResults['apk-paths'],
        aab: argResults['aab'],
        aabPaths: argResults['aab-paths'],
        skipUploadApk: argResults['skip-upload-apk'] ?? false,
        skipUploadAab: argResults['skip-upload-aab'] ?? false,
        skipUploadMetadata: argResults['skip-upload-metadata'] ?? false,
        skipUploadChangelogs: argResults['skip-upload-changelogs'] ?? false,
        skipUploadImages: argResults['skip-upload-images'] ?? false,
        skipUploadScreenshots: argResults['skip-upload-screenshots'] ?? false,
        syncImageUpload: argResults['sync-image-upload'] ?? false,
        trackPromoteTo: argResults['track-promote-to'],
        trackPromoteReleaseStatus: argResults['track-promote-release-status'],
        validateOnly: argResults['validate-only'] ?? false,
        mapping: argResults['mapping'],
        mappingPaths: argResults['mapping-paths'],
        rootUrl: argResults['root-url'],
        timeout: int.parse(argResults['timeout']),
        versionCodesToRetain:
            (argResults['version-codes-to-retain'])?.cast<int>(),
        changesNotSentForReview:
            (argResults['changes-not-sent-for-review'] as bool?) ?? false,
        rescueChangesNotSentForReview:
            (argResults['rescue-changes-not-sent-for-review'] as bool?) ?? true,
        inAppUpdatePriority:
            int.tryParse(argResults['in-app-update-priority'].toString()),
        obbMainReferencesVersion:
            int.tryParse(argResults['obb-main-references-version'].toString()),
        obbMainFileSize:
            int.tryParse(argResults['obb-main-file-size'].toString()),
        obbPatchReferencesVersion:
            int.tryParse(argResults['obb-patch-references-version'].toString()),
        obbPatchFileSize:
            int.tryParse(argResults['obb-patch-file-size'].toString()),
        ackBundleInstallationWarning:
            (argResults['ack-bundle-installation-warning'] as bool?) ?? false,
        uploadDebugSymbols: argResults['upload-debug-symbols'] ?? true,
      );

  /// Creates Arguments instance from JSON configuration.
  ///
  /// Deserializes JSON configuration data to create a Fastlane Arguments
  /// instance. Provides default values for optional parameters and
  /// validates required configuration.
  ///
  /// Parameters:
  /// - `json` - JSON configuration map
  /// - `variables` - System variables for interpolation
  ///
  /// Returns configured Arguments instance from JSON data.
  ///
  /// Throws Exception if required fields are missing:
  /// - "file-path" is required
  /// - "binary-type" is required
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "file-path": "/path/to/app.aab",
  ///   "binary-type": "aab",
  ///   "track": "production",
  ///   "metadata-path": "/path/to/metadata"
  /// }
  /// ```
  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    if (json['file-path'] == null) throw Exception("file-path is required");
    if (json['binary-type'] == null) throw Exception("binary-type is required");

    return Arguments(
      variables,
      filePath: json['file-path'] ?? "${Files.androidOutputApks.path}/*.apk",
      binaryType: json['binary-type'],
      versionName: json['version-name'],
      versionCode: json['version-code'],
      releaseStatus: json['release-status'],
      jsonKeyData: json['json-key-data'],
      apk: json['apk'],
      aab: json['aab'],
      track: json['track'] ?? "production",
      rollout: double.tryParse(json['rollout'] ?? ''),
      metadataPath:
          json['metadata-path'] ?? Files.androidDistributionMetadataDir.path,
      jsonKey: json['json-key'] ?? path.join("distribution", "fastlane.json"),
      apkPaths: (json['apk-paths'])?.toString().split(","),
      aabPaths: (json['aab-paths'])?.toString().split(","),
      skipUploadApk: json['skip-upload-apk'] ?? false,
      skipUploadAab: json['skip-upload-aab'] ?? false,
      skipUploadMetadata: json['skip-upload-metadata'] ?? false,
      skipUploadChangelogs: json['skip-upload-changelogs'] ?? false,
      skipUploadImages: json['skip-upload-images'] ?? false,
      skipUploadScreenshots: json['skip-upload-screenshots'] ?? false,
      syncImageUpload: json['sync-image-upload'] ?? false,
      trackPromoteTo: json['track-promote-to'],
      trackPromoteReleaseStatus: json['track-promote-release-status'],
      validateOnly: json['validate-only'] ?? false,
      mapping: json['mapping'],
      mappingPaths: (json['mapping-paths'])?.toString().split(","),
      rootUrl: json['root-url'],
      timeout: int.tryParse(json['timeout'].toString()) ?? 300,
      versionCodesToRetain: (json['version-codes-to-retain'])?.cast<int>(),
      changesNotSentForReview:
          (json['changes-not-sent-for-review'] as bool?) ?? false,
      rescueChangesNotSentForReview:
          (json['rescue-changes-not-sent-for-review'] as bool?) ?? true,
      inAppUpdatePriority:
          int.tryParse(json['in-app-update-priority'].toString()) ?? 0,
      obbMainReferencesVersion:
          int.tryParse(json['obb-main-references-version'].toString()),
      obbMainFileSize: int.tryParse(json['obb-main-file-size'].toString()),
      obbPatchReferencesVersion:
          int.tryParse(json['obb-patch-references-version'].toString()),
      obbPatchFileSize: int.tryParse(json['obb-patch-file-size'].toString()),
      ackBundleInstallationWarning:
          (json['ack-bundle-installation-warning'] as bool?) ?? false,
      uploadDebugSymbols: json['upload-debug-symbols'] ?? true,
    );
  }

  /// Builds the Fastlane command arguments list.
  ///
  /// Constructs the complete command-line arguments for the Fastlane
  /// `upload_to_play_store` action. Handles file path resolution,
  /// mapping file detection, and parameter formatting.
  ///
  /// Key behavior:
  /// - Automatically detects binary files in directories
  /// - Adds debug symbols mapping files when found
  /// - Formats all parameters for Fastlane execution
  /// - Includes conditional parameters based on configuration
  ///
  /// Returns list of formatted Fastlane command arguments.
  ///
  /// Example output:
  /// ```
  /// ["run", "upload_to_play_store", "aab:/path/to/app.aab",
  ///  "metadata_path:/path/to/metadata", "track:production"]
  /// ```
  @override
  List<String> get argumentBuilder {
    final mappingPathParser = (mappingPaths ?? []);

    String filePath = this.filePath;
    if (FileSystemEntity.isDirectorySync(filePath)) {
      final file = (Directory(filePath).listSync()).firstWhere(
          (item) => item.path.endsWith(binaryType == "apk" ? ".apk" : ".aab"),
          orElse: () => throw Exception("No file found"));
      filePath = file.path;
      mappingPathParser.add("${this.filePath}/debug_symbols.zip");
    } else {
      mappingPathParser.add("${File(filePath).parent.path}/debug_symbols.zip");
    }
    return [
      "run",
      "upload_to_play_store",
      "metadata_path:$metadataPath",
      binaryType == "apk" ? "apk:$filePath" : "aab:$filePath",
      "package_name:${parent.parent.packageName}",
      "json_key:$jsonKey",
      "timeout:$timeout",
      "track:$track",
      if (releaseStatus != null) "release_status:$releaseStatus",
      if (versionName != null) "version_name:$versionName",
      if (versionCode != null) "version_code:$versionCode",
      if (rollout != null) "rollout:$rollout",
      if (jsonKeyData != null) "json_key_data:$jsonKeyData",
      if (apk != null) "apk:$apk",
      if (apkPaths != null && apkPaths!.isNotEmpty)
        "apk_paths:${apkPaths!.join(',')}",
      if (aab != null) "aab:$aab",
      if (aabPaths != null && aabPaths!.isNotEmpty)
        "aab_paths:${aabPaths!.join(',')}",
      if (skipUploadApk) "skip_upload_apk:true",
      if (skipUploadAab) "skip_upload_aab:true",
      if (skipUploadMetadata) "skip_upload_metadata:true",
      if (skipUploadChangelogs) "skip_upload_changelogs:true",
      if (skipUploadImages) "skip_upload_images:true",
      if (skipUploadScreenshots) "skip_upload_screenshots:true",
      if (syncImageUpload) "sync_image_upload:true",
      if (trackPromoteTo != null) "track_promote_to:$trackPromoteTo",
      if (trackPromoteReleaseStatus != null)
        "track_promote_release_status:$trackPromoteReleaseStatus",
      if (validateOnly) "validate_only:true",
      if (mapping != null) "mapping:$mapping",
      if (mappingPathParser.isNotEmpty)
        "mapping_paths:${mappingPathParser.join(',')}",
      if (rootUrl != null) "root_url:$rootUrl",
      if (versionCodesToRetain != null && versionCodesToRetain!.isNotEmpty)
        "version_codes_to_retain:${versionCodesToRetain!.join(',')}",
      if (changesNotSentForReview) "changes_not_sent_for_review:true",
      if (rescueChangesNotSentForReview)
        "rescue_changes_not_sent_for_review:true",
      if (inAppUpdatePriority != null)
        "in_app_update_priority:$inAppUpdatePriority",
      if (obbMainReferencesVersion != null)
        "obb_main_references_version:$obbMainReferencesVersion",
      if (obbMainFileSize != null) "obb_main_file_size:$obbMainFileSize",
      if (obbPatchReferencesVersion != null)
        "obb_patch_references_version:$obbPatchReferencesVersion",
      if (obbPatchFileSize != null) "obb_patch_file_size:$obbPatchFileSize",
      if (ackBundleInstallationWarning == true)
        "ack_bundle_installation_warning:$ackBundleInstallationWarning",
    ];
  }

  /// Command-line argument parser for Fastlane publisher.
  ///
  /// Defines all supported command-line options for the Fastlane publisher
  /// with their descriptions, types, defaults, and validation rules.
  /// Used for parsing user input and generating help documentation.
  ///
  /// Includes comprehensive options for:
  /// - File paths and binary types
  /// - Version and release management
  /// - Track and rollout configuration
  /// - Metadata and asset handling
  /// - Upload controls and validation
  /// - Advanced Google Play features
  static ArgParser parser = ArgParser()
    ..addOption('file-path',
        abbr: 'f', help: 'Path to the file to upload.', mandatory: true)
    ..addOption('binary-type',
        help:
            'The binary type of the application to use. Valid values are apk, aab.',
        defaultsTo: "apk")
    ..addOption(
      'package-name',
      abbr: 'p',
      help: 'The package name of the application to use.',
      defaultsTo: BuildInfo.androidPackageName,
      mandatory: BuildInfo.androidPackageName == null,
    )
    ..addOption('version-name',
        help:
            'Version name (used when uploading new APKs/AABs) - defaults to versionName in build.gradle or AndroidManifest.xml.')
    ..addOption('version-code',
        abbr: 'c',
        help: 'The versionCode for which to download the generated APK.')
    ..addOption('release-status',
        abbr: 'r',
        help:
            'Release status (used when uploading new APKs/AABs) - valid values are completed, draft, halted, inProgress.')
    ..addOption('track',
        abbr: 't',
        help:
            'The track of the application to use. The default available tracks are: production, beta, alpha, internal.')
    ..addOption('rollout',
        abbr: 'R',
        help:
            'The percentage of the user fraction when uploading to the rollout track (setting to 1 will complete the rollout).')
    ..addOption('metadata-path',
        help: 'Path to the directory containing the metadata files.',
        defaultsTo: Files.androidDistributionMetadataDir.path)
    ..addOption('json-key',
        abbr: 'j',
        help:
            'The path to a file containing service account JSON, used to authenticate with Google.',
        defaultsTo: Files.fastlaneJson.path)
    ..addOption('json-key-data',
        abbr: 'J',
        help:
            'The raw service account JSON data used to authenticate with Google.')
    ..addOption('apk', abbr: 'a', help: 'Path to the APK file to upload.')
    ..addMultiOption('apk-paths',
        abbr: 'A', help: 'An array of paths to APK files to upload.')
    ..addOption('aab', abbr: 'b', help: 'Path to the AAB file to upload.')
    ..addMultiOption('aab-paths',
        abbr: 'B', help: 'An array of paths to AAB files to upload.')
    ..addFlag('skip-upload-apk',
        negatable: false,
        defaultsTo: false,
        help: 'Whether to skip uploading APK.')
    ..addFlag('skip-upload-aab',
        negatable: false,
        defaultsTo: false,
        help: 'Whether to skip uploading AAB.')
    ..addFlag('skip-upload-metadata',
        negatable: false,
        defaultsTo: false,
        help: 'Whether to skip uploading metadata, changelogs not included.')
    ..addFlag('skip-upload-changelogs',
        negatable: false,
        defaultsTo: false,
        help: 'Whether to skip uploading changelogs.')
    ..addFlag('skip-upload-images',
        negatable: false,
        defaultsTo: false,
        help: 'Whether to skip uploading images, screenshots not included.')
    ..addFlag('skip-upload-screenshots',
        negatable: false,
        defaultsTo: false,
        help: 'Whether to skip uploading screenshots.')
    ..addFlag('sync-image-upload',
        negatable: false,
        defaultsTo: false,
        help:
            'Whether to use sha256 comparison to skip upload of images and screenshots that are already in Play Store.')
    ..addOption('track-promote-to',
        abbr: 'T',
        help:
            'The track to promote to. The default available tracks are: production, beta, alpha, internal.')
    ..addOption('track-promote-release-status',
        abbr: 's',
        help:
            'Promoted track release status (used when promoting a track) - valid values are completed, draft, halted, inProgress.')
    ..addFlag('validate-only',
        negatable: false,
        defaultsTo: false,
        help:
            'Only validate changes with Google Play rather than actually publish.')
    ..addOption('mapping',
        abbr: 'm',
        help:
            'Path to the mapping file to upload (mapping.txt or native-debug-symbols.zip alike).')
    ..addMultiOption('mapping-paths',
        abbr: 'M',
        help:
            'An array of paths to mapping files to upload (mapping.txt or native-debug-symbols.zip alike).')
    ..addOption('root-url',
        abbr: 'u',
        help:
            'Root URL for the Google Play API. The provided URL will be used for API calls in place of https://www.googleapis.com/.')
    ..addOption('timeout',
        defaultsTo: "300",
        help: 'Timeout for read, open and send (in seconds).')
    ..addMultiOption('version-codes-to-retain',
        abbr: 'V',
        help: 'An array of version codes to retain when publishing a new APK.')
    ..addFlag('changes-not-sent-for-review',
        negatable: false,
        defaultsTo: false,
        help:
            'Indicates that the changes in this edit will not be reviewed until they are explicitly sent for review from the Google Play Console UI.')
    ..addFlag('rescue-changes-not-sent-for-review',
        negatable: false,
        defaultsTo: true,
        help:
            'Catches changes_not_sent_for_review errors when an edit is committed and retries with the configuration that the error message recommended.')
    ..addOption('in-app-update-priority',
        abbr: 'I',
        help:
            'In-app update priority for all the newly added APKs in the release. Can take values between [0,5].')
    ..addOption('obb-main-references-version',
        abbr: 'O', help: 'References version of main expansion file.')
    ..addOption('obb-main-file-size',
        abbr: 'S', help: 'Size of main expansion file in bytes.')
    ..addOption('obb-patch-references-version',
        abbr: 'P', help: 'References version of patch expansion file.')
    ..addOption('obb-patch-file-size',
        abbr: 'F', help: 'Size of patch expansion file in bytes.')
    ..addFlag('upload-debug-symbols',
        negatable: false,
        defaultsTo: true,
        help: 'Whether to upload debug symbols.')
    ..addFlag('ack-bundle-installation-warning',
        negatable: false,
        defaultsTo: false,
        help:
            'Must be set to true if the bundle installation may trigger a warning on user devices (e.g can only be downloaded over wifi). Typically this is required for bundles over 150MB.');

  /// Creates default Fastlane configuration for a package.
  ///
  /// Generates a basic Fastlane Arguments instance with default settings
  /// suitable for most Android app publishing scenarios. Uses standard
  /// paths and common configuration values.
  ///
  /// Parameters:
  /// - `packageName` - Android package name for the app
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns Arguments instance with default configuration:
  /// - APK binary type
  /// - Standard distribution output directory
  /// - Default metadata path
  /// - Fastlane JSON key location
  /// - Debug symbols upload enabled
  ///
  /// Useful for quick setup and testing scenarios.
  factory Arguments.defaultConfigs(
          String packageName, ArgResults? globalResults) =>
      Arguments(
        Variables.fromSystem(globalResults),
        filePath: "${Files.androidDistributionOutputDir.path}/*.apk",
        metadataPath: Files.androidDistributionMetadataDir.path,
        jsonKey: Files.fastlaneJson.path,
        uploadDebugSymbols: true,
        binaryType: "apk",
      );

  /// Serializes Arguments instance to JSON format.
  ///
  /// Converts all configuration parameters to a JSON-serializable map
  /// for storage, transmission, or configuration file generation.
  /// Handles proper formatting of arrays and optional values.
  ///
  /// Returns map containing all configuration parameters with their
  /// current values. Arrays are joined with commas, null values
  /// are preserved for proper deserialization.
  ///
  /// Example output:
  /// ```json
  /// {
  ///   "file-path": "/path/to/app.aab",
  ///   "binary-type": "aab",
  ///   "track": "production",
  ///   "upload-debug-symbols": true
  /// }
  /// ```
  @override
  Map<String, dynamic> toJson() => {
        'file-path': filePath,
        'binary-type': binaryType,
        'version-name': versionName,
        'version-code': versionCode,
        'release-status': releaseStatus,
        'track': track,
        'rollout': rollout,
        'metadata-path': metadataPath,
        'json-key': jsonKey,
        'json-key-data': jsonKeyData,
        'apk': apk,
        'apk-paths': apkPaths?.join(","),
        'aab': aab,
        'aab-paths': aabPaths?.join(","),
        'skip-upload-apk': skipUploadApk,
        'skip-upload-aab': skipUploadAab,
        'skip-upload-metadata': skipUploadMetadata,
        'skip-upload-changelogs': skipUploadChangelogs,
        'skip-upload-images': skipUploadImages,
        'skip-upload-screenshots': skipUploadScreenshots,
        'sync-image-upload': syncImageUpload,
        'track-promote-to': trackPromoteTo,
        'track-promote-release-status': trackPromoteReleaseStatus,
        'validate-only': validateOnly,
        'mapping': mapping,
        'mapping-paths': mappingPaths?.join(","),
        'root-url': rootUrl,
        'timeout': timeout,
        'version-codes-to-retain': versionCodesToRetain,
        'changes-not-sent-for-review': changesNotSentForReview,
        'rescue-changes-not-sent-for-review': rescueChangesNotSentForReview,
        'in-app-update-priority': inAppUpdatePriority,
        'obb-main-references-version': obbMainReferencesVersion,
        'obb-main-file-size': obbMainFileSize,
        'obb-patch-references-version': obbPatchReferencesVersion,
        'obb-patch-file-size': obbPatchFileSize,
        'ack-bundle-installation-warning': ackBundleInstallationWarning,
        'upload-debug-symbols': uploadDebugSymbols,
      };
}
