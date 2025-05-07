import 'package:args/args.dart';

import '../../parsers/job_arguments.dart';
import '../parser.dart';

/// Represents the arguments required to build an Android application.
///
/// This class extends [BuildArguments] and includes additional options
/// specific to Android builds, such as splitting APKs by ABI.
class AndroidBuildArgument extends BuildArguments {
  /// Whether to split APKs by ABI.
  ///
  /// This option is only valid when the `binaryType` is set to `apk`.
  final bool splitPerAbi;

  /// Creates an instance of [AndroidBuildArgument].
  ///
  /// [splitPerAbi] - Whether to split APKs by ABI.
  /// Throws an [ArgumentError] if `binaryType` is not `apk` and `splitPerAbi` is true.
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

  /// Returns the list of arguments to be passed to the build command.
  ///
  /// Includes the `--split-per-abi` flag if `splitPerAbi` is true and `binaryType` is `apk`.
  @override
  List<String> get results => super.results
    ..addAll([if (splitPerAbi && binaryType == 'apk') '--split-per-abi']);

  /// Creates a copy of this [AndroidBuildArgument] with updated values.
  ///
  /// [data] - The new values to override the existing ones.
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

  /// The argument parser for Android build arguments.
  ///
  /// Defines the available options and flags for the Android build command.
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

  /// Returns the default configuration for Android builds.
  ///
  /// This includes default values for all required arguments.
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

  /// Creates an instance of [AndroidBuildArgument] from parsed command-line arguments.
  ///
  /// [results] - The parsed arguments from the command-line.
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

  /// Creates an instance of [AndroidBuildArgument] from a JSON object.
  ///
  /// [json] - The JSON object containing the argument values.
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

  /// Returns the list of argument keys supported by this class.
  @override
  List<String> get argKeys => parser.options.keys.toList();

  /// Converts this [AndroidBuildArgument] instance to a JSON object.
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
