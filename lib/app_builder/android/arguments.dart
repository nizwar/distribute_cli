import 'package:args/args.dart';
import 'package:distribute_cli/parsers/variables.dart';

import '../../files.dart';
import '../build_arguments.dart';

/// Comprehensive Android build arguments configuration.
///
/// Extends the base `BuildArguments` class with Android-specific build options
/// including APK/AAB generation, ABI splitting, debug symbols, obfuscation,
/// and various optimization settings.
///
/// Key Android features:
/// - APK and Android App Bundle (AAB) generation
/// - ABI-specific APK splitting for reduced download sizes
/// - Debug symbol generation for crash analysis
/// - Code obfuscation for release builds
/// - Build dependency validation controls
/// - Size analysis and widget tracking options
///
/// Example usage:
/// ```dart
/// final args = Arguments(
///   variables,
///   binaryType: 'apk',
///   buildMode: 'release',
///   splitPerAbi: true,
///   obfuscate: true,
///   generateDebugSymbols: true,
/// );
/// ```
class Arguments extends BuildArguments {
  /// Enables APK splitting by Application Binary Interface (ABI).
  ///
  /// When `true`, generates separate APK files for different device
  /// architectures (arm64-v8a, armeabi-v7a, x86_64). This reduces
  /// download size as users only get the APK for their device architecture.
  ///
  /// Only valid when `binaryType` is set to "apk". Setting this to `true`
  /// with AAB binary type will throw an `ArgumentError`.
  ///
  /// Default: `false`
  final bool splitPerAbi;

  /// Controls debug symbol generation for crash reporting and debugging.
  ///
  /// When `true`, generates debug symbols that can be uploaded to
  /// crash reporting services like Firebase Crashlytics or Play Console
  /// for better crash analysis and stack trace resolution.
  ///
  /// Default: `true`
  final bool generateDebugSymbols;

  /// Whether to only generate build configuration without building.
  ///
  /// When `true`, performs configuration checks and setup without
  /// actually building the application. Useful for validating
  /// build configurations.
  final bool? configOnly;

  /// Controls widget creation tracking for debugging.
  ///
  /// When enabled, tracks widget creation locations which helps with
  /// debugging widget-related issues but adds overhead to the build.
  ///
  /// Values:
  /// - `true` - Enable widget creation tracking
  /// - `false` - Disable widget creation tracking
  /// - `null` - Use default Flutter behavior
  final bool? trackWidgetCreation;

  /// Skips Android build dependency validation.
  ///
  /// When `true`, bypasses dependency validation checks which can
  /// speed up builds but may lead to runtime issues if dependencies
  /// are incompatible.
  ///
  /// Values:
  /// - `true` - Skip dependency validation
  /// - `false` - Perform dependency validation
  /// - `null` - Use default behavior
  final bool? androidSkipBuildDependencyValidation;

  /// Enables size analysis of the built application.
  ///
  /// When `true`, generates detailed size analysis reports showing
  /// the contribution of different components to the final app size.
  /// Useful for optimizing app size.
  ///
  /// Values:
  /// - `true` - Enable size analysis
  /// - `false` - Disable size analysis
  /// - `null` - Use default behavior
  final bool? analyzeSize;

  /// Ignores deprecation warnings during build.
  ///
  /// When `true`, suppresses deprecation warnings which can clean up
  /// build output but may hide important API migration information.
  final bool? ignoreDeprecation;

  /// Enables code obfuscation for release builds.
  ///
  /// When `true`, obfuscates Dart code to make reverse engineering
  /// more difficult. Recommended for production releases to protect
  /// intellectual property.
  ///
  /// Values:
  /// - `true` - Enable obfuscation
  /// - `false` - Disable obfuscation
  /// - `null` - Use default behavior (typically enabled for release)
  final bool? obfuscate;

  /// Specifies the target platform architecture.
  ///
  /// Defines the specific platform architecture to build for.
  /// Common values include:
  /// - "android-arm64" - ARM 64-bit architecture
  /// - "android-arm" - ARM 32-bit architecture
  /// - "android-x64" - x86 64-bit architecture
  final String? targetPlatform;

  /// Additional arguments to pass to the Android project build.
  ///
  /// Allows passing custom arguments directly to the underlying
  /// Android Gradle build system for advanced configuration.
  final String? androidProjectArg;

  /// Directory path for storing code size analysis output.
  ///
  /// When size analysis is enabled, this specifies where to store
  /// the detailed size breakdown files and reports.
  final String? codeSizeDirectory;

  /// Path for split debug information storage.
  ///
  /// Specifies where to store debug symbols when they are separated
  /// from the main binary. Used for symbolication of crash reports
  /// while keeping the main binary smaller.
  final String? splitDebugInfo;

  /// Creates a new Android build arguments instance.
  ///
  /// Parameters:
  /// - `variables` - Variable processor for argument substitution
  /// - `buildMode` - Build mode (debug, profile, release)
  /// - `binaryType` - Output type (apk or aab)
  /// - `target` - Entry point file path
  /// - `flavor` - Build flavor for multi-flavor builds
  /// - `dartDefines` - Compile-time constants
  /// - `dartDefinesFile` - File containing compile-time constants
  /// - `customArgs` - Additional custom arguments
  /// - `buildName` - Version name for the build
  /// - `buildNumber` - Version code for the build
  /// - `pub` - Whether to run pub get before building
  /// - `output` - Output directory path
  /// - `splitPerAbi` - Enable ABI-specific APK splitting
  /// - `generateDebugSymbols` - Generate debug symbols
  /// - `configOnly` - Only generate configuration
  /// - `trackWidgetCreation` - Enable widget creation tracking
  /// - `androidSkipBuildDependencyValidation` - Skip dependency validation
  /// - `analyzeSize` - Enable size analysis
  /// - `ignoreDeprecation` - Ignore deprecation warnings
  /// - `obfuscate` - Enable code obfuscation
  /// - `targetPlatform` - Target platform architecture
  /// - `androidProjectArg` - Additional Android project arguments
  /// - `codeSizeDirectory` - Directory for size analysis output
  /// - `splitDebugInfo` - Path for debug info storage
  ///
  /// Throws `ArgumentError` if `splitPerAbi` is `true` and `binaryType` is not "apk".
  Arguments(
    super.variables, {
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
    // Validate that splitPerAbi is only used with APK binary type
    if (binaryType != 'apk' && splitPerAbi) {
      throw ArgumentError('binaryType must be "apk" to use splitPerAbi');
    }
  }

  /// Builds the command-line arguments list for the Android build process.
  ///
  /// Returns a list of command-line arguments to be passed to the Flutter
  /// build command. Combines base build arguments with Android-specific
  /// options based on the configuration.
  ///
  /// Android-specific arguments added:
  /// - `--split-per-abi` - When `splitPerAbi` is true and binary type is APK
  /// - `--config-only` - When only configuration generation is needed
  /// - `--track-widget-creation` / `--no-track-widget-creation` - Widget tracking control
  /// - `--android-skip-build-dependency-validation` - Dependency validation control
  /// - `--analyze-size` / `--no-analyze-size` - Size analysis control
  /// - `--ignore-deprecation` - Deprecation warning control
  /// - `--obfuscate` / `--no-obfuscate` - Code obfuscation control
  /// - `--target-platform` - Target platform specification
  /// - `--android-project-arg` - Additional Android project arguments
  /// - `--code-size-directory` - Size analysis output directory
  /// - `--split-debug-info` - Debug info storage path
  @override
  List<String> get argumentBuilder => super.argumentBuilder
    ..addAll([
      // Add APK splitting only for APK binary type
      if (splitPerAbi && binaryType == 'apk') '--split-per-abi',

      // Configuration-only build
      if (configOnly == true) '--config-only',

      // Widget creation tracking control
      if (trackWidgetCreation != null)
        if (trackWidgetCreation == true)
          '--track-widget-creation'
        else
          '--no-track-widget-creation',

      // Android build dependency validation control
      if (androidSkipBuildDependencyValidation != null)
        if (androidSkipBuildDependencyValidation == true)
          '--android-skip-build-dependency-validation'
        else
          '--no-android-skip-build-dependency-validation',

      // Size analysis control
      if (analyzeSize != null)
        if (analyzeSize == true) '--analyze-size' else '--no-analyze-size',

      // Deprecation warning control
      if (ignoreDeprecation != null)
        if (ignoreDeprecation == true) '--ignore-deprecation',

      // Code obfuscation control
      if (obfuscate != null)
        if (obfuscate == true) '--obfuscate' else '--no-obfuscate',

      // Target platform specification
      if (targetPlatform != null) '--target-platform=$targetPlatform',

      // Additional Android project arguments
      if (androidProjectArg != null) '--android-project-arg=$androidProjectArg',

      // Code size analysis output directory
      if (codeSizeDirectory != null) '--code-size-directory=$codeSizeDirectory',

      // Debug info storage path
      if (splitDebugInfo != null) '--split-debug-info=$splitDebugInfo',
    ]);

  /// Creates a copy of this Android arguments instance with updated values.
  ///
  /// - `data` - New Android arguments to merge with current instance
  ///
  /// Returns a new `Arguments` instance with values from `data` taking
  /// precedence over current values. Null values in `data` will preserve
  /// the corresponding values from the current instance.
  ///
  /// This method is useful for creating variants of build configurations
  /// without modifying the original instance.
  ///
  /// Example usage:
  /// ```dart
  /// final releaseArgs = debugArgs.copyWith(Arguments(
  ///   variables,
  ///   binaryType: 'aab',
  ///   buildMode: 'release',
  ///   obfuscate: true,
  /// ));
  /// ```
  BuildArguments copyWith(Arguments? data) {
    return Arguments(
      data?.variables ?? variables,
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
        help: 'Target platform (android-arm, android-arm64, android-x64)')
    ..addOption('android-project-arg', help: 'Android project argument')
    ..addOption('code-size-directory', help: 'Code size directory')
    ..addOption('split-debug-info', help: 'Split debug info');

  /// Returns the default configuration for Android builds.
  ///
  /// This includes default values for all required arguments.
  factory Arguments.defaultConfigs(ArgResults? globalResults) => Arguments(
        Variables.fromSystem(globalResults),
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
  factory Arguments.fromArgResults(
      ArgResults results, ArgResults? globalResults) {
    return Arguments(
      Variables.fromSystem(globalResults),
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
  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    return Arguments(
      variables,
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
