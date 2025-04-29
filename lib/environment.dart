import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'logger.dart';

/// Represents the environment configuration for the distribution process.
///
/// The `Environment` class loads configuration from a `.env` file and provides
/// access to various settings, such as build flags, Firebase credentials, and
/// Fastlane configuration. It also validates the environment setup.
///
/// Example usage:
/// ```
/// final environment = Environment.fromArgResults(argResults);
/// if (environment.isAndroidBuild) {
///   print("Android build is enabled.");
/// }
/// ```
class Environment {
  /// The environment variables for the distribution process.
  DistributionInitResult? distributionInitResult;

  /// Stores environment variables loaded from the configuration file.
  static final Map<String, String> _env = {};

  /// Indicates if Android builds are enabled.
  bool isAndroidBuild = false;

  /// Indicates if iOS builds are enabled.
  bool isIOSBuild = false;

  /// Indicates if Android distribution is enabled.
  bool isAndroidDistribute = false;

  /// Indicates if iOS distribution is enabled.
  bool isIOSDistribute = false;

  /// The Android package name.
  String androidPackageName = '';

  /// The Firebase App ID for Android.
  String androidFirebaseAppId = '';

  /// The Firebase groups for Android distribution.
  String androidFirebaseGroups = '';

  /// The iOS distribution user.
  String iosDistributionUser = '';

  /// The iOS distribution password.
  String iosDistributionPassword = '';

  /// Indicates if Fastlane is used for distribution.
  bool useFastlane = false;

  /// Indicates if Firebase is used for distribution.
  bool useFirebase = false;

  /// Indicates if verbose logging is enabled.
  bool isVerbose = false;

  /// The Android Play Store mode (e.g., internal, alpha, beta, production).
  String androidPlaystoreTrack = 'internal';
  String androidPlaystoreTrackPromoteTo = 'production';

  /// The path to the configuration file.
  late String configPath;

  Environment() {
    distributionInitResult = DistributionInitResult.instance();
  }

  /// Creates an `Environment` instance from the provided [argResults].
  static Environment fromArgResults(ArgResults? argResults) {
    final configPath = argResults?['config_path'] as String? ?? ".distribution.env";
    final configFile = File(configPath);
    final isVerbose = argResults?['verbose'] as bool? ?? false;
    if (!configFile.existsSync()) {
      configFile.createSync();
      ColorizeLogger.logDebug('Configuration file created at ${configFile.path}');
    }

    if ((configFile.readAsStringSync()).isEmpty) {
      configFile.writeAsStringSync(Environment.examples);
    }
    final environment = fromFile(configFile);
    environment.isVerbose = isVerbose;
    environment.configPath = configPath;
    return environment;
  }

  /// Creates an `Environment` instance from the specified [file].
  static Environment fromFile(File file) {
    final output = Environment();
    output._loadEnv(file.path);

    return output;
  }

  /// Checks if the environment is fully initialized.
  Future<bool> get initialized async {
    return distributionInitResult != null && _env.isNotEmpty;
  }

  /// Loads environment variables from the specified [path].
  void _loadEnv(path) {
    final envFile = File(path);
    if (!envFile.existsSync()) {
      ColorizeLogger.logError('Environment file not found: $path, please run distribute init first');
      exit(1);
    }
    final env = envFile.readAsStringSync();
    final lines = env.split('\n');
    for (var line in lines) {
      if (line.isNotEmpty && !line.startsWith('#')) {
        final parts = line.split('=');
        if (parts.length == 2) {
          _env[parts[0].trim()] = parts[1].trim();
        }
      }
    }
    _parseEnv();
  }

  /// Parses the loaded environment variables.
  void _parseEnv() {
    isAndroidBuild = _env['ANDROID_BUILD'] == 'true';
    isIOSBuild = _env['IOS_BUILD'] == 'true';
    isAndroidDistribute = _env['ANDROID_DISTRIBUTE'] == 'true';
    isIOSDistribute = _env['IOS_DISTRIBUTE'] == 'true';
    androidPackageName = _env['ANDROID_PACKAGE_NAME'] ?? '';
    androidFirebaseAppId = _env['ANDROID_FIREBASE_APP_ID'] ?? '';
    androidFirebaseGroups = _env['ANDROID_FIREBASE_GROUPS'] ?? '';
    androidPlaystoreTrack = _env['ANDROID_PLAYSTORE_TRACK'] ?? 'internal';
    androidPlaystoreTrackPromoteTo = _env['ANDROID_PLAYSTORE_TRACK_PROMOTE_TO'] ?? 'production';
    iosDistributionUser = _env['IOS_DISTRIBUTION_USER'] ?? '';
    iosDistributionPassword = _env['IOS_DISTRIBUTION_PASSWORD'] ?? '';
    useFastlane = _env['USE_FASTLANE'] == 'true';
    useFirebase = _env['USE_FIREBASE'] == 'true';
  }

  static String examples = '''
ANDROID_BUILD=true
ANDROID_DISTRIBUTE=true
ANDROID_PLAYSTORE_TRACK=internal
ANDROID_PLAYSTORE_TRACK_PROMOTE_TO=production
ANDROID_PACKAGE_NAME=
ANDROID_FIREBASE_APP_ID=
ANDROID_FIREBASE_GROUPS=
ANDROID_PLAYSTORE_MODE=internal

IOS_BUILD=true
IOS_DISTRIBUTE=true
IOS_DISTRIBUTION_USER=
IOS_DISTRIBUTION_PASSWORD=

USE_FASTLANE=true
USE_FIREBASE=false
''';

  @override

  /// Returns a string representation of the environment configuration.
  String toString() => '''
ANDROID_BUILD=$isAndroidBuild
ANDROID_DISTRIBUTE=$isAndroidDistribute
ANDROID_PLAYSTORE_TRACK=$androidPlaystoreTrack
ANDROID_PLAYSTORE_TRACK_PROMOTE_TO=$androidPlaystoreTrack
ANDROID_PACKAGE_NAME=$androidPackageName
ANDROID_FIREBASE_APP_ID=$androidFirebaseAppId
ANDROID_FIREBASE_GROUPS=$androidFirebaseGroups

IOS_BUILD=$isIOSBuild
IOS_DISTRIBUTE=$isIOSDistribute
IOS_DISTRIBUTION_USER=$iosDistributionUser
IOS_DISTRIBUTION_PASSWORD=$iosDistributionPassword

USE_FASTLANE=$useFastlane
USE_FIREBASE=$useFirebase
  ''';
}

class DistributionInitResult {
  bool git;
  bool fastlane;
  bool fastlaneJson;
  bool xcrun;

  DistributionInitResult({
    required this.git,
    required this.fastlane,
    required this.fastlaneJson,
    required this.xcrun,
  });

  factory DistributionInitResult.fromJson(Map<String, dynamic> json) {
    return DistributionInitResult(
      git: json['git'] ?? false,
      fastlane: json['fastlane'] ?? false,
      fastlaneJson: json['fastlane_json'] ?? false,
      xcrun: json['xcrun'] ?? false,
    );
  }

  static DistributionInitResult? instance() {
    final dist = File("dist");
    if (!dist.existsSync()) return null;
    try {
      return DistributionInitResult.fromJson(jsonDecode(dist.readAsStringSync()));
    } catch (_) {}
    return null;
  }

  static DistributionInitResult empty() {
    return DistributionInitResult(
      git: false,
      fastlane: false,
      fastlaneJson: false,
      xcrun: false,
    );
  }

  @override
  String toString() {
    return 'DistributionInitResult(git: $git, fastlane: $fastlane, fastlaneJson: $fastlaneJson, xcrun: $xcrun)';
  }
}
