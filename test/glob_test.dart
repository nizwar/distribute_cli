import 'dart:io';

import 'package:distribute_cli/files.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() => sandbox = Directory.systemTemp.createTempSync('distribute_glob'));
  tearDown(() => sandbox.deleteSync(recursive: true));

  /// Creates [relative] under the sandbox and returns its path.
  String make(String relative) {
    final file = File('${sandbox.path}${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');
    return file.path;
  }

  List<String> names(List<File> files) =>
      files.map((f) => f.uri.pathSegments.last).toList()..sort();

  group('detecting a pattern', () {
    test('recognises the magic characters', () {
      expect(Glob.hasMagic('out/*.apk'), isTrue);
      expect(Glob.hasMagic('out/app-?.apk'), isTrue);
      expect(Glob.hasMagic('out/app-[ab].apk'), isTrue);
      expect(Glob.hasMagic('out/**/app.apk'), isTrue);
    });

    test('leaves an ordinary path alone', () {
      expect(Glob.hasMagic('distribution/android/output'), isFalse);
      expect(Glob.hasMagic('build/app-release.apk'), isFalse);
    });
  });

  group('expanding', () {
    test('matches by extension in one directory', () {
      make('out/app-release.apk');
      make('out/app-arm64.apk');
      make('out/mapping.txt');

      final found = Glob.expand('out/*.apk', from: sandbox);

      expect(names(found), ['app-arm64.apk', 'app-release.apk']);
    });

    test('a single star does not cross a directory boundary', () {
      make('out/top.apk');
      make('out/nested/deep.apk');

      expect(names(Glob.expand('out/*.apk', from: sandbox)), ['top.apk']);
    });

    test('a double star descends', () {
      make('out/top.apk');
      make('out/nested/deep.apk');
      make('out/nested/deeper/deepest.apk');

      expect(
        names(Glob.expand('out/**/*.apk', from: sandbox)),
        ['deep.apk', 'deepest.apk', 'top.apk'],
      );
    });

    test('a question mark matches exactly one character', () {
      make('out/app-1.apk');
      make('out/app-12.apk');

      expect(names(Glob.expand('out/app-?.apk', from: sandbox)), ['app-1.apk']);
    });

    test('a character set matches its members', () {
      make('out/app-a.apk');
      make('out/app-b.apk');
      make('out/app-c.apk');

      expect(
        names(Glob.expand('out/app-[ab].apk', from: sandbox)),
        ['app-a.apk', 'app-b.apk'],
      );
    });

    test('a pattern in a directory segment works', () {
      make('build/debug/app.apk');
      make('build/release/app.apk');

      final found = Glob.expand('build/*/app.apk', from: sandbox);
      expect(found, hasLength(2));
    });

    test('the newest match comes first', () {
      final older = make('out/old.apk');
      final newer = make('out/new.apk');
      File(older).setLastModifiedSync(DateTime(2020));
      File(newer).setLastModifiedSync(DateTime(2030));

      expect(
        Glob.expand('out/*.apk', from: sandbox).first.path,
        endsWith('new.apk'),
      );
    });

    test('nothing matching yields an empty list, not an error', () {
      make('out/app.apk');
      expect(Glob.expand('out/*.ipa', from: sandbox), isEmpty);
    });

    test('a missing directory yields an empty list', () {
      expect(Glob.expand('nowhere/*.apk', from: sandbox), isEmpty);
    });

    test('a path with no magic resolves to itself when it exists', () {
      final made = make('out/app.apk');
      expect(Glob.expand(made).single.path, made);
    });

    test('a path with no magic yields nothing when it does not exist', () {
      expect(Glob.expand('${sandbox.path}/absent.apk'), isEmpty);
    });

    test('directories are never returned', () {
      make('out/nested/app.apk');
      Directory('${sandbox.path}${Platform.pathSeparator}out'
              '${Platform.pathSeparator}decoy.apk')
          .createSync(recursive: true);

      final found = Glob.expand('out/*.apk', from: sandbox);
      expect(found, isEmpty, reason: 'decoy.apk is a directory');
    });

    test('a dot in the pattern is literal, not "any character"', () {
      make('out/appXapk');
      make('out/app.apk');

      expect(names(Glob.expand('out/app.apk', from: sandbox)), ['app.apk']);
    });
  });
}
