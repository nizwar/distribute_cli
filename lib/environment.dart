import 'dart:convert';
import 'dart:io';

import 'logger.dart';

class Environment {
  static final Map<String, String> _env = {};
  bool isAndroidBuild = false;
  bool isIOSBuild = false;
  bool isAndroidDistribute = false;
  bool isIOSDistribute = false;
  String androidPackageName = '';
  String androidFirebaseAppId = '';
  String androidFirebaseGroups = '';
  String iosDistributionUser = '';
  String iosDistributionPassword = '';
  bool useFastlane = false;
  bool useFirebase = false;
  bool isVerbose = false;

  Environment(final String path) {
    _loadEnv(path);
  }

  Future<bool> get initialized async {
    final androidDir = await Directory("distribution/android").exists();
    bool initEnvironment = false;
    File distributionFile = File("dist");
    if (!await distributionFile.exists()) {
      ColorizeLogger.logError(
          'dist file not found, please run distribute init first');
      return false;
    } else {
      final distribution = await distributionFile.readAsString().then((value) {
        return jsonDecode(value);
      }).catchError((e) {
        ColorizeLogger.logError('Error while parsing dist');
        exit(1);
      });

      final checkGit = distribution["git"] ?? false; //Required
      final checkFastlane = distribution["fastlane"] ?? false; //Required
      final checkFastlaneJson =
          distribution["fastlane_json"] ?? false; //Required
      final checkXCrun = distribution["xcrun"] ?? false; //Optional

      if (Platform.isMacOS) {
        if (checkGit && checkFastlane && checkFastlaneJson && checkXCrun) {
          initEnvironment = true;
        }
      } else {
        if (checkGit && checkFastlane && checkFastlaneJson) {
          initEnvironment = true;
        }
      }
    }
    return androidDir && initEnvironment;
  }

  void _loadEnv(path) {
    final envFile = File(path);
    if (!envFile.existsSync()) {
      ColorizeLogger.logError(
          'Environment file not found: $path, please run distribute init first');
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

  void _parseEnv() {
    isAndroidBuild = _env['ANDROID_BUILD'] == 'true';
    isIOSBuild = _env['IOS_BUILD'] == 'true';
    isAndroidDistribute = _env['ANDROID_DISTRIBUTE'] == 'true';
    isIOSDistribute = _env['IOS_DISTRIBUTE'] == 'true';
    androidPackageName = _env['ANDROID_PACKAGE_NAME'] ?? '';
    androidFirebaseAppId = _env['ANDROID_FIREBASE_APP_ID'] ?? '';
    androidFirebaseGroups = _env['ANDROID_FIREBASE_GROUPS'] ?? '';
    iosDistributionUser = _env['IOS_DISTRIBUTION_USER'] ?? '';
    iosDistributionPassword = _env['IOS_DISTRIBUTION_PASSWORD'] ?? '';
    useFastlane = _env['USE_FASTLANE'] == 'true';
    useFirebase = _env['USE_FIREBASE'] == 'true';
  }

  static String examples = '''
ANDROID_BUILD=true
ANDROID_DISTRIBUTE=true
ANDROID_PACKAGE_NAME=
ANDROID_FIREBASE_APP_ID=
ANDROID_FIREBASE_GROUPS=

IOS_BUILD=true
IOS_DISTRIBUTE=true
IOS_DISTRIBUTION_USER=
IOS_DISTRIBUTION_PASSWORD=

USE_FASTLANE=true
USE_FIREBASE=false
''';

  @override
  String toString() => '''
ANDROID_BUILD=$isAndroidBuild
ANDROID_DISTRIBUTE=$isAndroidDistribute
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
