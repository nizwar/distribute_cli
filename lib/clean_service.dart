import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'files.dart';
import 'logger.dart';
import 'parsers/job_arguments.dart';

/// Performs the destructive portion of cleanup behind strict path guards.
class CleanService {
  final ColorizeLogger logger;
  final bool dryRun;
  final Directory projectRoot;
  final Set<String> protectedPaths;

  CleanService(
    this.logger, {
    required this.dryRun,
    Directory? projectRoot,
    Iterable<String> protectedPaths = const [],
  })  : projectRoot = projectRoot ?? Directory.current,
        protectedPaths = protectedPaths.toSet();

  Future<int> flutterClean() async {
    logger.logCommand('flutter clean');
    if (dryRun) return 0;
    final Process process;
    try {
      process = await Process.start(
        'flutter',
        ['clean'],
        workingDirectory: projectRoot.path,
        runInShell: true,
        includeParentEnvironment: true,
      );
      JobArguments.trackProcess(process);
    } on ProcessException catch (error) {
      logger.logError('Unable to start `flutter clean`: ${error.message}');
      return 127;
    }
    final drained = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(logger.logDebug),
      process.stderr.transform(utf8.decoder).forEach(logger.logErrorVerbose),
    ]);
    final exit = await process.exitCode;
    await drained;
    return exit;
  }

  Future<int> outputs(Iterable<String> directories) async {
    var failed = false;
    for (final raw in directories.toSet()) {
      try {
        final directory = _safeOutput(raw);
        if (!directory.existsSync()) {
          logger.logDebug('output already clean: ${directory.path}');
          continue;
        }
        logger.logInfo(
          '${dryRun ? '[dry-run] would remove' : 'removing'} ${directory.path}',
        );
        if (!dryRun) {
          await directory.delete(recursive: true);
        }
      } on FileSystemException catch (error) {
        failed = true;
        logger.logError('Could not clean $raw: ${error.message}');
      } on ArgumentError catch (error) {
        failed = true;
        logger.logError(error.message.toString());
      }
    }
    return failed ? 1 : 0;
  }

  Directory _safeOutput(String raw) {
    if (raw.trim().isEmpty) {
      throw ArgumentError('Refusing to clean an empty path.');
    }
    final root = path.normalize(projectRoot.absolute.path);
    final target = path.normalize(
      path.isAbsolute(raw) ? raw : path.join(root, raw),
    );
    if (_samePath(target, root) || !_isWithin(root, target)) {
      throw ArgumentError(
        "Refusing to clean '$raw': output must be inside the project root.",
      );
    }

    final protected = <String>{
      path.normalize(
        path.join(root, Files.androidDistributionMetadataDir.path),
      ),
      path.normalize(path.join(root, Files.iosDistributionMetadataDir.path)),
      path.normalize(path.join(root, Files.customOutputMetadataDir.path)),
      path.normalize(path.join(root, Files.fastlaneJson.path)),
      path.normalize(path.join(root, 'distribution.log')),
      path.normalize(path.join(root, '.distribute')),
      if (ColorizeLogger.logFilePath.isNotEmpty)
        path.normalize(
          path.isAbsolute(ColorizeLogger.logFilePath)
              ? ColorizeLogger.logFilePath
              : path.join(root, ColorizeLogger.logFilePath),
        ),
      for (final item in protectedPaths)
        path.normalize(path.isAbsolute(item) ? item : path.join(root, item)),
    };
    for (final item in protected) {
      if (_samePath(target, item) ||
          _isWithin(target, item) ||
          _isWithin(item, target)) {
        throw ArgumentError(
          "Refusing to clean '$raw': it contains protected metadata, "
          'credentials, logs, or run state.',
        );
      }
    }

    final entityType = FileSystemEntity.typeSync(target, followLinks: false);
    if (entityType == FileSystemEntityType.link) {
      throw ArgumentError("Refusing to clean symlinked output '$raw'.");
    }
    var cursor = root;
    for (final segment in path.split(path.relative(target, from: root))) {
      cursor = path.join(cursor, segment);
      if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw ArgumentError(
          "Refusing to clean '$raw': a parent path is a symlink.",
        );
      }
    }
    return Directory(target);
  }

  static String _comparisonPath(String value) =>
      Platform.isMacOS || Platform.isWindows ? value.toLowerCase() : value;

  static bool _samePath(String first, String second) =>
      _comparisonPath(first) == _comparisonPath(second);

  static bool _isWithin(String parent, String child) => path.isWithin(
        _comparisonPath(parent),
        _comparisonPath(child),
      );
}
