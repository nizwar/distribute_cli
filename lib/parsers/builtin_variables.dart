import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'build_info.dart';

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
  static void reset() => _cache.clear();

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
  };

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
