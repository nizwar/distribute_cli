import 'dart:io';
import 'package:path/path.dart' as path;

class BuildInfo {
  static String? androidPackageName;
  static String? iosBundleId;
  static String? webAppName;
  static String? macOSBundleId;
  static String? windowsPackageName;
  static String? linuxPackageName;
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
