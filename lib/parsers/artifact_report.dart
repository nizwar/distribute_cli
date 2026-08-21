import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// A binary produced by a build job.
///
/// Size and checksum are captured right after the build so the run summary can
/// answer the two questions that usually follow a release - "did the app grow?"
/// and "is the file I am about to ship the one that was built?" - without
/// anyone having to shell out to `ls` and `shasum`.
class Artifact {
  /// Absolute or project relative path of the file.
  final String filePath;

  /// Size of the file in bytes.
  final int sizeInBytes;

  /// Lowercase hex SHA-256 of the file contents.
  final String sha256Hash;

  /// Creates an artifact record.
  const Artifact({
    required this.filePath,
    required this.sizeInBytes,
    required this.sha256Hash,
  });

  /// Restores an artifact recorded in run state or a JSON report.
  factory Artifact.fromJson(Map<String, dynamic> json) => Artifact(
        filePath: json['path'].toString(),
        sizeInBytes: (json['size-bytes'] as num).toInt(),
        sha256Hash: json['sha256'].toString(),
      );

  /// File name without its directory.
  String get name => path.basename(filePath);

  /// Human readable size such as `24.3 MB`.
  String get readableSize {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = sizeInBytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return unit == 0
        ? '$sizeInBytes ${units[unit]}'
        : '${size.toStringAsFixed(1)} ${units[unit]}';
  }

  /// Short checksum prefix, enough to eyeball a match in a log.
  String get shortHash => sha256Hash.substring(0, 12);

  /// Serialises the artifact for the `--json` run report.
  Map<String, dynamic> toJson() => {
        'name': name,
        'path': filePath,
        'size-bytes': sizeInBytes,
        'size-readable': readableSize,
        'sha256': sha256Hash,
      };

  /// Collects every file directly inside [directory] as an artifact.
  ///
  /// Returns an empty list when the directory is absent, which is the normal
  /// state during a dry run or before the first build.
  static Future<List<Artifact>> fromDirectory(
    String directory, {
    Set<String> extensions = const {'apk', 'aab', 'ipa', 'zip'},
  }) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];

    final artifacts = <Artifact>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final extension =
          path.extension(entity.path).replaceFirst('.', '').toLowerCase();
      if (extensions.isNotEmpty && !extensions.contains(extension)) continue;
      artifacts.add(await fromFile(entity));
    }

    artifacts.sort((a, b) => a.name.compareTo(b.name));
    return artifacts;
  }

  /// Reads [file] and computes its size and checksum.
  ///
  /// The file is streamed rather than read into memory: an app bundle can be
  /// hundreds of megabytes.
  static Future<Artifact> fromFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return Artifact(
      filePath: file.path,
      sizeInBytes: await file.length(),
      sha256Hash: digest.toString(),
    );
  }
}
