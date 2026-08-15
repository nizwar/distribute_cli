import 'dart:io';

import 'package:distribute_cli/files.dart';
import 'package:distribute_cli/logger.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  _artifactSafety();

  late Directory sandbox;
  late String source;
  late String target;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_files');
    source = path.join(sandbox.path, 'build');
    target = path.join(sandbox.path, 'out');
    Directory(source).createSync(recursive: true);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  /// Creates a file under [source], optionally back-dating it.
  File seed(String relative, {Duration? age}) {
    final file = File(path.join(source, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(relative);
    if (age != null) {
      file.setLastModifiedSync(DateTime.now().subtract(age));
    }
    return file;
  }

  List<String> targetFiles() => Directory(target).existsSync()
      ? (Directory(target)
          .listSync()
          .whereType<File>()
          .map(
            (file) => path.basename(file.path),
          )
          .toList()
        ..sort())
      : <String>[];

  group('copyFiles', () {
    test('copies a matching artifact into the target directory', () async {
      seed('app-release.apk');

      final result = await Files.copyFiles(source, target, fileType: ['apk']);

      expect(result, isNotNull);
      expect(targetFiles(), ['app-release.apk']);
    });

    test('creates the target directory when it does not exist', () async {
      seed('app-release.apk');
      expect(Directory(target).existsSync(), isFalse);

      await Files.copyFiles(source, target, fileType: ['apk']);

      expect(Directory(target).existsSync(), isTrue);
    });

    test('filters by extension', () async {
      seed('app-release.apk');
      seed('mapping.txt');

      await Files.copyFiles(source, target, fileType: ['apk']);

      expect(targetFiles(), ['app-release.apk']);
    });

    test('throws when the source directory is missing', () {
      expect(
        () => Files.copyFiles(
          path.join(sandbox.path, 'nope'),
          target,
          fileType: ['apk'],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when nothing matches the requested type', () {
      seed('notes.txt');

      expect(
        () => Files.copyFiles(source, target, fileType: ['apk']),
        throwsA(isA<Exception>()),
      );
    });

    test('returns the best scoring artifact, not an arbitrary one', () async {
      // A stale debug build sitting next to a fresh release build is the
      // common case after switching build modes.
      seed('debug/app-debug.apk', age: const Duration(hours: 1));
      seed('release/app-release.apk');

      final result = await Files.copyFiles(
        source,
        target,
        fileType: ['apk'],
        mode: 'release',
      );

      expect(path.basename(result!), 'app-release.apk');
    });

    test('prefers the requested flavor', () async {
      seed('release/app-prod-release.apk');
      seed('release/app-dev-release.apk');

      final result = await Files.copyFiles(
        source,
        target,
        fileType: ['apk'],
        mode: 'release',
        flavor: 'prod',
      );

      expect(path.basename(result!), 'app-prod-release.apk');
    });

    test('does not carry artifacts of another build mode into the output',
        () async {
      // Publishing scans the output directory, so a debug binary left there is
      // a binary that can reach the store.
      seed('debug/app-debug.apk', age: const Duration(hours: 1));
      seed('release/app-release.apk');

      await Files.copyFiles(
        source,
        target,
        fileType: ['apk'],
        mode: 'release',
      );

      expect(targetFiles(), ['app-release.apk']);
    });

    test('keeps every split-per-abi artifact of the requested mode', () async {
      seed('release/app-arm64-v8a-release.apk');
      seed('release/app-armeabi-v7a-release.apk');
      seed('release/app-x86_64-release.apk');

      await Files.copyFiles(
        source,
        target,
        fileType: ['apk'],
        mode: 'release',
      );

      expect(targetFiles(), hasLength(3));
    });

    test('replaces a stale file already present in the target', () async {
      Directory(target).createSync(recursive: true);
      File(path.join(target, 'app-release.apk')).writeAsStringSync('old');
      seed('release/app-release.apk');

      await Files.copyFiles(source, target, fileType: ['apk'], mode: 'release');

      expect(
        File(path.join(target, 'app-release.apk')).readAsStringSync(),
        'release/app-release.apk',
      );
    });

    test('prunes an artifact left by an earlier, different build', () async {
      // Publishers scan the whole directory, so a leftover from a previous run
      // is still a binary that can be uploaded.
      Directory(target).createSync(recursive: true);
      File(path.join(target, 'app-debug.apk')).writeAsStringSync('old debug');
      seed('release/app-release.apk');

      await Files.copyFiles(source, target, fileType: ['apk'], mode: 'release');

      expect(targetFiles(), ['app-release.apk']);
    });

    test('never touches files of an unrelated type in the target', () async {
      Directory(target).createSync(recursive: true);
      File(path.join(target, 'changelogs.log')).writeAsStringSync('keep me');
      File(path.join(target, 'debug_symbols.zip')).writeAsStringSync('keep me');
      seed('release/app-release.apk');

      await Files.copyFiles(source, target, fileType: ['apk'], mode: 'release');

      expect(
        Directory(target)
            .listSync()
            .whereType<File>()
            .map((file) => path.basename(file.path)),
        containsAll(['changelogs.log', 'debug_symbols.zip']),
      );
    });
  });
}

/// Cover for the two ways `copyFiles` used to ship the wrong binary.
void _artifactSafety() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_artifacts');
    ColorizeLogger.logFilePath = '';
    ColorizeLogger.verbosity = LogVerbosity.silent;
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  String make(String relative) {
    final file = File('${sandbox.path}${Platform.pathSeparator}$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('binary');
    return file.path;
  }

  group('build mode', () {
    test('a lone debug artifact is refused, not promoted', () async {
      // A publish run after a plain `flutter run` used to copy app-debug.apk
      // into the release output directory and upload it.
      make('build/app/outputs/flutter-apk/app-debug.apk');

      expect(
        Files.copyFiles(
          '${sandbox.path}/build',
          '${sandbox.path}/out',
          fileType: const ['apk'],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not a release build'),
          ),
        ),
      );
    });

    test('the release artifact still wins when both are present', () async {
      make('build/app/outputs/flutter-apk/app-debug.apk');
      make('build/app/outputs/flutter-apk/app-release.apk');

      final copied = await Files.copyFiles(
        '${sandbox.path}/build',
        '${sandbox.path}/out',
        fileType: const ['apk'],
      );

      expect(copied, endsWith('app-release.apk'));
      expect(
        Directory('${sandbox.path}/out')
            .listSync()
            .map((e) => e.path.split(Platform.pathSeparator).last),
        ['app-release.apk'],
      );
    });

    test('an explicit debug mode selects the debug artifact', () async {
      make('build/app/outputs/flutter-apk/app-debug.apk');
      make('build/app/outputs/flutter-apk/app-release.apk');

      final copied = await Files.copyFiles(
        '${sandbox.path}/build',
        '${sandbox.path}/out',
        fileType: const ['apk'],
        mode: 'debug',
      );

      expect(copied, endsWith('app-debug.apk'));
    });

    test('an unlabelled artifact is still accepted', () async {
      // Custom build systems do not always encode the mode in the name.
      make('build/out/myapp.apk');

      final copied = await Files.copyFiles(
        '${sandbox.path}/build',
        '${sandbox.path}/out2',
        fileType: const ['apk'],
      );

      expect(copied, endsWith('myapp.apk'));
    });
  });

  group('copying onto itself', () {
    test('an output directory equal to the source keeps the file', () async {
      // Deleting the target and then copying from it destroyed the artifact.
      final source = make('build/app/outputs/flutter-apk/app-release.apk');
      final directory = File(source).parent.path;

      final copied = await Files.copyFiles(
        directory,
        directory,
        fileType: const ['apk'],
      );

      expect(File(source).existsSync(), isTrue);
      expect(copied, endsWith('app-release.apk'));
    });

    test('the same directory written a different way also keeps it', () async {
      final source = make('build/app/outputs/flutter-apk/app-release.apk');
      final directory = File(source).parent.path;

      await Files.copyFiles(
        directory,
        '$directory${Platform.pathSeparator}..${Platform.pathSeparator}'
        'flutter-apk',
        fileType: const ['apk'],
      );

      expect(File(source).existsSync(), isTrue);
    });
  });
}
