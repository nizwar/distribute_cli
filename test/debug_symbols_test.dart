import 'dart:io';

import 'package:distribute_cli/app_builder/build_arguments.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  _variantSelection();

  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_symbols');
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  /// Creates a Gradle-style merged_native_libs layout under the sandbox.
  void seedVariant(String variant, {String? task}) {
    final segments = [
      'build',
      'app',
      'intermediates',
      'merged_native_libs',
      variant,
      if (task != null) task,
      'out',
      'lib',
      'arm64-v8a',
    ];
    Directory(path.join(sandbox.path, path.joinAll(segments)))
        .createSync(recursive: true);
  }

  Directory? find({required String mode, String? flavor}) =>
      BuildArguments.findNativeSymbolsDirectory(
        mode: mode,
        flavor: flavor,
        root: sandbox,
      );

  test('finds the flavorless release layout', () {
    seedVariant('release', task: 'mergeReleaseNativeLibs');

    final result = find(mode: 'release');
    expect(result, isNotNull);
    expect(path.basename(result!.path), 'lib');
    expect(result.path, contains('mergeReleaseNativeLibs'));
  });

  test('finds a flavored variant, which the hardcoded path never did', () {
    // Gradle names the directory after the variant: `prodRelease`, not
    // `release`, with a matching `mergeProdReleaseNativeLibs` task.
    seedVariant('prodRelease', task: 'mergeProdReleaseNativeLibs');

    final result = find(mode: 'release', flavor: 'prod');
    expect(result, isNotNull);
    expect(result!.path, contains('prodRelease'));
  });

  test('supports the older layout without a task subdirectory', () {
    seedVariant('release');

    expect(find(mode: 'release'), isNotNull);
  });

  test('prefers the flavored variant over a leftover flavorless one', () {
    seedVariant('release', task: 'mergeReleaseNativeLibs');
    seedVariant('prodRelease', task: 'mergeProdReleaseNativeLibs');

    final result = find(mode: 'release', flavor: 'prod');
    expect(result!.path, contains('prodRelease'));
  });

  test('does not return a variant of a different flavor', () {
    seedVariant('devRelease', task: 'mergeDevReleaseNativeLibs');

    expect(find(mode: 'release', flavor: 'prod'), isNull);
  });

  test('does not return a variant of a different build mode', () {
    seedVariant('debug', task: 'mergeDebugNativeLibs');

    expect(find(mode: 'release'), isNull);
  });

  test('returns null when the project has never been built', () {
    expect(find(mode: 'release'), isNull);
  });

  test('returns null when the variant directory holds no out/lib', () {
    Directory(
      path.join(
        sandbox.path,
        'build',
        'app',
        'intermediates',
        'merged_native_libs',
        'release',
      ),
    ).createSync(recursive: true);

    expect(find(mode: 'release'), isNull);
  });
}

/// The variant picker used substring matching plus longest-name-wins, which
/// selected the wrong flavor and could promote a debug variant to release.
void _variantSelection() {
  late Directory sandbox;

  setUp(() =>
      sandbox = Directory.systemTemp.createTempSync('distribute_cli_variant'));
  tearDown(() => sandbox.deleteSync(recursive: true));

  void makeVariant(String name) {
    Directory(
      [
        sandbox.path, 'build', 'app', 'intermediates', 'merged_native_libs', //
        name, 'merge${name[0].toUpperCase()}${name.substring(1)}NativeLibs',
        'out', 'lib', 'arm64-v8a',
      ].join(Platform.pathSeparator),
    ).createSync(recursive: true);
  }

  String? pick({required String mode, String? flavor}) =>
      BuildArguments.findNativeSymbolsDirectory(
        mode: mode,
        flavor: flavor,
        root: sandbox,
      )?.path;

  group('findNativeSymbolsDirectory', () {
    test('an exact flavor match wins over a longer one', () {
      makeVariant('devRelease');
      makeVariant('devQaRelease');

      expect(pick(mode: 'release', flavor: 'dev'), contains('devRelease'));
    });

    test('the order the directories are listed in does not matter', () {
      makeVariant('devQaRelease');
      makeVariant('devRelease');

      expect(pick(mode: 'release', flavor: 'dev'), contains('devRelease'));
    });

    test('a flavourless build prefers the plain mode directory', () {
      makeVariant('release');
      makeVariant('prodRelease');

      final picked = pick(mode: 'release');
      expect(picked,
          contains('merged_native_libs${Platform.pathSeparator}release'));
    });

    test('a debug variant is never chosen for a release build', () {
      // `debugRelease`.contains('release') was true, and it is longer.
      makeVariant('release');
      makeVariant('debugRelease');

      expect(pick(mode: 'release'), isNot(contains('debugRelease')));
    });

    test('an unusual variant name is still found by the loose fallback', () {
      makeVariant('prodReleaseFoo');

      expect(pick(mode: 'release', flavor: 'prod'), contains('prodReleaseFoo'));
    });

    test('nothing matching yields null', () {
      makeVariant('debug');

      expect(pick(mode: 'release', flavor: 'nope'), isNull);
    });
  });
}
