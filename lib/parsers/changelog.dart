import 'dart:io';

/// Raised when the changelog cannot be produced.
///
/// Always carries something the user can act on: which git command failed, or
/// which revision could not be resolved.
class ChangelogException implements Exception {
  /// What went wrong, and what to do about it.
  final String message;

  /// Creates a changelog failure carrying [message].
  ChangelogException(this.message);

  @override
  String toString() => message;
}

/// One commit, already split into the parts a changelog cares about.
class ChangelogEntry {
  /// Full commit hash.
  final String sha;

  /// First line of the commit message, with any conventional prefix removed.
  final String subject;

  /// Conventional commit type (`feat`, `fix`, …), or null when there is none.
  final String? type;

  /// Conventional commit scope, when the subject declared one.
  final String? scope;

  /// Whether the commit is marked as a breaking change.
  final bool breaking;

  /// Commit author's name.
  final String author;

  /// Creates an entry.
  const ChangelogEntry({
    required this.sha,
    required this.subject,
    required this.author,
    this.type,
    this.scope,
    this.breaking = false,
  });

  /// The first seven characters of [sha], as git renders it.
  String get shortSha => sha.length <= 7 ? sha : sha.substring(0, 7);

  /// `scope: subject`, or just the subject when there is no scope.
  String get titled => scope == null ? subject : '$scope: $subject';
}

/// The commit range a changelog was built from.
class ChangelogRange {
  /// Exclusive start of the range, or null when the history has no earlier tag.
  final String? from;

  /// Inclusive end of the range.
  final String to;

  /// Creates a range.
  const ChangelogRange({required this.to, this.from});

  /// How git spells this range.
  String get revisions => from == null ? to : '$from..$to';

  @override
  String toString() => from == null ? 'up to $to' : '$from → $to';
}

/// How the changelog is rendered.
enum ChangelogFormat {
  /// Headed sections and `- ` bullets. Suits GitHub release bodies.
  markdown,

  /// A flat bullet list with no headings. Suits stores that show plain text,
  /// such as Firebase App Distribution release notes.
  plain;

  /// Parses the `format:` key.
  static ChangelogFormat parse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case null:
      case '':
      case 'markdown':
      case 'md':
        return ChangelogFormat.markdown;
      case 'plain':
      case 'text':
        return ChangelogFormat.plain;
      default:
        throw ArgumentError(
          "Invalid changelog format '$value'. Expected 'markdown' or 'plain'.",
        );
    }
  }
}

/// Builds a changelog from the git history.
///
/// The default range is "everything since the previous tag", which is what a
/// release actually wants: running this on a tagged commit describes that
/// release, not an empty range.
///
/// Conventional commit prefixes (`feat:`, `fix(auth)!:`) are recognised and
/// used for grouping, but nothing requires them — a repository with ordinary
/// commit messages gets a flat list rather than an error.
class Changelog {
  /// Commits in the range, newest first.
  final List<ChangelogEntry> entries;

  /// The range the entries came from.
  final ChangelogRange range;

  /// Creates a changelog from already-parsed [entries].
  const Changelog({
    required this.entries,
    required this.range,
    this.shallow = false,
  });

  /// Whether the range contained no commits worth listing.
  bool get isEmpty => entries.isEmpty;

  /// Whether the repository is a shallow clone, so the history is truncated.
  ///
  /// CI checkouts default to `--depth 1`, which quietly produces release notes
  /// missing everything before the cut. The caller says so rather than letting
  /// a short changelog look like a quiet release.
  final bool shallow;

  /// Section headings, in the order they are rendered.
  ///
  /// Types outside this map fall into "Other changes", so an unfamiliar prefix
  /// is still shown rather than silently dropped.
  static const Map<String, String> sections = {
    'feat': 'Features',
    'fix': 'Bug fixes',
    'perf': 'Performance',
    'refactor': 'Refactoring',
    'docs': 'Documentation',
    'test': 'Tests',
    'build': 'Build',
    'ci': 'CI',
    'style': 'Style',
    'chore': 'Chores',
    'revert': 'Reverts',
  };

  /// Reads the history and builds a changelog.
  ///
  /// [from] and [to] are any revision git understands. When [from] is omitted
  /// the previous tag is used; when there is no earlier tag the whole history
  /// is taken, capped by [limit].
  static Future<Changelog> fromGit({
    String? from,
    String to = 'HEAD',
    int? limit,
    bool includeMerges = false,
    Directory? workingDirectory,
  }) async {
    final root = workingDirectory?.path;
    if (await _git(['rev-parse', '--git-dir'], root) == null) {
      throw ChangelogException(
        'not a git repository, so there is no history to read',
      );
    }

    if (await _git(['rev-parse', '--verify', '$to^{commit}'], root) == null) {
      throw ChangelogException("revision '$to' does not exist");
    }

    final start = from ?? await _previousTag(to, root);
    if (from != null &&
        await _git(['rev-parse', '--verify', '$from^{commit}'], root) == null) {
      throw ChangelogException("revision '$from' does not exist");
    }

    // %x1f between fields and %x1e between records: a commit subject can
    // contain anything, including newlines and pipes, so a printable delimiter
    // would eventually be wrong.
    //
    // The trailing `--` matters: without it a revision that is also a path —
    // a branch called `release` next to a `release/` directory, or a tracked
    // file named `HEAD` — makes git refuse with "ambiguous argument", which
    // used to be swallowed and reported as an empty history.
    final result = await _run(
      [
        'log',
        if (start != null) '$start..$to' else to,
        '--pretty=format:%H%x1f%s%x1f%an%x1e',
        if (!includeMerges) '--no-merges',
        if (limit != null) '--max-count=$limit',
        '--',
      ],
      root,
    );

    if (result == null) {
      throw ChangelogException('git is not installed, or is not on PATH');
    }
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw ChangelogException(
        'git could not read the history for '
        '${start == null ? to : '$start..$to'}'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }

    final entries = parseLog(result.stdout.toString());
    final shallow =
        (await _git(['rev-parse', '--is-shallow-repository'], root))?.trim() ==
            'true';

    return Changelog(
      entries: entries,
      range: ChangelogRange(from: start, to: to),
      shallow: shallow,
    );
  }

  /// Parses the delimited output of `git log` into entries.
  ///
  /// Separated from [fromGit] so the grouping and rendering can be tested
  /// without a repository.
  static List<ChangelogEntry> parseLog(String log) {
    final entries = <ChangelogEntry>[];
    final seen = <String>{};

    for (final record in log.split('\x1e')) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;

      final fields = trimmed.split('\x1f');
      if (fields.length < 3) continue;

      final subject = fields[1].trim();
      if (subject.isEmpty) continue;

      final parsed = _parseSubject(subject);

      // A cherry-picked or rebased commit shows up twice with a different
      // hash; the same sentence listed twice reads like a mistake.
      if (!seen.add('${parsed.type}|${parsed.scope}|${parsed.subject}')) {
        continue;
      }

      entries.add(
        ChangelogEntry(
          sha: fields[0].trim(),
          subject: parsed.subject,
          type: parsed.type,
          scope: parsed.scope,
          breaking: parsed.breaking,
          author: fields[2].trim(),
        ),
      );
    }

    return entries;
  }

  /// Renders the changelog.
  ///
  /// [includeShas] appends the short hash to each line, which is useful in a
  /// GitHub release body and noise in a store listing.
  String render({
    ChangelogFormat format = ChangelogFormat.markdown,
    bool group = true,
    bool includeShas = false,
    String? title,
  }) {
    if (entries.isEmpty) return '';

    String line(ChangelogEntry entry) =>
        '- ${entry.titled}${includeShas ? ' (${entry.shortSha})' : ''}';

    final buffer = StringBuffer();
    if (title != null && title.isNotEmpty) {
      buffer.writeln(
        format == ChangelogFormat.markdown ? '## $title' : title,
      );
      buffer.writeln();
    }

    if (!group || format == ChangelogFormat.plain) {
      // Breaking changes still lead: they are the ones that need reading.
      final ordered = [
        ...entries.where((entry) => entry.breaking),
        ...entries.where((entry) => !entry.breaking),
      ];
      for (final entry in ordered) {
        final marker = entry.breaking ? '- BREAKING: ' : '- ';
        buffer.writeln(
          '$marker${entry.titled}'
          '${includeShas ? ' (${entry.shortSha})' : ''}',
        );
      }
      return buffer.toString().trimRight();
    }

    final breaking = entries.where((entry) => entry.breaking).toList();
    if (breaking.isNotEmpty) {
      buffer.writeln('### Breaking changes');
      for (final entry in breaking) {
        buffer.writeln(line(entry));
      }
      buffer.writeln();
    }

    for (final section in sections.entries) {
      final matching = entries
          .where((entry) => entry.type == section.key && !entry.breaking)
          .toList();
      if (matching.isEmpty) continue;

      buffer.writeln('### ${section.value}');
      for (final entry in matching) {
        buffer.writeln(line(entry));
      }
      buffer.writeln();
    }

    final other = entries
        .where((entry) =>
            !entry.breaking && !sections.containsKey(entry.type ?? ''))
        .toList();
    if (other.isNotEmpty) {
      buffer.writeln('### Other changes');
      for (final entry in other) {
        buffer.writeln(line(entry));
      }
    }

    return buffer.toString().trimRight();
  }

  /// The tag before [to], or null when the history has none.
  ///
  /// `git describe` alone is not enough: on a tagged commit it returns that
  /// commit's own tag, which would produce an empty range for exactly the
  /// release being cut.
  static Future<String?> _previousTag(String to, String? root) async {
    final tags = await _git(['tag', '--merged', to], root);
    if (tags == null || tags.trim().isEmpty) return null;

    final names = tags
        .split('\n')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;

    // Ranked by how many commits separate the tag from `to`, not by when the
    // tag was created. Creation date is the wrong axis: a tag cut on a side
    // branch can be newer than the mainline tag that superseded it, and a
    // retroactively added tag is dated "now" forever — both make the range
    // re-list commits that already shipped while dropping ones that have not.
    String? closest;
    var fewest = 1 << 30;

    for (final tag in names) {
      final distance = await _git(
        ['rev-list', '--count', '$tag..$to', '--'],
        root,
      );
      final count = int.tryParse(distance?.trim() ?? '');
      // 0 means the tag points at `to` itself; diffing against it would
      // describe an empty release, which is never what was wanted.
      if (count == null || count == 0) continue;
      if (count < fewest) {
        fewest = count;
        closest = tag;
      }
    }

    // Every tag points at `to` itself, so there is nothing earlier to diff
    // against; the whole history is the honest answer.
    return closest;
  }

  /// Splits `feat(scope)!: subject` into its parts.
  static _Subject _parseSubject(String subject) {
    final match = RegExp(
      r'^([a-zA-Z]+)(?:\(([^)]*)\))?(!)?:\s*(.+)$',
    ).firstMatch(subject);

    if (match == null) {
      // Not a conventional commit. `BREAKING CHANGE:` anywhere in the subject
      // is still worth honouring, since plenty of repositories use it alone.
      final breaking = subject.toUpperCase().contains('BREAKING CHANGE');
      return _Subject(subject: subject, breaking: breaking);
    }

    final scope = match.group(2)?.trim();
    return _Subject(
      type: match.group(1)!.toLowerCase(),
      scope: scope == null || scope.isEmpty ? null : scope,
      breaking: match.group(3) != null,
      subject: match.group(4)!.trim(),
    );
  }

  /// Runs git, returning null when it is missing or the command fails.
  ///
  /// Used for the probes where "it did not work" is a legitimate answer — no
  /// tags, not a repository. Anything whose failure the user needs to hear
  /// about goes through [_run] instead.
  static Future<String?> _git(List<String> arguments, String? root) async {
    final result = await _run(arguments, root);
    if (result == null || result.exitCode != 0) return null;
    return result.stdout.toString();
  }

  /// Runs git and returns the whole result, or null when git is missing.
  static Future<ProcessResult?> _run(
      List<String> arguments, String? root) async {
    try {
      return await Process.run('git', arguments, workingDirectory: root);
    } on ProcessException {
      return null;
    }
  }
}

/// A commit subject split into its conventional parts.
class _Subject {
  final String? type;
  final String? scope;
  final bool breaking;
  final String subject;

  const _Subject({
    required this.subject,
    this.type,
    this.scope,
    this.breaking = false,
  });
}
