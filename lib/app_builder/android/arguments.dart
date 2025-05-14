import 'package:args/args.dart';

import '../../files.dart';
import '../build_arguments.dart';

/// Arguments required to build an Android application.
///
/// This class extends [BuildArguments] and includes additional options
/// specific to Android builds, such as splitting APKs by ABI and debug symbols.
class Arguments extends BuildArguments {
  /// Whether to split APKs by ABI. Only valid when `binaryType` is `apk`.
  final bool splitPerAbi;

  /// Whether to generate debug symbols.
  final bool generateDebugSymbols;
  final bool? configOnly;
  final bool? trackWidgetCreation;
  final bool? androidSkipBuildDependencyValidation;
  final bool? analyzeSize;
  final bool? ignoreDeprecation;
  final bool? obfuscate;
  final String? targetPlatform;
  final String? androidProjectArg;
  final String? codeSizeDirectory;
  final String? splitDebugInfo;

  /// Creates an instance of [Arguments] for Android builds.
  ///
  /// Throws an [ArgumentError] if `binaryType` is not `apk` and `splitPerAbi` is true.
  Arguments({
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
    super.output,
    this.splitPerAbi = false,
    this.generateDebugSymbols = true,
    this.configOnly,
    this.trackWidgetCreation,
    this.androidSkipBuildDependencyValidation,
    this.analyzeSize,
    this.ignoreDeprecation,
    this.obfuscate,
    this.targetPlatform,
    this.androidProjectArg,
    this.codeSizeDirectory,
    this.splitDebugInfo,
  }) : super(
            buildSourceDir: binaryType == "apk"
                ? Files.androidOutputApks.path
                : Files.androidOutputAppbundles.path) {
    if (binaryType != 'apk' && splitPerAbi) {
      throw ArgumentError('binaryType must be "apk" to use splitPerAbi');
    }
  }

  /// Returns the list of arguments to be passed to the build command.
  ///
  /// Includes the `--split-per-abi` flag if `splitPerAbi` is true and `binaryType` is `apk`.
  @override
  List<String> get results => super.results
    ..addAll([
      if (splitPerAbi && binaryType == 'apk') '--split-per-abi',
      if (configOnly == true) '--config-only',
      if (trackWidgetCreation != null)
        if (trackWidgetCreation == true)
          '--track-widget-creation'
        else
          '--no-track-widget-creation',
      if (androidSkipBuildDependencyValidation != null)
        if (androidSkipBuildDependencyValidation == true)
          '--android-skip-build-dependency-validation'
        else
          '--no-android-skip-build-dependency-validation',
      if (analyzeSize != null)
        if (analyzeSize == true) '--analyze-size' else '--no-analyze-size',
      if (ignoreDeprecation != null)
        if (ignoreDeprecation == true) '--ignore-deprecation',
      if (obfuscate != null)
        if (obfuscate == true) '--obfuscate' else '--no-obfuscate',
      if (targetPlatform != null) '--target-platform=$targetPlatform',
      if (androidProjectArg != null) '--android-project-arg=$androidProjectArg',
      if (codeSizeDirectory != null) '--code-size-directory=$codeSizeDirectory',
      if (splitDebugInfo != null) '--split-debug-info=$splitDebugInfo',
    ]);

  /// Creates a copy of this [Arguments] with updated values.
  ///
  /// [data] - The new values to override the existing ones.
  BuildArguments copyWith(Arguments? data) {
    return Arguments(
      buildMode: data?.buildMode ?? buildMode,
      binaryType: data?.binaryType ?? binaryType,
      target: data?.target ?? target,
      flavor: data?.flavor ?? flavor,
      dartDefines: data?.dartDefines ?? dartDefines,
      dartDefinesFile: data?.dartDefinesFile ?? dartDefinesFile,
      splitPerAbi: data?.splitPerAbi ?? splitPerAbi,
      customArgs: data?.customArgs ?? customArgs,
      buildName: data?.buildName ?? buildName,
      buildNumber: data?.buildNumber ?? buildNumber,
      pub: data?.pub ?? pub,
      output: data?.output ?? output,
      generateDebugSymbols: data?.generateDebugSymbols ?? generateDebugSymbols,
      configOnly: data?.configOnly ?? configOnly,
      trackWidgetCreation: data?.trackWidgetCreation ?? trackWidgetCreation,
      androidSkipBuildDependencyValidation:
          data?.androidSkipBuildDependencyValidation ??
              androidSkipBuildDependencyValidation,
      analyzeSize: data?.analyzeSize ?? analyzeSize,
      ignoreDeprecation: data?.ignoreDeprecation ?? ignoreDeprecation,
      obfuscate: data?.obfuscate ?? obfuscate,
      targetPlatform: data?.targetPlatform ?? targetPlatform,
      androidProjectArg: data?.androidProjectArg ?? androidProjectArg,
      codeSizeDirectory: data?.codeSizeDirectory ?? codeSizeDirectory,
      splitDebugInfo: data?.splitDebugInfo ?? splitDebugInfo,
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
    ..addFlag('generate-debug-symbols',
        abbr: 'g', help: 'Generate debug symbols', defaultsTo: true)
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
    ..addOption('output',
        abbr: 'o',
        help: 'Output path for the build',
        defaultsTo: Files.androidDistributionOutputDir.path)
    ..addOption('dart-defines-file', help: 'Dart defines file')
    ..addFlag('pub',
        abbr: 'p', help: 'Run pub get before building', defaultsTo: true)
    ..addFlag('config-only',
        help: 'Only generate the configuration file', defaultsTo: false)
    ..addFlag('track-widget-creation',
        help: 'Track widget creation', defaultsTo: false)
    ..addFlag('android-skip-build-dependency-validation',
        help: 'Skip build dependency validation', defaultsTo: false)
    ..addFlag('analyze-size', help: 'Analyze size', defaultsTo: false)
    ..addFlag('ignore-deprecation',
        help: 'Ignore deprecation warnings', defaultsTo: false)
    ..addFlag('obfuscate', help: 'Obfuscate the code', defaultsTo: false)
    ..addOption('target-platform',
        help: 'Target platform (android-arm, android-arm64, android-x64)',
        defaultsTo: 'android-arm')
    ..addOption('android-project-arg', help: 'Android project argument')
    ..addOption('code-size-directory', help: 'Code size directory')
    ..addOption('split-debug-info', help: 'Split debug info');

  /// Returns the default configuration for Android builds.
  ///
  /// This includes default values for all required arguments.
  factory Arguments.defaultConfigs() => Arguments(
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
        output: Files.androidDistributionOutputDir.path,
        generateDebugSymbols: true,
        customArgs: [],
      );

  /// Creates an instance of [Arguments] from parsed command-line arguments.
  ///
  /// [results] - The parsed arguments from the command-line.
  factory Arguments.fromArgResults(ArgResults results) {
    return Arguments(
      binaryType: results['binary-type'] as String,
      splitPerAbi: results['split-per-abi'] as bool? ?? false,
      output: results['output'] as String? ??
          Files.androidDistributionOutputDir.path,
      buildMode: results['build-mode'] as String?,
      target: results['target'] as String?,
      flavor: results['flavor'] as String?,
      buildName: results['build-name'] as String?,
      buildNumber: results['build-number']?.toString(),
      pub: results['pub'] as bool? ?? true,
      dartDefines: results['dart-defines'] as String?,
      dartDefinesFile: results['dart-defines-file'] as String?,
      customArgs: results['arguments']?.split(' ') as List<String>?,
      generateDebugSymbols: results['generate-debug-symbols'] as bool? ?? true,
      configOnly: results['config-only'] as bool? ?? false,
      trackWidgetCreation: results['track-widget-creation'] as bool? ?? false,
      androidSkipBuildDependencyValidation:
          results['android-skip-build-dependency-validation'] as bool? ?? false,
      analyzeSize: results['analyze-size'] as bool? ?? false,
      ignoreDeprecation: results['ignore-deprecation'] as bool? ?? false,
      obfuscate: results['obfuscate'] as bool? ?? false,
      targetPlatform: results['target-platform'] as String?,
      androidProjectArg: results['android-project-arg'] as String?,
      codeSizeDirectory: results['code-size-directory'] as String?,
      splitDebugInfo: results['split-debug-info'] as String?,
    );
  }

  /// Creates an instance of [Arguments] from a JSON object.
  ///
  /// [json] - The JSON object containing the argument values.
  factory Arguments.fromJson(Map<String, dynamic> json) {
    return Arguments(
      binaryType: json['binary-type'] ?? "apk",
      splitPerAbi: json['split-per-abi'] as bool? ?? false,
      buildMode: json['build-mode'] as String? ?? 'release',
      output:
          json['output'] as String? ?? Files.androidDistributionOutputDir.path,
      target: json['target'] as String?,
      flavor: json['flavor'] as String?,
      buildName: json['build-name'] as String?,
      buildNumber: json['build-number']?.toString(),
      pub: json['pub'] as bool? ?? true,
      dartDefines: json['dart-defines'] as String?,
      dartDefinesFile: json['dart-defines-file'] as String?,
      customArgs: (json['arguments'] as List<dynamic>?)?.cast<String>(),
      generateDebugSymbols: json['generate-debug-symbols'] as bool? ?? true,
      configOnly: json['config-only'] as bool?,
      trackWidgetCreation: json['track-widget-creation'] as bool?,
      androidSkipBuildDependencyValidation:
          json['android-skip-build-dependency-validation'] as bool?,
      analyzeSize: json['analyze-size'] as bool?,
      ignoreDeprecation: json['ignore-deprecation'] as bool?,
      obfuscate: json['obfuscate'] as bool?,
      targetPlatform: json['target-platform'] as String?,
      androidProjectArg: json['android-project-arg'] as String?,
      codeSizeDirectory: json['code-size-directory'] as String?,
      splitDebugInfo: json['split-debug-info'] as String?,
    );
  }

  /// Converts this [Arguments] instance to a JSON object.
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
        'output': output,
        'generate-debug-symbols': generateDebugSymbols,
        'config-only': configOnly,
        'track-widget-creation': trackWidgetCreation,
        'android-skip-build-dependency-validation':
            androidSkipBuildDependencyValidation,
        'analyze-size': analyzeSize,
        'ignore-deprecation': ignoreDeprecation,
        'obfuscate': obfuscate,
        'target-platform': targetPlatform,
        'android-project-arg': androidProjectArg,
        'code-size-directory': codeSizeDirectory,
        'split-debug-info': splitDebugInfo,
      };
}
