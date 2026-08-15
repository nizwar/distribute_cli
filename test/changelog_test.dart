import 'dart:io';

import 'package:distribute_cli/parsers/changelog.dart';
import 'package:test/test.dart';

/// Builds the delimited shape `git log --pretty=format:%H%x1f%s%x1f%an%x1e`
/// produces, so the parsing and rendering can be exercised without a repo.
String log(List<(String, String, String)> commits) =>
    commits.map((c) => '${c.$1}\x1f${c.$2}\x1f${c.$3}').join('\x1e');

void main() {
  Changelog build(List<(String, String, String)> commits) => Changelog(
        entries: Changelog.parseLog(log(commits)),
        range: const ChangelogRange(from: 'v1.0.0', to: 'HEAD'),
      );

  group('parsing commit subjects', () {
    test('splits a conventional commit into its parts', () {
      final entry = Changelog.parseLog(
        log([('abc1234def', 'feat(auth): add google sign in', 'Ada')]),
      ).single;

      expect(entry.type, 'feat');
      expect(entry.scope, 'auth');
      expect(entry.subject, 'add google sign in');
      expect(entry.breaking, isFalse);
      expect(entry.shortSha, 'abc1234');
      expect(entry.author, 'Ada');
    });

    test('reads the breaking marker', () {
      final entry = Changelog.parseLog(
        log([('a', 'feat!: drop android 5', 'Ada')]),
      ).single;

      expect(entry.breaking, isTrue);
      expect(entry.subject, 'drop android 5');
    });

    test('reads a breaking marker with a scope', () {
      final entry = Changelog.parseLog(
        log([('a', 'refactor(api)!: rename endpoints', 'Ada')]),
      ).single;

      expect(entry.type, 'refactor');
      expect(entry.scope, 'api');
      expect(entry.breaking, isTrue);
    });

    test('keeps a plain subject as-is', () {
      final entry =
          Changelog.parseLog(log([('a', 'just did a thing', 'Ada')])).single;

      expect(entry.type, isNull);
      expect(entry.scope, isNull);
      expect(entry.subject, 'just did a thing');
    });

    test('honours BREAKING CHANGE without a conventional prefix', () {
      final entry = Changelog.parseLog(
        log([('a', 'BREAKING CHANGE: config format changed', 'Ada')]),
      ).single;

      expect(entry.breaking, isTrue);
    });

    test('a colon in ordinary prose is not a type', () {
      // "Note: ..." would otherwise be read as a type named `note`, which is
      // harmless, but "fixes #12: whatever" must not lose its text.
      final entry = Changelog.parseLog(
        log([('a', 'fixes #12: crash on launch', 'Ada')]),
      ).single;

      expect(entry.subject, 'fixes #12: crash on launch');
      expect(entry.type, isNull);
    });

    test('drops a commit with an empty subject', () {
      expect(Changelog.parseLog(log([('a', '   ', 'Ada')])), isEmpty);
    });

    test('drops a duplicate subject from a cherry-pick', () {
      final entries = Changelog.parseLog(log([
        ('a', 'fix: same thing', 'Ada'),
        ('b', 'fix: same thing', 'Grace'),
      ]));

      expect(entries, hasLength(1));
    });

    test('a subject containing a newline is kept whole', () {
      // `%s` is a single line, so this cannot come from git — but the record
      // separator is what makes that irrelevant, and nothing may be silently
      // truncated at a newline.
      final entries = Changelog.parseLog(
        log([('a', 'fix: line one\nline two', 'Ada')]),
      );

      expect(entries.single.subject, 'fix: line one\nline two');
    });

    test('a subject containing the field separator does not split a record',
        () {
      final entries = Changelog.parseLog(
        log([('a', 'fix: a | b : c', 'Ada'), ('b', 'feat: next', 'Ada')]),
      );

      expect(entries, hasLength(2));
      expect(entries.first.subject, 'a | b : c');
    });

    test('an empty log yields nothing', () {
      expect(Changelog.parseLog(''), isEmpty);
      expect(Changelog.parseLog('\x1e\x1e'), isEmpty);
    });
  });

  group('markdown rendering', () {
    final changelog = build([
      ('a', 'feat(auth): add sign in', 'Ada'),
      ('b', 'fix: crash on launch', 'Ada'),
      ('c', 'feat!: drop android 5', 'Ada'),
      ('d', 'chore: bump deps', 'Ada'),
      ('e', 'something unlabelled', 'Ada'),
    ]);

    test('groups by type with breaking changes first', () {
      final rendered = changelog.render();

      expect(rendered.indexOf('### Breaking changes'), 0);
      expect(
        rendered.indexOf('### Features'),
        lessThan(rendered.indexOf('### Bug fixes')),
      );
      expect(rendered, contains('- auth: add sign in'));
      expect(rendered, contains('### Other changes'));
      expect(rendered, contains('- something unlabelled'));
    });

    test('a breaking change is listed once, under its own heading', () {
      final rendered = changelog.render();
      expect('drop android 5'.allMatches(rendered).length, 1);
    });

    test('grouping can be turned off', () {
      final rendered = changelog.render(group: false);

      expect(rendered, isNot(contains('###')));
      expect(rendered.split('\n'), hasLength(5));
      expect(rendered.split('\n').first, startsWith('- BREAKING:'));
    });

    test('short hashes are opt-in', () {
      expect(changelog.render(), isNot(contains('(a)')));
      expect(changelog.render(includeShas: true), contains('(a)'));
    });

    test('a title is rendered as a heading', () {
      expect(changelog.render(title: 'v1.1.0'), startsWith('## v1.1.0'));
    });

    test('an empty changelog renders as nothing', () {
      expect(build([]).render(), isEmpty);
      expect(build([]).isEmpty, isTrue);
    });

    test('an unknown type falls into Other changes rather than vanishing', () {
      final rendered = build([('a', 'wibble: something odd', 'Ada')]).render();

      expect(rendered, contains('### Other changes'));
      expect(rendered, contains('something odd'));
    });
  });

  group('plain rendering', () {
    test('is a flat list with no headings', () {
      final rendered = build([
        ('a', 'feat: one', 'Ada'),
        ('b', 'fix: two', 'Ada'),
      ]).render(format: ChangelogFormat.plain);

      expect(rendered, isNot(contains('#')));
      expect(rendered.split('\n'), ['- one', '- two']);
    });

    test('still leads with breaking changes', () {
      final rendered = build([
        ('a', 'feat: ordinary', 'Ada'),
        ('b', 'feat!: important', 'Ada'),
      ]).render(format: ChangelogFormat.plain);

      expect(rendered.split('\n').first, '- BREAKING: important');
    });

    test('ignores the group flag, because there are no sections', () {
      final rendered = build([('a', 'feat: one', 'Ada')])
          .render(format: ChangelogFormat.plain, group: true);

      expect(rendered, '- one');
    });
  });

  group('format parsing', () {
    test('accepts the documented spellings', () {
      expect(ChangelogFormat.parse('markdown'), ChangelogFormat.markdown);
      expect(ChangelogFormat.parse('md'), ChangelogFormat.markdown);
      expect(ChangelogFormat.parse('plain'), ChangelogFormat.plain);
      expect(ChangelogFormat.parse('text'), ChangelogFormat.plain);
      expect(ChangelogFormat.parse(null), ChangelogFormat.markdown);
      expect(ChangelogFormat.parse(''), ChangelogFormat.markdown);
    });

    test('rejects anything else by name', () {
      expect(
        () => ChangelogFormat.parse('html'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('reading a real repository', () {
    late Directory repo;

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('distribute_cli_changelog');
      Future<void> git(List<String> args) async {
        final result =
            await Process.run('git', args, workingDirectory: repo.path);
        if (result.exitCode != 0) {
          throw StateError('git ${args.join(' ')}: ${result.stderr}');
        }
      }

      Future<void> commit(String message) async {
        File('${repo.path}${Platform.pathSeparator}f.txt')
            .writeAsStringSync(message);
        await git(['add', '-A']);
        await git(['commit', '-m', message]);
      }

      await git(['init', '-q']);
      await git(['config', 'user.email', 't@t.t']);
      await git(['config', 'user.name', 'T']);
      await git(['config', 'commit.gpgsign', 'false']);

      await commit('chore: before the tag');
      await git(['tag', 'v1.0.0']);
      await commit('feat: after the tag');
      await commit('fix: also after');
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('defaults to everything since the previous tag', () async {
      final log = await Changelog.fromGit(workingDirectory: repo);

      expect(log.range.from, 'v1.0.0');
      expect(log.entries.map((e) => e.subject),
          containsAll(['after the tag', 'also after']));
      expect(
          log.entries.map((e) => e.subject), isNot(contains('before the tag')));
    });

    test('a tagged HEAD still describes that release', () async {
      // `git describe` alone returns HEAD's own tag here, which would produce
      // an empty range for exactly the release being cut.
      await Process.run('git', ['tag', 'v1.1.0'], workingDirectory: repo.path);

      final log = await Changelog.fromGit(workingDirectory: repo);

      expect(log.range.from, 'v1.0.0');
      expect(log.entries, hasLength(2));
    });

    test('an explicit range wins', () async {
      final log = await Changelog.fromGit(
        from: 'v1.0.0',
        to: 'HEAD',
        limit: 1,
        workingDirectory: repo,
      );

      expect(log.entries, hasLength(1));
    });

    test('a repository with no tags reads the whole history', () async {
      final bare = Directory.systemTemp.createTempSync('distribute_cli_bare');
      try {
        for (final args in [
          ['init', '-q'],
          ['config', 'user.email', 't@t.t'],
          ['config', 'user.name', 'T'],
        ]) {
          await Process.run('git', args, workingDirectory: bare.path);
        }
        File('${bare.path}${Platform.pathSeparator}f.txt')
            .writeAsStringSync('1');
        await Process.run('git', ['add', '-A'], workingDirectory: bare.path);
        await Process.run('git', ['commit', '-m', 'feat: first'],
            workingDirectory: bare.path);

        final log = await Changelog.fromGit(workingDirectory: bare);

        expect(log.range.from, isNull);
        expect(log.entries.single.subject, 'first');
      } finally {
        bare.deleteSync(recursive: true);
      }
    });

    test('an unknown revision is reported by name', () async {
      expect(
        Changelog.fromGit(to: 'no-such-ref', workingDirectory: repo),
        throwsA(
          isA<ChangelogException>().having(
            (e) => e.message,
            'message',
            contains('no-such-ref'),
          ),
        ),
      );
    });

    test('a ref that collides with a path still reads the history', () async {
      // Without a trailing `--`, git refuses with "ambiguous argument" and the
      // failure used to be reported as an empty history with exit 0.
      Directory('${repo.path}${Platform.pathSeparator}release')
          .createSync(recursive: true);
      File('${repo.path}${Platform.pathSeparator}release${Platform.pathSeparator}a')
          .writeAsStringSync('a');
      await Process.run('git', ['add', '-A'], workingDirectory: repo.path);
      await Process.run('git', ['commit', '-m', 'feat: on release'],
          workingDirectory: repo.path);
      await Process.run('git', ['branch', 'release'],
          workingDirectory: repo.path);

      final log =
          await Changelog.fromGit(to: 'release', workingDirectory: repo);

      expect(log.entries, isNotEmpty);
      expect(log.entries.map((e) => e.subject), contains('on release'));
    });

    test('the previous tag is the nearest ancestor, not the newest by date',
        () async {
      // A retroactively created tag has a creation date of "now", so ordering
      // by creatordate made it win forever and re-list commits that had
      // already shipped.
      await Process.run('git', ['tag', 'v2.0.0'], workingDirectory: repo.path);
      await Process.run(
        'git',
        ['tag', '-a', 'v0.9.0', '-m', 'retro', 'v1.0.0'],
        workingDirectory: repo.path,
      );
      // A commit after v2.0.0 so the range is not empty.
      File('${repo.path}${Platform.pathSeparator}f.txt').writeAsStringSync('n');
      await Process.run('git', ['add', '-A'], workingDirectory: repo.path);
      await Process.run('git', ['commit', '-m', 'fix: newest'],
          workingDirectory: repo.path);

      final log = await Changelog.fromGit(workingDirectory: repo);

      expect(log.range.from, 'v2.0.0');
      expect(log.entries.map((e) => e.subject), ['newest']);
    });

    test('a tag pointing at the end of the range is skipped', () async {
      await Process.run('git', ['tag', 'v2.0.0'], workingDirectory: repo.path);

      final log = await Changelog.fromGit(workingDirectory: repo);

      expect(log.range.from, 'v1.0.0', reason: 'v2.0.0 is HEAD itself');
      expect(log.entries, hasLength(2));
    });

    test('a full clone is not reported as shallow', () async {
      expect(
          (await Changelog.fromGit(workingDirectory: repo)).shallow, isFalse);
    });

    test('a shallow clone is flagged', () async {
      final shallow = Directory.systemTemp.createTempSync('distribute_shallow');
      try {
        final result = await Process.run('git', [
          'clone',
          '--depth',
          '1',
          '--no-local',
          'file://${repo.path}',
          shallow.path,
        ]);
        if (result.exitCode != 0) {
          markTestSkipped('git clone --depth is unavailable here');
          return;
        }

        final log = await Changelog.fromGit(workingDirectory: shallow);
        expect(log.shallow, isTrue);
      } finally {
        shallow.deleteSync(recursive: true);
      }
    });

    test('a directory that is not a repository is reported', () async {
      final plain = Directory.systemTemp.createTempSync('distribute_cli_plain');
      try {
        expect(
          Changelog.fromGit(workingDirectory: plain),
          throwsA(isA<ChangelogException>()),
        );
      } finally {
        plain.deleteSync(recursive: true);
      }
    });
  });
}
