import 'dart:io';
import 'package:path/path.dart' as path;

/// A utility class for extracting build information from Flutter project files.
///
/// The `BuildInfo` class automatically detects and extracts package names,
/// bundle identifiers, and app names from various platform-specific configuration files.
/// This information is used throughout the distribution process to identify applications
/// across different platforms.
class BuildInfo {
  /// The Android application ID extracted from `android/app/build.gradle`
  ///
  /// Example: "com.example.myapp"
  static String? androidPackageName;

  /// The iOS bundle identifier extracted from `ios/Runner.xcodeproj/project.pbxproj`
  ///
  /// Example: "com.example.myapp"
  static String? iosBundleId;

  /// The web application name extracted from `web/index.html` title tag
  ///
  /// Example: "My Flutter App"
  static String? webAppName;

  /// The macOS bundle identifier extracted from `macos/Runner.xcodeproj/project.pbxproj`
  ///
  /// Example: "com.example.myapp"
  static String? macOSBundleId;

  /// The Windows package name extracted from `windows/runner/Runner.rc`
  ///
  /// Contains version information in the format "1,0,0,1"
  static String? windowsPackageName;

  /// The Linux package name extracted from `linux/CMakeLists.txt`
  ///
  /// Example: "my_flutter_app"
  static String? linuxPackageName;

  /// Extracts build information from all supported Flutter platforms.
  ///
  /// This method scans the project directory for platform-specific configuration files
  /// and extracts relevant build information such as package names and bundle identifiers.
  ///
  /// Supported platforms and their configuration files:
  /// - Android: `android/app/build.gradle` - Extracts `applicationId`
  /// - iOS: `ios/Runner.xcodeproj/project.pbxproj` - Extracts `PRODUCT_BUNDLE_IDENTIFIER`
  /// - Web: `web/index.html` - Extracts app name from `<title>` tag
  /// - macOS: `macos/Runner.xcodeproj/project.pbxproj` - Extracts `PRODUCT_BUNDLE_IDENTIFIER`
  /// - Windows: `windows/runner/Runner.rc` - Extracts `FILEVERSION`
  /// - Linux: `linux/CMakeLists.txt` - Extracts `PROJECT_NAME`
  ///
  /// Returns a map containing all extracted build information with the following keys:
  /// - `androidPackageName` - Android application ID
  /// - `iosBundleId` - iOS bundle identifier
  /// - `webAppName` - Web application name
  /// - `macOSBundleId` - macOS bundle identifier
  /// - `windowsPackageName` - Windows version information
  /// - `linuxPackageName` - Linux project name
  static Future<Map<String, dynamic>> applyBuildInfo() async {
    if ((Directory("android").existsSync())) {
      final androidFile = File(path.join("android", "app", "build.gradle"));

      if (androidFile.existsSync()) {
        final content = await androidFile.readAsString();
        final packageNameMatch =
            RegExp(r'applicationId\s+"([^"]+)"').firstMatch(content) ??
                RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(content);
        if (packageNameMatch != null) {
          androidPackageName = packageNameMatch.group(1);
        }
      }
    }
    if ((Directory("ios").existsSync())) {
      final iosFile =
          File(path.join("ios", "Runner.xcodeproj", "project.pbxproj"));
      if (iosFile.existsSync()) {
        final content = await iosFile.readAsString();
        final bundleIdMatch =
            RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
                .firstMatch(content);
        if (bundleIdMatch != null) {
          iosBundleId = bundleIdMatch.group(1);
        }
      }
    }
    if ((Directory("web").existsSync())) {
      final webFile = File(path.join("web", "index.html"));
      if (webFile.existsSync()) {
        final content = await webFile.readAsString();
        final appNameMatch =
            RegExp(r'<title\s*>([^<]+)</title\s*>', caseSensitive: false)
                .firstMatch(content);
        if (appNameMatch != null) {
          webAppName = appNameMatch.group(1);
        }
      }
    }
    if ((Directory("macos").existsSync())) {
      final macOSFile =
          File(path.join("macos", "Runner.xcodeproj", "project.pbxproj"));
      if (macOSFile.existsSync()) {
        final content = await macOSFile.readAsString();
        final bundleIdMatch =
            RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
                .firstMatch(content);
        if (bundleIdMatch != null) {
          macOSBundleId = bundleIdMatch.group(1);
        }
      }
    }
    if ((Directory("windows").existsSync())) {
      final windowsFile = File(path.join("windows", "runner", "Runner.rc"));
      if (windowsFile.existsSync()) {
        final content = await windowsFile.readAsString();
        final packageNameMatch =
            RegExp(r'FILEVERSION\s+(\d+),\s*(\d+),\s*(\d+),\s*(\d+)')
                .firstMatch(content);
        if (packageNameMatch != null) {
          windowsPackageName = packageNameMatch.group(0);
        }
      }
    }
    if ((Directory("linux").existsSync())) {
      final linuxFile = File(path.join("linux", "CMakeLists.txt"));
      if (linuxFile.existsSync()) {
        final content = await linuxFile.readAsString();
        final packageNameMatch =
            RegExp(r'set\(PROJECT_NAME\s+"([^"]+)"\)').firstMatch(content);
        if (packageNameMatch != null) {
          linuxPackageName = packageNameMatch.group(1);
        }
      }
    }

    return {
      "androidPackageName": androidPackageName,
      "iosBundleId": iosBundleId,
      "webAppName": webAppName,
      "macOSBundleId": macOSBundleId,
      "windowsPackageName": windowsPackageName,
      "linuxPackageName": linuxPackageName,
    };
  }

  /// Gets the current build information as a map.
  ///
  /// This getter provides access to all the extracted build information
  /// in a convenient map format.
  ///
  /// Returns a map with the following keys:
  /// - `androidPackageName` - Android application ID
  /// - `iosBundleId` - iOS bundle identifier
  /// - `webAppName` - Web application name
  /// - `macOSBundleId` - macOS bundle identifier
  /// - `windowsPackageName` - Windows version information
  /// - `linuxPackageName` - Linux project name
  Map<String, String?> get buildInfo {
    return {
      "androidPackageName": androidPackageName,
      "iosBundleId": iosBundleId,
      "webAppName": webAppName,
      "macOSBundleId": macOSBundleId,
      "windowsPackageName": windowsPackageName,
      "linuxPackageName": linuxPackageName,
    };
  }
}
