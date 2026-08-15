import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'build_info.dart';
import 'changelog.dart';

/// Values that `distribution.yaml` can reference without declaring them.
///
/// These cover the two things almost every release pipeline needs and that are
/// otherwise awkward to express: the current git state and the version declared
/// in `pubspec.yaml`. For example, deriving the build number from the commit
/// count no longer needs a wrapper script:
///
/// ```yaml
/// builder:
///   android:
///     build-name: "${{PUBSPEC_VERSION_NAME}}"
///     build-number: "${{GIT_COMMIT_COUNT}}"
/// ```
///
/// Every value is resolved lazily and memoised: a configuration that never
/// mentions `GIT_SHA` never spawns `git`. User defined `variables` and real
/// environment variables both take precedence, so any of these can be
/// overridden - which also makes them easy to pin in tests.
class BuiltinVariables {
  BuiltinVariables._();

  /// Cache of already resolved values, keyed by variable name.
  static final Map<String, String> _cache = {};

  /// The set of names this class can provide.
  static Set<String> get names => _resolvers.keys.toSet();

  /// Whether [name] is a built-in variable.
  static bool contains(String name) => _resolvers.containsKey(name);

  /// Clears the memoised values. Intended for tests.
  static void reset() {
    _cache.clear();
    _changelogCache = null;
    _polished.clear();
    changelogOptions = null;
    changelogPolisher = null;
  }

  /// Resolves [name], returning `null` when it is not a built-in or when it
  /// cannot be determined (for example `GIT_TAG` outside a tagged repository).
  static Future<String?> resolve(String name) async {
    if (_cache.containsKey(name)) return _cache[name];

    final resolver = _resolvers[name];
    if (resolver == null) return null;

    final value = await resolver();
    if (value == null || value.isEmpty) return null;

    _cache[name] = value;
    return value;
  }

  /// Resolves every built-in, skipping the ones that are unavailable.
  ///
  /// Used by `distribute doctor` and `distribute validate` to show the user
  /// what the placeholders will expand to.
  static Future<Map<String, String>> resolveAll() async {
    final resolved = <String, String>{};
    for (final name in _resolvers.keys) {
      final value = await resolve(name);
      if (value != null) resolved[name] = value;
    }
    return resolved;
  }

  static final Map<String, Future<String?> Function()> _resolvers = {
    'GIT_SHA': () => _git(['rev-parse', 'HEAD']),
    'GIT_SHORT_SHA': () => _git(['rev-parse', '--short', 'HEAD']),
    'GIT_BRANCH': () => _git(['rev-parse', '--abbrev-ref', 'HEAD']),
    'GIT_TAG': () => _git(['describe', '--tags', '--abbrev=0']),
    // `rev-list --count` is the conventional monotonic build number: it only
    // ever grows on a linear history, which is what app stores require.
    'GIT_COMMIT_COUNT': () => _git(['rev-list', '--count', 'HEAD']),
    'GIT_COMMIT_MESSAGE': () => _git(['log', '-1', '--pretty=%s']),
    'GIT_AUTHOR': () => _git(['log', '-1', '--pretty=%an']),
    'PUBSPEC_NAME': () => _pubspec('name'),
    'PUBSPEC_VERSION': () => _pubspec('version'),
    'PUBSPEC_VERSION_NAME': () => _pubspecVersionPart(0),
    'PUBSPEC_BUILD_NUMBER': () => _pubspecVersionPart(1),
    'ANDROID_APPLICATION_ID': () async => BuildInfo.androidPackageName,
    'IOS_BUNDLE_ID': () async => BuildInfo.iosBundleId,
    'BUILD_DATE': () async => DateTime.now().toIso8601String().split('T').first,
    'BUILD_TIMESTAMP': () async => DateTime.now().toIso8601String(),
    'HOST_OS': () async => Platform.operatingSystem,
    // Release notes for whatever this build contains. Resolved lazily like
    // everything else here, so a configuration that never mentions it never
    // shells out to git.
    // `CHANGELOG` follows the configured `format:`; `CHANGELOG_PLAIN` is the
    // escape hatch for a store listing that cannot render markdown, whatever
    // the project chose.
    'CHANGELOG': () => _changelog(null),
    'CHANGELOG_PLAIN': () => _changelog(ChangelogFormat.plain),
    'CHANGELOG_RANGE': () async {
      final log = await _readChangelog();
      return log?.range.toString();
    },
  };

  /// Settings the `changelog:` section supplies to `${{CHANGELOG}}`.
  ///
  /// Injected by whoever loaded the configuration, because this class is
  /// deliberately free of any dependency on the parser. Left null, the
  /// defaults apply — which is what makes the variable work with no
  /// configuration at all.
  static ChangelogOptions? changelogOptions;

  /// Memoised history, so two publishers referencing `${{CHANGELOG}}` in the
  /// same run read git once.
  static Changelog? _changelogCache;

  static Future<Changelog?> _readChangelog() async {
    if (_changelogCache != null) return _changelogCache;
    final options = changelogOptions ?? const ChangelogOptions();
    try {
      return _changelogCache = await Changelog.fromGit(
        from: options.from,
        limit: options.limit,
        includeMerges: options.includeMerges,
      );
    } on ChangelogException {
      // Not a git repository, or an unresolvable revision. The placeholder is
      // left unresolved, which `validate` already reports — better than
      // silently publishing empty release notes.
      return null;
    }
  }

  /// Renders the history, optionally forcing [format] over the configured one.
  ///
  /// The polished text is memoised separately from the raw text: with
  /// `changelog: ai: true` two publishers referencing the variable must cost
  /// one model request, not two.
  static Future<String?> _changelog(ChangelogFormat? format) async {
    final log = await _readChangelog();
    if (log == null || log.isEmpty) return null;
    final options = changelogOptions ?? const ChangelogOptions();

    final rendered = log.render(
      format: format ?? options.format,
      group: options.group,
      includeShas: options.includeShas,
    );

    final polish = changelogPolisher;
    if (polish == null) return rendered;

    final cached = _polished[rendered];
    if (cached != null) return cached;
    return _polished[rendered] = await polish(rendered);
  }

  /// Rewrites the rendered notes, when `changelog: ai:` asked for it.
  ///
  /// Injected rather than called directly so this class keeps no dependency on
  /// the AI adapters, and so a project that never sets `ai:` never loads them.
  /// A failure must throw: silently publishing raw commit subjects when the
  /// user asked for an edited changelog is a surprise at the worst moment.
  static Future<String> Function(String notes)? changelogPolisher;

  /// Polished text, keyed by the raw text it came from.
  static final Map<String, String> _polished = {};

  /// Runs a git command, returning `null` when git is missing or the command
  /// fails (not a repository, no tags yet, no commits yet).
  static Future<String?> _git(List<String> arguments) async {
    try {
      final result = await Process.run('git', arguments, runInShell: true);
      if (result.exitCode != 0) return null;
      final output = result.stdout.toString().trim();
      return output.isEmpty ? null : output;
    } on ProcessException {
      return null;
    }
  }

  /// Reads a top level scalar from `pubspec.yaml`.
  static Future<String?> _pubspec(String key) async {
    final file = File('pubspec.yaml');
    if (!file.existsSync()) return null;
    try {
      final content = loadYaml(await file.readAsString());
      if (content is! Map) return null;
      return content[key]?.toString();
    } on YamlException {
      return null;
    }
  }

  /// Splits `1.2.3+45` into its name (`1.2.3`) and build number (`45`).
  static Future<String?> _pubspecVersionPart(int index) async {
    final version = await _pubspec('version');
    if (version == null) return null;
    final parts = version.split('+');
    return index < parts.length ? parts[index] : null;
  }

  /// Best-effort path to the project root, used for diagnostics.
  static String get projectRoot => path.current;
}

/// The subset of the `changelog:` section that `${{CHANGELOG}}` needs.
///
/// A plain value object so `BuiltinVariables` stays independent of the
/// configuration parser and remains trivially testable.
class ChangelogOptions {
  /// Start of the range. Null means "the previous tag".
  final String? from;

  /// Whether markdown output is grouped by conventional commit type.
  final bool group;

  /// Whether each line carries its short commit hash.
  final bool includeShas;

  /// Whether merge commits are listed.
  final bool includeMerges;

  /// Cap on the number of commits read.
  final int? limit;

  /// How `${{CHANGELOG}}` is rendered.
  final ChangelogFormat format;

  /// Creates the options.
  const ChangelogOptions({
    this.from,
    this.group = true,
    this.includeShas = false,
    this.includeMerges = false,
    this.limit,
    this.format = ChangelogFormat.markdown,
  });
}
