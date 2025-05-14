import 'dart:io';

import 'package:args/args.dart';

import '../../files.dart';
import '../publisher_arguments.dart';

/// Arguments for Fastlane Android Publisher.
///
/// This class is used to upload the app to the Google Play Store using Fastlane.
class Arguments extends PublisherArguments {
  /// Version name (used when uploading new APKs/AABs).
  final String? versionName;

  /// The versionCode for which to download the generated APK.
  final int? versionCode;

  /// Release status (valid values: completed, draft, halted, inProgress).
  final String? releaseStatus;

  /// The track of the application to use (e.g., production, beta, alpha, internal).
  final String track;

  /// The percentage of the user fraction when uploading to the rollout track.
  final double? rollout;

  /// Path to the directory containing the metadata files.
  final String metadataPath;

  /// The path to a file containing service account JSON.
  final String jsonKey;

  /// The raw service account JSON data.
  final String? jsonKeyData;

  /// Path to the APK file to upload.
  final String? apk;

  /// An array of paths to APK files to upload.
  final List<String>? apkPaths;

  /// Path to the AAB file to upload.
  final String? aab;

  /// An array of paths to AAB files to upload.
  final List<String>? aabPaths;

  /// Whether to skip uploading APK.
  final bool skipUploadApk;

  /// Whether to skip uploading AAB.
  final bool skipUploadAab;

  /// Whether to skip uploading metadata, changelogs not included.
  final bool skipUploadMetadata;

  /// Whether to skip uploading changelogs.
  final bool skipUploadChangelogs;

  /// Whether to skip uploading images, screenshots not included.
  final bool skipUploadImages;

  /// Whether to skip uploading screenshots.
  final bool skipUploadScreenshots;

  /// Whether to use sha256 comparison to skip upload of images and screenshots that are already in Play Store.
  final bool syncImageUpload;

  /// The track to promote to. The default available tracks are: production, beta, alpha, internal.
  final String? trackPromoteTo;

  /// Promoted track release status (used when promoting a track) - valid values are completed, draft, halted, inProgress.
  final String? trackPromoteReleaseStatus;

  /// Only validate changes with Google Play rather than actually publish.
  final bool validateOnly;

  /// Path to the mapping file to upload (mapping.txt or native-debug-symbols.zip alike).
  final String? mapping;

  /// An array of paths to mapping files to upload (mapping.txt or native-debug-symbols.zip alike).
  final List<String>? mappingPaths;

  /// Root URL for the Google Play API. The provided URL will be used for API calls in place of https://www.googleapis.com/.
  final String? rootUrl;

  /// Timeout for read, open, and send (in seconds).
  final int timeout;

  /// An array of version codes to retain when publishing a new APK.
  final List<int>? versionCodesToRetain;

  /// Indicates that the changes in this edit will not be reviewed until they are explicitly sent for review from the Google Play Console UI.
  final bool changesNotSentForReview;

  /// Catches changes_not_sent_for_review errors when an edit is committed and retries with the configuration that the error message recommended.
  final bool rescueChangesNotSentForReview;

  /// In-app update priority for all the newly added APKs in the release. Can take values between [0,5].
  final int? inAppUpdatePriority;

  /// References version of 'main' expansion file.
  final int? obbMainReferencesVersion;

  /// Size of 'main' expansion file in bytes.
  final int? obbMainFileSize;

  /// References version of 'patch' expansion file.
  final int? obbPatchReferencesVersion;

  /// Size of 'patch' expansion file in bytes.
  final int? obbPatchFileSize;

  /// Must be set to true if the bundle installation may trigger a warning on user devices (e.g can only be downloaded over wifi). Typically this is required for bundles over 150MB.
  final bool? ackBundleInstallationWarning;

  final bool uploadDebugSymbols;

  /// Constructor for the FastlaneAndroidPublisherArgument class.
  Arguments({
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
  }) : super("fastlane");

  factory Arguments.fromArgResults(ArgResults argResults) => Arguments(
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
        versionCodesToRetain: (argResults['version-codes-to-retain'])?.cast<int>(),
        changesNotSentForReview: (argResults['changes-not-sent-for-review'] as bool?) ?? false,
        rescueChangesNotSentForReview: (argResults['rescue-changes-not-sent-for-review'] as bool?) ?? true,
        inAppUpdatePriority: int.tryParse(argResults['in-app-update-priority'].toString()),
        obbMainReferencesVersion: int.tryParse(argResults['obb-main-references-version'].toString()),
        obbMainFileSize: int.tryParse(argResults['obb-main-file-size'].toString()),
        obbPatchReferencesVersion: int.tryParse(argResults['obb-patch-references-version'].toString()),
        obbPatchFileSize: int.tryParse(argResults['obb-patch-file-size'].toString()),
        ackBundleInstallationWarning: (argResults['ack-bundle-installation-warning'] as bool?) ?? false,
        uploadDebugSymbols: argResults['upload-debug-symbols'] ?? true,
      );

  factory Arguments.fromJson(Map<String, dynamic> json) {
    if (json['file-path'] == null) throw Exception("file-path is required");
    if (json['binary-type'] == null) throw Exception("binary-type is required");

    return Arguments(
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
      metadataPath: json['metadata-path'] ?? Files.androidDistributionMetadataDir.path,
      jsonKey: json['json-key'] ?? "distribution/fastlane.json",
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
      changesNotSentForReview: (json['changes-not-sent-for-review'] as bool?) ?? false,
      rescueChangesNotSentForReview: (json['rescue-changes-not-sent-for-review'] as bool?) ?? true,
      inAppUpdatePriority: int.tryParse(json['in-app-update-priority'].toString()) ?? 0,
      obbMainReferencesVersion: int.tryParse(json['obb-main-references-version'].toString()),
      obbMainFileSize: int.tryParse(json['obb-main-file-size'].toString()),
      obbPatchReferencesVersion: int.tryParse(json['obb-patch-references-version'].toString()),
      obbPatchFileSize: int.tryParse(json['obb-patch-file-size'].toString()),
      ackBundleInstallationWarning: (json['ack-bundle-installation-warning'] as bool?) ?? false,
      uploadDebugSymbols: json['upload-debug-symbols'] ?? true,
    );
  }

  @override
  List<String> get results {
    final mappingPathParser = (mappingPaths ?? []);

    String filePath = this.filePath;
    if (FileSystemEntity.isDirectorySync(filePath)) {
      final file = (Directory(filePath).listSync()).firstWhere((item) => item.path.endsWith(binaryType == "apk" ? ".apk" : ".aab"), orElse: () => throw Exception("No file found"));
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
      if (apkPaths != null && apkPaths!.isNotEmpty) "apk_paths:${apkPaths!.join(',')}",
      if (aab != null) "aab:$aab",
      if (aabPaths != null && aabPaths!.isNotEmpty) "aab_paths:${aabPaths!.join(',')}",
      if (skipUploadApk) "skip_upload_apk:true",
      if (skipUploadAab) "skip_upload_aab:true",
      if (skipUploadMetadata) "skip_upload_metadata:true",
      if (skipUploadChangelogs) "skip_upload_changelogs:true",
      if (skipUploadImages) "skip_upload_images:true",
      if (skipUploadScreenshots) "skip_upload_screenshots:true",
      if (syncImageUpload) "sync_image_upload:true",
      if (trackPromoteTo != null) "track_promote_to:$trackPromoteTo",
      if (trackPromoteReleaseStatus != null) "track_promote_release_status:$trackPromoteReleaseStatus",
      if (validateOnly) "validate_only:true",
      if (mapping != null) "mapping:$mapping",
      if (mappingPathParser.isNotEmpty) "mapping_paths:${mappingPathParser.join(',')}",
      if (rootUrl != null) "root_url:$rootUrl",
      if (versionCodesToRetain != null && versionCodesToRetain!.isNotEmpty) "version_codes_to_retain:${versionCodesToRetain!.join(',')}",
      if (changesNotSentForReview) "changes_not_sent_for_review:true",
      if (rescueChangesNotSentForReview) "rescue_changes_not_sent_for_review:true",
      if (inAppUpdatePriority != null) "in_app_update_priority:$inAppUpdatePriority",
      if (obbMainReferencesVersion != null) "obb_main_references_version:$obbMainReferencesVersion",
      if (obbMainFileSize != null) "obb_main_file_size:$obbMainFileSize",
      if (obbPatchReferencesVersion != null) "obb_patch_references_version:$obbPatchReferencesVersion",
      if (obbPatchFileSize != null) "obb_patch_file_size:$obbPatchFileSize",
      if (ackBundleInstallationWarning == true) "ack_bundle_installation_warning:$ackBundleInstallationWarning",
    ];
  }

  static ArgParser parser = ArgParser()
    ..addOption('file-path', abbr: 'f', help: 'Path to the file to upload.', mandatory: true)
    ..addOption('binary-type', help: 'The binary type of the application to use. Valid values are apk, aab.', defaultsTo: "apk")
    ..addOption('package-name', abbr: 'p', help: 'The package name of the application to use.', mandatory: true)
    ..addOption('version-name', help: 'Version name (used when uploading new APKs/AABs) - defaults to versionName in build.gradle or AndroidManifest.xml.')
    ..addOption('version-code', abbr: 'c', help: 'The versionCode for which to download the generated APK.')
    ..addOption('release-status', abbr: 'r', help: 'Release status (used when uploading new APKs/AABs) - valid values are completed, draft, halted, inProgress.')
    ..addOption('track', abbr: 't', help: 'The track of the application to use. The default available tracks are: production, beta, alpha, internal.')
    ..addOption('rollout', abbr: 'R', help: 'The percentage of the user fraction when uploading to the rollout track (setting to 1 will complete the rollout).')
    ..addOption('metadata-path', help: 'Path to the directory containing the metadata files.', defaultsTo: Files.androidDistributionMetadataDir.path)
    ..addOption('json-key', abbr: 'j', help: 'The path to a file containing service account JSON, used to authenticate with Google.', defaultsTo: Files.fastlaneJson.path)
    ..addOption('json-key-data', abbr: 'J', help: 'The raw service account JSON data used to authenticate with Google.')
    ..addOption('apk', abbr: 'a', help: 'Path to the APK file to upload.')
    ..addMultiOption('apk-paths', abbr: 'A', help: 'An array of paths to APK files to upload.')
    ..addOption('aab', abbr: 'b', help: 'Path to the AAB file to upload.')
    ..addMultiOption('aab-paths', abbr: 'B', help: 'An array of paths to AAB files to upload.')
    ..addFlag('skip-upload-apk', negatable: false, defaultsTo: false, help: 'Whether to skip uploading APK.')
    ..addFlag('skip-upload-aab', negatable: false, defaultsTo: false, help: 'Whether to skip uploading AAB.')
    ..addFlag('skip-upload-metadata', negatable: false, defaultsTo: false, help: 'Whether to skip uploading metadata, changelogs not included.')
    ..addFlag('skip-upload-changelogs', negatable: false, defaultsTo: false, help: 'Whether to skip uploading changelogs.')
    ..addFlag('skip-upload-images', negatable: false, defaultsTo: false, help: 'Whether to skip uploading images, screenshots not included.')
    ..addFlag('skip-upload-screenshots', negatable: false, defaultsTo: false, help: 'Whether to skip uploading screenshots.')
    ..addFlag('sync-image-upload', negatable: false, defaultsTo: false, help: 'Whether to use sha256 comparison to skip upload of images and screenshots that are already in Play Store.')
    ..addOption('track-promote-to', abbr: 'T', help: 'The track to promote to. The default available tracks are: production, beta, alpha, internal.')
    ..addOption('track-promote-release-status', abbr: 's', help: 'Promoted track release status (used when promoting a track) - valid values are completed, draft, halted, inProgress.')
    ..addFlag('validate-only', negatable: false, defaultsTo: false, help: 'Only validate changes with Google Play rather than actually publish.')
    ..addOption('mapping', abbr: 'm', help: 'Path to the mapping file to upload (mapping.txt or native-debug-symbols.zip alike).')
    ..addMultiOption('mapping-paths', abbr: 'M', help: 'An array of paths to mapping files to upload (mapping.txt or native-debug-symbols.zip alike).')
    ..addOption('root-url', abbr: 'u', help: 'Root URL for the Google Play API. The provided URL will be used for API calls in place of https://www.googleapis.com/.')
    ..addOption('timeout', defaultsTo: "300", help: 'Timeout for read, open and send (in seconds).')
    ..addMultiOption('version-codes-to-retain', abbr: 'V', help: 'An array of version codes to retain when publishing a new APK.')
    ..addFlag('changes-not-sent-for-review',
        negatable: false, defaultsTo: false, help: 'Indicates that the changes in this edit will not be reviewed until they are explicitly sent for review from the Google Play Console UI.')
    ..addFlag('rescue-changes-not-sent-for-review',
        negatable: false, defaultsTo: true, help: 'Catches changes_not_sent_for_review errors when an edit is committed and retries with the configuration that the error message recommended.')
    ..addOption('in-app-update-priority', abbr: 'I', help: 'In-app update priority for all the newly added APKs in the release. Can take values between [0,5].')
    ..addOption('obb-main-references-version', abbr: 'O', help: 'References version of main expansion file.')
    ..addOption('obb-main-file-size', abbr: 'S', help: 'Size of main expansion file in bytes.')
    ..addOption('obb-patch-references-version', abbr: 'P', help: 'References version of patch expansion file.')
    ..addOption('obb-patch-file-size', abbr: 'F', help: 'Size of patch expansion file in bytes.')
    ..addFlag('upload-debug-symbols', negatable: false, defaultsTo: true, help: 'Whether to upload debug symbols.')
    ..addFlag('ack-bundle-installation-warning',
        negatable: false,
        defaultsTo: false,
        help: 'Must be set to true if the bundle installation may trigger a warning on user devices (e.g can only be downloaded over wifi). Typically this is required for bundles over 150MB.');

  factory Arguments.defaultConfigs(String packageName) => Arguments(
        filePath: "${Files.androidDistributionOutputDir.path}/*.apk",
        metadataPath: Files.androidDistributionMetadataDir.path,
        jsonKey: Files.fastlaneJson.path,
        uploadDebugSymbols: true,
        binaryType: "apk",
      );

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
