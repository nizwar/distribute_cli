import 'package:args/args.dart';

import 'clean_service.dart';
import 'command.dart';
import 'files.dart';
import 'parsers/config_parser.dart';

/// Removes Flutter build products and/or configured distribution outputs.
class CleanCommand extends Commander {
  @override
  String get name => 'clean';

  @override
  String get description =>
      'Clean Flutter build products and distribution output directories.';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'distribution.yaml',
      help: 'Configuration used to discover custom output directories.',
    )
    ..addFlag('flutter', negatable: false, help: 'Run flutter clean.')
    ..addFlag('outputs', negatable: false, help: 'Remove distribution outputs.')
    ..addFlag('all', negatable: false, help: 'Clean Flutter and outputs.')
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Print what would be removed without changing files.',
    );

  @override
  Future<int> run() async {
    final all = argResults!['all'] as bool;
    final selectedFlutter = argResults!['flutter'] as bool;
    final selectedOutputs = argResults!['outputs'] as bool;
    final noSelection = !all && !selectedFlutter && !selectedOutputs;
    final protectedPaths = <String>{};
    var failure = 0;
    if (all || selectedOutputs || noSelection) {
      final outputs = <String>{
        Files.androidDistributionOutputDir.path,
        Files.iosDistributionOutputDir.path,
        Files.customOutputDir.path,
      };
      try {
        final config =
            await ConfigParser.distributeYaml(configPath, globalResults);
        outputs.addAll(config.builderOutputDirectories());
        protectedPaths.addAll(config.protectedCredentialFiles());
      } on ConfigException catch (error) {
        logger.logWarning(
          'Could not read $configPath; cleaning default outputs only: '
          '${error.message}',
        );
      }
      final service = CleanService(
        logger,
        dryRun: argResults!['dry-run'] as bool,
        protectedPaths: protectedPaths,
      );
      final outputFailure = await service.outputs(outputs);
      if (failure == 0) failure = outputFailure;
    }
    if (all || selectedFlutter || noSelection) {
      final service = CleanService(
        logger,
        dryRun: argResults!['dry-run'] as bool,
        protectedPaths: protectedPaths,
      );
      final flutterFailure = await service.flutterClean();
      if (failure == 0) failure = flutterFailure;
    }
    return failure;
  }
}
