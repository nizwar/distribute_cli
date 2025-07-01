import 'package:args/args.dart';
import 'package:distribute_cli/parsers/variables.dart';

import '../../files.dart';
import '../publisher_arguments.dart';

/// Comprehensive Firebase App Distribution arguments for automated app testing.
///
/// Extends `PublisherArguments` to provide Firebase-specific configuration for
/// distributing applications to testers and testing groups. Supports advanced
/// features like release notes, tester management, and group-based distribution.
///
/// Key capabilities:
/// - Firebase App Distribution integration
/// - Individual and group tester management
/// - Release notes and documentation
/// - Email and file-based distribution lists
/// - APK and AAB binary support
/// - Automated testing workflows
///
/// Example usage:
/// ```dart
/// final args = Arguments(
///   variables,
///   filePath: '/path/to/app.apk',
///   appId: '1:123456789:android:abcdef',
///   binaryType: 'apk',
///   releaseNotes: 'New features and bug fixes',
///   groups: 'internal-qa,external-beta',
/// );
/// ```
class Arguments extends PublisherArguments {
  /// Firebase application identifier for the target app.
  ///
  /// The unique Firebase app ID that identifies your application in the
  /// Firebase console. Required for all Firebase App Distribution operations.
  /// Format: "1:PROJECT_NUMBER:PLATFORM:APP_ID"
  ///
  /// Example: "1:123456789:android:abcdef123456"
  ///
  /// Can be found in:
  /// - Firebase Console > Project Settings > General > Your apps
  /// - google-services.json file (mobilesdk_app_id)
  final String appId;

  /// Release notes text to include with the distribution.
  ///
  /// Brief description of changes, features, or fixes in this release.
  /// Displayed to testers when they receive the app update notification.
  /// Mutually exclusive with `releaseNotesFile`.
  ///
  /// Example: "Fixed login bug and added dark mode support"
  final String? releaseNotes;

  /// Path to a file containing release notes content.
  ///
  /// Points to a text file with detailed release notes for the distribution.
  /// File content is read and included in the release notification.
  /// Useful for maintaining release notes in version control.
  /// Mutually exclusive with `releaseNotes`.
  ///
  /// Example: "/path/to/release-notes.txt"
  final String? releaseNotesFile;

  /// Comma-separated list of tester email addresses.
  ///
  /// Individual email addresses of testers who should receive this
  /// distribution. Testers must be invited to the Firebase project.
  /// Mutually exclusive with `testersFile`.
  ///
  /// Example: "tester1@example.com,tester2@example.com"
  final String? testers;

  /// Path to a file containing tester email addresses.
  ///
  /// Points to a text file with comma-separated or newline-separated
  /// tester email addresses. Useful for managing large tester lists
  /// or maintaining tester lists in version control.
  /// Mutually exclusive with `testers`.
  ///
  /// File format example:
  /// ```
  /// tester1@example.com
  /// tester2@example.com,tester3@example.com
  /// ```
  final String? testersFile;

  /// Comma-separated list of tester group aliases.
  ///
  /// Group aliases that define collections of testers in Firebase Console.
  /// Groups must be created and configured in Firebase App Distribution.
  /// Mutually exclusive with `groupsFile`.
  ///
  /// Example: "qa-team,beta-users,internal-staff"
  final String? groups;

  /// Path to a file containing tester group aliases.
  ///
  /// Points to a text file with comma-separated or newline-separated
  /// group aliases. Useful for managing complex group distributions
  /// or maintaining group lists in version control.
  /// Mutually exclusive with `groups`.
  ///
  /// File format example:
  /// ```
  /// qa-team
  /// beta-users,internal-staff
  /// ```
  final String? groupsFile;

  /// Creates a new Firebase App Distribution arguments instance.
  ///
  /// Initializes Firebase-specific configuration for automated app distribution
  /// to testers and testing groups. Requires core Firebase parameters and
  /// distribution settings.
  ///
  /// Required parameters:
  /// - `variables` - System and environment variables
  /// - `filePath` - Path to the APK/AAB file to distribute
  /// - `appId` - Firebase application identifier
  /// - `binaryType` - Type of binary file (apk/aab)
  ///
  /// Example:
  /// ```dart
  /// final args = Arguments(
  ///   variables,
  ///   filePath: '/path/to/app.apk',
  ///   appId: '1:123456789:android:abcdef',
  ///   binaryType: 'apk',
  ///   releaseNotes: 'Latest beta with new features',
  ///   groups: 'beta-testers,internal-qa',
  /// );
  /// ```
  Arguments(
    Variables variables, {
    required super.filePath,
    required this.appId,
    required super.binaryType,
    this.releaseNotes,
    this.releaseNotesFile,
    this.testers,
    this.testersFile,
    this.groups,
    this.groupsFile,
  }) : super('firebase', variables);

  /// Creates Arguments instance from command-line arguments.
  ///
  /// Parses command-line arguments and optional global results to create
  /// a fully configured Firebase Arguments instance. Handles validation
  /// and type conversion for all Firebase-specific parameters.
  ///
  /// Parameters:
  /// - `results` - Parsed command-line arguments
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns configured Arguments instance with parsed values.
  ///
  /// Uses first rest argument as file path if available, otherwise
  /// defaults to standard Android distribution output directory.
  factory Arguments.fromArgResults(
          ArgResults results, ArgResults? globalResults) =>
      Arguments(
        Variables.fromSystem(globalResults),
        filePath:
            results.rest.firstOrNull ?? Files.androidDistributionOutputDir.path,
        binaryType: results['binary-type'] as String,
        appId: results['app-id'] as String,
        releaseNotes: results['release-notes'] as String?,
        releaseNotesFile: results['release-notes-file'] as String?,
        testers: results['testers'] as String?,
        testersFile: results['testers-file'] as String?,
        groups: results['groups'] as String?,
        groupsFile: results['groups-file'] as String?,
      );

  /// Creates Arguments instance from JSON configuration.
  ///
  /// Deserializes JSON configuration data to create a Firebase Arguments
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
  /// - "app-id" is required
  /// - "binary-type" is required
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "file-path": "/path/to/app.apk",
  ///   "app-id": "1:123456789:android:abcdef",
  ///   "binary-type": "apk",
  ///   "release-notes": "Bug fixes and improvements",
  ///   "groups": "qa-team,beta-users"
  /// }
  /// ```
  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    if (json['file-path'] == null) throw Exception("file-path is required");
    if (json['app-id'] == null) throw Exception("app-id is required");
    if (json['binary-type'] == null) throw Exception("binary-type is required");
    return Arguments(
      variables,
      filePath: json["file-path"] as String,
      appId: json['app-id'] as String,
      binaryType: json['binary-type'] as String,
      releaseNotes: json['release-notes'] as String?,
      releaseNotesFile: json['release-notes-file'] as String?,
      testers: json['testers'] as String?,
      testersFile: json['testers-file'] as String?,
      groups: json['groups'] as String?,
      groupsFile: json['groups-file'] as String?,
    );
  }

  /// Builds the Firebase CLI command arguments list.
  ///
  /// Constructs the complete command-line arguments for the Firebase CLI
  /// `appdistribution:distribute` command. Formats all parameters according
  /// to Firebase CLI expectations and includes conditional arguments.
  ///
  /// Key behavior:
  /// - Uses Firebase CLI distribution command format
  /// - Includes file path and app ID as primary arguments
  /// - Adds optional parameters when configured
  /// - Handles mutual exclusivity of file vs inline options
  ///
  /// Returns list of formatted Firebase CLI command arguments.
  ///
  /// Example output:
  /// ```
  /// ["appdistribution:distribute", "/path/to/app.apk", "--app",
  ///  "1:123456789:android:abcdef", "--groups=qa-team,beta-users"]
  /// ```
  @override
  List<String> get argumentBuilder => [
        'appdistribution:distribute',
        filePath,
        '--app',
        appId,
        if (releaseNotes != null) '--release-notes=$releaseNotes',
        if (releaseNotesFile != null) '--release-notes-file=$releaseNotesFile',
        if (testers != null) '--testers=$testers',
        if (testersFile != null) '--testers-file=$testersFile',
        if (groups != null) '--groups=$groups',
        if (groupsFile != null) '--groups-file=$groupsFile',
      ];

  /// Command-line argument parser for Firebase App Distribution.
  ///
  /// Defines all supported command-line options for the Firebase publisher
  /// with their descriptions, types, defaults, and validation rules.
  /// Used for parsing user input and generating help documentation.
  ///
  /// Includes comprehensive options for:
  /// - File paths and binary types
  /// - Firebase app identification
  /// - Release notes and documentation
  /// - Tester and group management
  /// - Distribution configuration
  static ArgParser parser = ArgParser()
    ..addOption('file-path',
        abbr: 'f', help: 'Path to the file to upload', mandatory: true)
    ..addOption('binary-type',
        abbr: 'b',
        help:
            'The binary type of the application to use. Valid values are apk, aab.',
        defaultsTo: 'apk')
    ..addOption('app-id',
        abbr: 'a', help: 'The app id of your Firebase app', mandatory: true)
    ..addOption('release-notes', abbr: 'r', help: 'Release notes to include')
    ..addOption('release-notes-file', help: 'Path to file with release notes')
    ..addOption('testers',
        abbr: 't',
        help: 'A comma-separated list of tester emails to distribute to')
    ..addOption('testers-file',
        abbr: 'T',
        help:
            'Path to file with a comma- or newline-separated list of tester emails to distribute to')
    ..addOption('groups',
        abbr: 'g',
        help: 'A comma-separated list of group aliases to distribute to')
    ..addOption('groups-file',
        abbr: 'G',
        help:
            'Path to file with a comma- or newline-separated list of group aliases to distribute to');

  /// Creates default Firebase configuration for an app.
  ///
  /// Generates a basic Firebase Arguments instance with default settings
  /// suitable for most Firebase App Distribution scenarios. Uses standard
  /// paths and common configuration values.
  ///
  /// Parameters:
  /// - `appId` - Firebase application identifier
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns Arguments instance with default configuration:
  /// - APK binary type
  /// - Standard Android distribution output directory
  /// - No release notes or tester specifications
  ///
  /// Useful for quick setup and basic distribution workflows.
  factory Arguments.defaultConfigs(String appId, ArgResults? globalResults) =>
      Arguments(
        Variables.fromSystem(globalResults),
        filePath: Files.androidDistributionOutputDir.path,
        appId: appId,
        binaryType: 'apk',
      );

  /// Serializes Arguments instance to JSON format.
  ///
  /// Converts all configuration parameters to a JSON-serializable map
  /// for storage, transmission, or configuration file generation.
  /// Preserves all parameter values including optional configurations.
  ///
  /// Returns map containing all configuration parameters with their
  /// current values. Null values are preserved for proper deserialization
  /// and configuration completeness.
  ///
  /// Example output:
  /// ```json
  /// {
  ///   "file-path": "/path/to/app.apk",
  ///   "app-id": "1:123456789:android:abcdef",
  ///   "binary-type": "apk",
  ///   "release-notes": "Bug fixes and improvements",
  ///   "groups": "qa-team,beta-users"
  /// }
  /// ```
  @override
  Map<String, dynamic> toJson() => {
        'file-path': filePath,
        'app-id': appId,
        'binary-type': binaryType,
        'release-notes': releaseNotes,
        'release-notes-file': releaseNotesFile,
        'testers': testers,
        'testers-file': testersFile,
        'groups': groups,
        'groups-file': groupsFile,
      };
}
