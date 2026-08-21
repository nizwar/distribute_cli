import 'dart:io';

import 'package:yaml/yaml.dart';

import 'variables.dart';

/// Supported automatic build-number sources.
enum VersionCodeSource {
  pubspec,
  increment,
  gitCommits,
  timestamp,
  literal;
}

/// Optional run-level version resolution settings.
class VersionConfig {
  final String? name;
  final String code;
  final VersionCodeSource codeSource;
  final bool writeBack;

  const VersionConfig({
    this.name,
    required this.code,
    required this.codeSource,
    this.writeBack = false,
  });

  factory VersionConfig.parse(dynamic raw) {
    if (raw is! Map) {
      throw ArgumentError("'version' must be a mapping.");
    }
    final map = Map<String, dynamic>.from(raw);
    final rawCode = map['code'];
    if (rawCode == null || rawCode.toString().trim().isEmpty) {
      throw ArgumentError(
        "version.code is required (pubspec, increment, git-commits, "
        'timestamp, or a literal number).',
      );
    }
    final code = rawCode.toString().trim();
    final source = switch (code.toLowerCase()) {
      'pubspec' => VersionCodeSource.pubspec,
      'increment' => VersionCodeSource.increment,
      'git-commits' => VersionCodeSource.gitCommits,
      'timestamp' => VersionCodeSource.timestamp,
      _ when int.tryParse(code) != null => VersionCodeSource.literal,
      _ => throw ArgumentError(
          "version.code must be pubspec, increment, git-commits, timestamp, "
          "or a literal number; got '$code'.",
        ),
    };

    final writeBack = _bool(map['write-back'], 'version.write-back');
    if (source == VersionCodeSource.literal && int.parse(code) < 1) {
      throw ArgumentError('version.code literal must be greater than zero.');
    }
    if (writeBack && source == VersionCodeSource.gitCommits) {
      // This is valid, but calling it out through the model keeps the parser
      // strict while allowing teams that deliberately mirror Git in pubspec.
    }
    return VersionConfig(
      name: map['name']?.toString(),
      code: code,
      codeSource: source,
      writeBack: writeBack,
    );
  }

  static bool _bool(dynamic raw, String label) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw.toString().trim().toLowerCase() == 'true') return true;
    if (raw.toString().trim().toLowerCase() == 'false') return false;
    throw ArgumentError("$label must be true or false, got '$raw'.");
  }
}

/// Version values fixed once at the beginning of a run.
class ResolvedVersion {
  final String name;
  final String code;

  const ResolvedVersion({required this.name, required this.code});

  Map<String, dynamic> toJson() => {'name': name, 'code': code};

  factory ResolvedVersion.fromJson(Map<String, dynamic> json) =>
      ResolvedVersion(
        name: json['name'].toString(),
        code: json['code'].toString(),
      );
}

/// Resolves and optionally writes a [VersionConfig].
class VersionResolver {
  final Variables variables;
  final File pubspec;

  VersionResolver(this.variables, {File? pubspec})
      : pubspec = pubspec ?? File('pubspec.yaml');

  Future<ResolvedVersion> resolve(
    VersionConfig config, {
    bool writeBack = true,
  }) async {
    final current = await _pubspecVersion();
    final parts = current.split('+');
    final currentName = parts.first;
    final currentCode = parts.length > 1 ? parts[1] : '0';

    final name = config.name == null || config.name!.trim().isEmpty
        ? currentName
        : await variables.process(config.name);
    final Object code = switch (config.codeSource) {
      VersionCodeSource.pubspec => currentCode,
      VersionCodeSource.increment => _increment(currentCode),
      VersionCodeSource.gitCommits => await _gitCommitCount(),
      VersionCodeSource.timestamp => _timestampCode(),
      VersionCodeSource.literal => int.parse(config.code),
    };
    final result = ResolvedVersion(name: name, code: code.toString());
    if (config.writeBack && writeBack) await this.writeBack(result);
    return result;
  }

  int _increment(String currentCode) {
    final parsed = int.tryParse(currentCode);
    if (parsed == null) {
      throw ArgumentError(
        "pubspec build number '$currentCode' is not numeric.",
      );
    }
    return parsed + 1;
  }

  Future<String> _pubspecVersion() async {
    if (!await pubspec.exists()) {
      throw ArgumentError(
          'pubspec.yaml was not found; auto-version cannot run.');
    }
    final decoded = loadYaml(await pubspec.readAsString());
    final version = decoded is Map ? decoded['version']?.toString() : null;
    if (version == null || version.trim().isEmpty) {
      throw ArgumentError('pubspec.yaml does not declare a version.');
    }
    return version.trim();
  }

  Future<int> _gitCommitCount() async {
    final workingDirectory = pubspec.parent.path;
    final shallow = await Process.run(
      'git',
      ['rev-parse', '--is-shallow-repository'],
      workingDirectory: workingDirectory,
    );
    if (shallow.exitCode == 0 &&
        shallow.stdout.toString().trim().toLowerCase() == 'true') {
      throw ArgumentError(
        'Cannot derive version.code from a shallow Git clone. Fetch the full '
        'history (for example checkout with fetch-depth: 0), or choose another '
        'strategy.',
      );
    }
    final result = await Process.run(
      'git',
      ['rev-list', '--count', 'HEAD'],
      workingDirectory: workingDirectory,
    );
    final count = int.tryParse(result.stdout.toString().trim());
    if (result.exitCode != 0 || count == null) {
      throw ArgumentError(
        'Could not derive version.code from Git. Ensure this is a repository '
        'with a non-shallow history, or choose another strategy.',
      );
    }
    return count;
  }

  /// Seconds since 2020-01-01 UTC: monotonic to the second and below the
  /// Android versionCode ceiling until well beyond the expected lifetime of
  /// this tool.
  int _timestampCode() {
    final epoch = DateTime.utc(2020).millisecondsSinceEpoch;
    return (DateTime.now().toUtc().millisecondsSinceEpoch - epoch) ~/ 1000;
  }

  /// Rewrites only the top-level version line, preserving all other formatting.
  Future<void> writeBack(ResolvedVersion version) async {
    final content = await pubspec.readAsString();
    final line = RegExp(r'^version\s*:\s*.*$', multiLine: true);
    if (!line.hasMatch(content)) {
      throw ArgumentError(
          'pubspec.yaml does not contain a writable version line.');
    }
    await pubspec.writeAsString(
      content.replaceFirst(line, 'version: ${version.name}+${version.code}'),
    );
  }
}
