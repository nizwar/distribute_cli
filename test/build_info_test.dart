import 'dart:io';

import 'package:distribute_cli/parsers/build_info.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory previousCwd;

  setUp(() {
    previousCwd = Directory.current;
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_buildinfo');
    Directory.current = sandbox;
    BuildInfo.androidPackageName = null;
    BuildInfo.iosBundleId = null;
  });

  tearDown(() {
    Directory.current = previousCwd;
    sandbox.deleteSync(recursive: true);
  });

  /// Writes [contents] to a path inside the sandbox.
  void write(String relative, String contents) {
    final file = File(path.join(sandbox.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  /// Builds a pbxproj whose bundle identifier entries appear in [order].
  String pbxproj(List<String> order) {
    final buffer = StringBuffer('// !\$*UTF8*\$!\n{\n');
    for (final value in order) {
      buffer.writeln('\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $value;');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  group('android applicationId', () {
    test('reads the groovy form', () async {
      write('android/app/build.gradle', 'applicationId "com.example.app"');
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.androidPackageName, 'com.example.app');
    });

    test('reads the kotlin dsl form', () async {
      write(
        'android/app/build.gradle.kts',
        'applicationId = "com.example.kts"',
      );
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.androidPackageName, 'com.example.kts');
    });
  });

  group('ios bundle identifier', () {
    test('reads the app target', () async {
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        pbxproj(['com.example.app', 'com.example.app.RunnerTests']),
      );
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.iosBundleId, 'com.example.app');
    });

    test('skips the test target even when it is listed first', () async {
      // Xcode rewrites this file freely; the app target is not guaranteed to
      // come first, and picking RunnerTests would upload under the wrong id.
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        pbxproj(['com.example.app.RunnerTests', 'com.example.app']),
      );
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.iosBundleId, 'com.example.app');
    });

    test('strips surrounding quotes', () async {
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        pbxproj(['"com.example.quoted"']),
      );
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.iosBundleId, 'com.example.quoted');
    });

    test('ignores an unresolved Xcode build setting', () async {
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        pbxproj([r'"$(APP_BUNDLE_ID)"', 'com.example.real']),
      );
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.iosBundleId, 'com.example.real');
    });

    test('leaves the id null when only test targets are present', () async {
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        pbxproj(['com.example.app.RunnerTests']),
      );
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.iosBundleId, isNull);
    });

    test('leaves the id null when the project has no ios directory', () async {
      await BuildInfo.applyBuildInfo();
      expect(BuildInfo.iosBundleId, isNull);
    });
  });
}
