import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'version_config.dart';

/// Persistent state used to continue an interrupted run safely.
class RunState {
  static const int currentSchema = 1;

  final String configHash;
  final String operation;
  final DateTime startedAt;
  DateTime updatedAt;
  ResolvedVersion? version;
  final Map<String, Map<String, dynamic>> jobs;

  RunState({
    required this.configHash,
    required this.operation,
    required this.startedAt,
    DateTime? updatedAt,
    this.version,
    Map<String, Map<String, dynamic>>? jobs,
  })  : updatedAt = updatedAt ?? startedAt,
        jobs = jobs ?? {};

  factory RunState.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != currentSchema) {
      throw const FormatException('unsupported run-state schema');
    }
    if (json['config-hash'] is! String ||
        json['started-at'] is! String ||
        json['updated-at'] is! String ||
        json['jobs'] is! Map) {
      throw const FormatException('missing or invalid required fields');
    }
    final rawJobs = json['jobs'];
    final jobs = <String, Map<String, dynamic>>{};
    for (final entry in (rawJobs as Map).entries) {
      if (entry.value is! Map) {
        throw FormatException("job '${entry.key}' is not an object");
      }
      jobs[entry.key.toString()] = Map<String, dynamic>.from(
        entry.value as Map,
      );
    }
    return RunState(
      configHash: json['config-hash'] as String,
      operation: json['operation']?.toString() ?? '',
      startedAt: DateTime.parse(json['started-at'].toString()),
      updatedAt: DateTime.parse(json['updated-at'].toString()),
      version: json['resolved-version'] is Map
          ? ResolvedVersion.fromJson(
              Map<String, dynamic>.from(json['resolved-version'] as Map),
            )
          : null,
      jobs: jobs,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': currentSchema,
        'config-hash': configHash,
        'operation': operation,
        'started-at': startedAt.toUtc().toIso8601String(),
        'updated-at': updatedAt.toUtc().toIso8601String(),
        if (version != null) 'resolved-version': version!.toJson(),
        'jobs': jobs,
      };
}

/// Atomic reader/writer for `.distribute/last-run.json`.
class RunStateStore {
  final File file;
  RunState state;
  Future<void> _writeGate = Future<void>.value();

  RunStateStore._(this.file, this.state);

  static String fingerprint(File config, String operation) {
    final bytes = <int>[
      ...config.readAsBytesSync(),
      ...utf8.encode('\noperation=$operation'),
    ];
    try {
      final result = Process.runSync(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: config.absolute.parent.path,
      );
      if (result.exitCode == 0) {
        final revision = result.stdout.toString().trim();
        if (revision.isNotEmpty) bytes.addAll(utf8.encode('\ngit=$revision'));
      }
    } on ProcessException {
      // A config outside a Git checkout remains resumable using its content.
    }
    return sha256.convert(bytes).toString();
  }

  static Future<RunStateStore> create({
    required File file,
    required String configHash,
    required String operation,
  }) async {
    final now = DateTime.now().toUtc();
    final store = RunStateStore._(
      file,
      RunState(
        configHash: configHash,
        operation: operation,
        startedAt: now,
      ),
    );
    await store.flush();
    return store;
  }

  static Future<RunStateStore> load(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('run state not found', file.path);
    }
    final String content;
    try {
      content = await file.readAsString();
    } on FileSystemException {
      rethrow;
    }
    try {
      final json = jsonDecode(content);
      if (json is! Map) throw const FormatException('root is not an object');
      return RunStateStore._(
        file,
        RunState.fromJson(Map<String, dynamic>.from(json)),
      );
    } on Object catch (error) {
      throw FormatException('invalid run state ${file.path}: $error');
    }
  }

  Map<String, dynamic>? job(String ref) => state.jobs[ref];

  Future<void> mark(String ref, Map<String, dynamic> value) async {
    state.jobs[ref] = value;
    await flush();
  }

  Future<void> setVersion(ResolvedVersion version) async {
    state.version = version;
    await flush();
  }

  Future<void> flush() {
    final operation = _writeGate.then(
      (_) => _flushNow(),
      onError: (_) => _flushNow(),
    );
    _writeGate = operation;
    return operation;
  }

  Future<void> _flushNow() async {
    state.updatedAt = DateTime.now().toUtc();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      // Some platforms do not replace an existing destination on rename.
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}
