import 'package:args/args.dart';

import '../../parsers/job_arguments.dart';
import '../parser.dart';

class AndroidBuildArgument extends BuildArguments {
  final bool splitPerAbi;
  AndroidBuildArgument({
    super.buildMode,
    required super.binaryType,
    super.target,
    super.flavor,
    super.dartDefines,
    super.dartDefinesFile,
    super.customArgs,
    super.buildName,
    super.buildNumber,
    super.pub,
    this.splitPerAbi = false,
  }) {
    if (binaryType != 'apk' && splitPerAbi) {
      throw ArgumentError('binaryType must be "apk" to use splitPerAbi');
    }
  }

  @override
  List<String> get results => super.results
    ..addAll([if (splitPerAbi && binaryType == 'apk') '--split-per-abi']);

  BuildArguments copyWith(AndroidBuildArgument? data) {
    return AndroidBuildArgument(
      buildMode: data?.buildMode ?? buildMode,
      binaryType: data?.binaryType ?? binaryType,
      target: data?.target ?? target,
      flavor: data?.flavor ?? flavor,
      dartDefines: data?.dartDefines ?? dartDefines,
      dartDefinesFile: data?.dartDefinesFile ?? dartDefinesFile,
      splitPerAbi: data?.splitPerAbi ?? splitPerAbi,
      customArgs: data?.customArgs ?? customArgs,
    );
  }

  static ArgParser parser = ArgParser()
    ..addOption('target',
        abbr: 't',
        help:
            'The main entry-point file of the application, as run on the device.')
    ..addOption('binary-type',
        abbr: 'b', help: 'Binary type (apk, aab)', defaultsTo: 'apk')
    ..addFlag('split-per-abi',
        abbr: 's', help: 'Split APKs by ABI', defaultsTo: false)
    ..addOption('build-mode',
        abbr: 'm',
        help: 'Build mode (debug, profile, release)',
        defaultsTo: 'release')
    ..addOption('flavor', abbr: 'f', help: 'Build flavor')
    ..addOption('arguments',
        abbr: 'a', help: 'Custom arguments to pass to the build command')
    ..addOption('dart-defines', abbr: 'd', help: 'Dart defines')
    ..addOption('build-name', abbr: 'n', help: 'Build name')
    ..addOption('build-number', abbr: 'N', help: 'Build number')
    ..addFlag('pub',
        abbr: 'p', help: 'Run pub get before building', defaultsTo: true)
    ..addOption('dart-defines-file', help: 'Dart defines file');

  static JobArguments defaultConfigs() => AndroidBuildArgument(
        binaryType: 'apk',
        splitPerAbi: false,
        buildMode: 'release',
        buildName: null,
        buildNumber: null,
        pub: true,
        target: null,
        flavor: null,
        dartDefines: null,
        dartDefinesFile: null,
        customArgs: [],
      );

  factory AndroidBuildArgument.fromArgResults(ArgResults results) {
    return AndroidBuildArgument(
      binaryType: results['binary-type'] as String,
      splitPerAbi: results['split-per-abi'] as bool? ?? false,
      buildMode: results['build-mode'] as String?,
      target: results['target'] as String?,
      flavor: results['flavor'] as String?,
      buildName: results['build-name'] as String?,
      buildNumber: results['build-number']?.toString(),
      pub: results['pub'] as bool? ?? true,
      dartDefines: results['dart-defines'] as String?,
      dartDefinesFile: results['dart-defines-file'] as String?,
      customArgs: results['arguments']?.split(' ') as List<String>?,
    );
  }

  factory AndroidBuildArgument.fromJson(Map<String, dynamic> json) {
    return AndroidBuildArgument(
      binaryType: json['binary-type'] ?? "apk",
      splitPerAbi: json['split-per-abi'] as bool? ?? false,
      buildMode: json['build-mode'] as String? ?? 'release',
      target: json['target'] as String?,
      flavor: json['flavor'] as String?,
      buildName: json['build-name'] as String?,
      buildNumber: json['build-number']?.toString(),
      pub: json['pub'] as bool? ?? true,
      dartDefines: json['dart-defines'] as String?,
      dartDefinesFile: json['dart-defines-file'] as String?,
      customArgs: (json['arguments'] as List<dynamic>?)?.cast<String>(),
    );
  }

  @override
  List<String> get argKeys => parser.options.keys.toList();

  @override
  Map<String, dynamic> toJson() => {
        'binary-type': binaryType,
        'split-per-abi': splitPerAbi,
        'build-mode': buildMode,
        'target': target,
        'flavor': flavor,
        'build-name': buildName,
        'build-number': buildNumber,
        'pub': pub,
        'dart-defines': dartDefines,
        'dart-defines-file': dartDefinesFile,
        'arguments': customArgs,
      };
}
