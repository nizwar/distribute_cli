import 'package:args/args.dart';
import 'package:distribute_cli/parsers/variables.dart';

import '../../files.dart';
import '../build_arguments.dart';

/// Comprehensive iOS build arguments configuration.
///
/// Extends the base `BuildArguments` class with iOS-specific build options
/// including export methods, provisioning profiles, and distribution settings.
/// Handles IPA generation and various iOS distribution workflows.
///
/// Key iOS features:
/// - IPA (iOS Application Archive) generation
/// - Export options plist configuration for code signing
/// - Multiple export methods for different distribution channels
/// - Integration with Xcode build system and toolchain
///
/// Example usage:
/// ```dart
/// final args = Arguments(
///   variables,
///   binaryType: 'ipa',
///   buildMode: 'release',
///   exportMethod: 'app-store',
/// );
/// ```
class Arguments extends BuildArguments {
  /// Path to the export options plist file for iOS code signing and distribution.
  ///
  /// The export options plist file contains configuration for:
  /// - Code signing identity and provisioning profiles
  /// - Distribution method and target audience
  /// - App thinning and bitcode settings
  /// - Upload symbols and manage version settings
  ///
  /// If not provided, Xcode will use default export options based on
  /// the project's code signing configuration.
  ///
  /// Example path: `/path/to/project/ios/ExportOptions.plist`
  final String? exportOptionsPlist;

  /// The export method for iOS application distribution.
  ///
  /// Determines how the application will be packaged and distributed:
  /// - `app-store` - For App Store distribution (requires distribution certificate)
  /// - `ad-hoc` - For limited device distribution (requires ad-hoc provisioning)
  /// - `enterprise` - For enterprise internal distribution (requires enterprise certificate)
  /// - `development` - For development testing (requires development provisioning)
  ///
  /// Each method has different code signing and provisioning requirements.
  final String? exportMethod;

  /// Creates a new iOS build arguments instance.
  ///
  /// Parameters:
  /// - `variables` - Variable processor for argument substitution
  /// - `buildMode` - Build mode (debug, profile, release)
  /// - `binaryType` - Output type (typically 'ipa' for iOS)
  /// - `output` - Output directory path for the built IPA
  /// - `target` - Entry point file path for the application
  /// - `flavor` - Build flavor for multi-flavor builds
  /// - `dartDefines` - Compile-time constants for conditional compilation
  /// - `dartDefinesFile` - File containing compile-time constants
  /// - `customArgs` - Additional custom arguments for the build process
  /// - `buildName` - Version name for the build (CFBundleShortVersionString)
  /// - `buildNumber` - Version code for the build (CFBundleVersion)
  /// - `pub` - Whether to run pub get before building
  /// - `exportOptionsPlist` - Path to export options plist file
  /// - `exportMethod` - Distribution method (app-store, ad-hoc, enterprise, development)
  ///
  /// Sets the build source directory to the iOS IPA output location automatically.
  Arguments(
    super.variables, {
    super.buildMode,
    required super.binaryType,
    super.output,
    super.target,
    super.flavor,
    super.dartDefines,
    super.dartDefinesFile,
    super.customArgs,
    super.buildName,
    super.buildNumber,
    super.pub,
    this.exportOptionsPlist,
    this.exportMethod,
  }) : super(buildSourceDir: Files.iosOutputIPA.path);

  /// Creates a copy of this iOS arguments instance with updated values.
  ///
  /// - `data` - New iOS arguments to merge with current instance
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
  ///   binaryType: 'ipa',
  ///   buildMode: 'release',
  ///   exportMethod: 'app-store',
  /// ));
  /// ```
  Arguments copyWith(Arguments? data) {
    return Arguments(
      data?.variables ?? variables,
      buildMode: data?.buildMode ?? buildMode,
      binaryType: data?.binaryType ?? binaryType,
      flavor: data?.flavor ?? flavor,
      dartDefines: data?.dartDefines ?? dartDefines,
      dartDefinesFile: data?.dartDefinesFile ?? dartDefinesFile,
      customArgs: data?.customArgs ?? customArgs,
      target: data?.target ?? target,
      buildName: data?.buildName ?? buildName,
      buildNumber: data?.buildNumber ?? buildNumber,
      pub: data?.pub ?? pub,
      exportOptionsPlist: data?.exportOptionsPlist ?? exportOptionsPlist,
      exportMethod: data?.exportMethod ?? exportMethod,
      output: data?.output ?? output,
    );
  }

  /// Command-line argument parser for iOS build configuration.
  ///
  /// Defines all available command-line options for iOS builds including:
  /// - Basic build options (target, binary-type, build-mode, flavor)
  /// - Build configuration (arguments, dart-defines, build-name, build-number)
  /// - iOS-specific options (export-options-plist, export-method)
  /// - Output and dependency management (output, pub)
  ///
  /// Used to parse command-line arguments into structured iOS build configuration.
  static ArgParser parser = ArgParser()
    ..addOption('target',
        abbr: 't',
        help:
            'The main entry-point file of the application, as run on the device.')
    ..addOption('binary-type',
        abbr: 'b', help: 'Binary type (ipa, ios)', defaultsTo: 'ipa')
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
    ..addOption('export-options-plist',
        help: 'Path to export options plist file')
    ..addOption('export-method',
        help: 'Export method (ad-hoc, app-store, enterprise, development)')
    ..addFlag('pub',
        abbr: 'p', help: 'Run pub get before building', defaultsTo: true)
    ..addOption("output",
        abbr: 'o',
        help: 'Output path for the build',
        defaultsTo: Files.iosDistributionOutputDir.path)
    ..addOption('dart-defines-file', help: 'Dart defines file');

  /// Creates an iOS arguments instance from parsed command-line arguments.
  ///
  /// - `results` - Parsed command-line arguments specific to this command
  /// - `globalResults` - Global command-line arguments shared across commands
  ///
  /// Returns a new `Arguments` instance configured with values from the
  /// command-line arguments, with appropriate defaults for unspecified options.
  ///
  /// The binary type defaults to the first positional argument or 'ipa' if none provided.
  factory Arguments.fromArgResults(
      ArgResults results, ArgResults? globalResults) {
    return Arguments(
      Variables.fromSystem(globalResults),
      buildMode: results['build-mode'] as String?,
      binaryType: results.rest.firstOrNull ?? 'ipa',
      target: results['target'] as String?,
      flavor: results['flavor'] as String?,
      dartDefines: results['dart-defines'] as String?,
      dartDefinesFile: results['dart-defines-file'] as String?,
      buildName: results['build-name'] as String?,
      buildNumber: results['build-number']?.toString(),
      pub: results['pub'] as bool? ?? true,
      exportOptionsPlist: results['export-options-plist'] as String?,
      exportMethod: results['export-method'] as String?,
      customArgs: results['arguments']?.split(' ') as List<String>?,
      output:
          results['output'] as String? ?? Files.iosDistributionOutputDir.path,
    );
  }

  /// Creates an iOS arguments instance from JSON configuration.
  ///
  /// - `json` - JSON object containing iOS build configuration
  /// - `variables` - Variable processor for argument substitution
  ///
  /// Returns a new `Arguments` instance with configuration parsed from the
  /// JSON object. Provides sensible defaults for missing values.
  ///
  /// Expected JSON structure:
  /// ```json
  /// {
  ///   "binary-type": "ipa",
  ///   "build-mode": "release",
  ///   "export-method": "app-store",
  ///   "export-options-plist": "/path/to/ExportOptions.plist"
  /// }
  /// ```
  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    return Arguments(
      variables,
      output: json['output'] as String? ?? Files.iosDistributionOutputDir.path,
      binaryType: json['binary-type'] ?? "ipa",
      buildMode: json['build-mode'] as String?,
      target: json['target'] as String?,
      flavor: json['flavor'] as String?,
      dartDefines: json['dart-defines'] as String?,
      dartDefinesFile: json['dart-defines-file'] as String?,
      buildName: json['build-name'] as String?,
      buildNumber: json['build-number']?.toString(),
      pub: json['pub'] as bool? ?? true,
      exportOptionsPlist: json['export-options-plist'] as String?,
      exportMethod: json['export-method'] as String?,
      customArgs: (json['arguments'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Returns the default iOS build configuration.
  ///
  /// - `globalResults` - Global command-line arguments for variable processing
  ///
  /// Creates a default iOS build configuration suitable for most release builds:
  /// - Binary type: 'ipa'
  /// - Build mode: 'release'
  /// - Output: iOS distribution directory
  /// - Pub: enabled (runs pub get before building)
  /// - No specific export method or options plist
  ///
  /// This configuration can be used as a starting point and customized as needed.
  static Arguments defaultConfigs(ArgResults? globalResults) => Arguments(
        Variables.fromSystem(globalResults),
        binaryType: 'ipa',
        buildMode: 'release',
        target: null,
        flavor: null,
        dartDefines: null,
        dartDefinesFile: null,
        buildName: null,
        buildNumber: null,
        pub: true,
        exportOptionsPlist: null,
        exportMethod: null,
        output: Files.iosDistributionOutputDir.path,
        customArgs: [],
      );

  /// Converts the iOS arguments to JSON representation.
  ///
  /// Returns a `Map<String, dynamic>` containing all iOS-specific configuration
  /// values. This JSON representation can be used for:
  /// - Configuration file serialization
  /// - API communication
  /// - Build configuration logging
  /// - Configuration persistence and restoration
  ///
  /// The returned map includes all build parameters with their current values,
  /// including null values for optional parameters.
  @override
  Map<String, dynamic> toJson() => {
        'binary-type': binaryType,
        'build-mode': buildMode,
        'target': target,
        'flavor': flavor,
        'dart-defines': dartDefines,
        'dart-defines-file': dartDefinesFile,
        'build-name': buildName,
        'build-number': buildNumber,
        'export-options-plist': exportOptionsPlist,
        'export-method': exportMethod,
        'arguments': customArgs,
        'pub': pub,
        'output': output,
      };

  /// Builds the command-line arguments list for the iOS build process.
  ///
  /// Returns a list of command-line arguments to be passed to the Flutter
  /// build command. Combines base build arguments with iOS-specific options.
  ///
  /// iOS-specific arguments added:
  /// - `--export-options-plist` - Path to export options plist file
  /// - `--export-method` - Distribution method (app-store, ad-hoc, etc.)
  ///
  /// These arguments control iOS-specific build behavior including code signing,
  /// provisioning profiles, and distribution method configuration.
  @override
  List<String> get argumentBuilder => super.argumentBuilder
    ..addAll([
      // Export options plist for code signing configuration
      if (exportOptionsPlist != null)
        '--export-options-plist=$exportOptionsPlist',

      // Export method for distribution type
      if (exportMethod != null) '--export-method=$exportMethod',
    ]);
}
