import 'package:args/args.dart';
import 'package:distribute_cli/parsers/variables.dart';

import '../../files.dart';
import '../build_arguments.dart';

/// Configuration class for custom build process arguments.
///
/// This class extends `BuildArguments` to provide comprehensive configuration
/// options for custom build workflows. It supports flexible binary type
/// specification, user-defined arguments, and advanced build customization
/// that can accommodate diverse project requirements and build environments.
///
/// ## Key Capabilities
///
/// - **Binary Type Flexibility**: Supports any binary output format specification
/// - **Custom Arguments**: Allows passing arbitrary arguments to build commands
/// - **Build Mode Control**: Configurable debug, profile, and release modes
/// - **Flavor Support**: Product flavor and variant management
/// - **Dart Compilation**: Advanced Dart define and compilation options
/// - **Output Customization**: Flexible output path and naming control
/// - **Build Integration**: Compatible with existing build systems and tools
///
/// ## Configuration Options
///
/// The class manages various build parameters:
/// - Binary output format and type specification
/// - Build mode and optimization settings
/// - Custom command-line arguments for specialized builds
/// - Source directory and target file configuration
/// - Dart compilation defines and build metadata
/// - Output path management and file naming
///
/// ## Example Usage
///
/// ```dart
/// // Create custom build configuration
/// final args = Arguments(
///   variables,
///   binaryType: 'aab',
///   buildMode: 'release',
///   customArgs: ['--verbose', '--analyze-size'],
///   flavor: 'production',
///   output: './custom-builds/',
/// );
///
/// // Execute custom build
/// final result = await args.build();
/// ```
class Arguments extends BuildArguments {
  /// Creates a new custom build arguments configuration.
  ///
  /// Initializes the custom build arguments with comprehensive parameter support
  /// for flexible build workflows. All parameters except `variables`, `binaryType`,
  /// and `buildSourceDir` are optional to provide maximum configuration flexibility.
  ///
  /// ## Parameters
  ///
  /// - `variables` - System and environment variables for build context
  /// - `buildMode` - Build optimization mode (debug, profile, release)
  /// - `binaryType` - Required output binary format specification
  /// - `buildSourceDir` - Required source directory path for build input
  /// - `target` - Main entry-point file for application execution
  /// - `flavor` - Product flavor or build variant identifier
  /// - `dartDefines` - Dart compilation define values
  /// - `dartDefinesFile` - File containing Dart define configurations
  /// - `buildName` - Human-readable build version name
  /// - `buildNumber` - Numeric build version identifier
  /// - `pub` - Flag to run pub get before building
  /// - `output` - Custom output directory path for build artifacts
  /// - `customArgs` - Additional arguments passed to build command
  ///
  /// ## Example
  ///
  /// ```dart
  /// final args = Arguments(
  ///   systemVariables,
  ///   binaryType: 'aab',
  ///   buildMode: 'release',
  ///   buildSourceDir: './lib',
  ///   flavor: 'production',
  ///   customArgs: ['--verbose', '--tree-shake-icons'],
  ///   output: './builds/custom/',
  /// );
  /// ```
  Arguments(
    super.variables, {
    super.buildMode,
    required super.binaryType,
    required super.buildSourceDir,
    super.target,
    super.flavor,
    super.dartDefines,
    super.dartDefinesFile,
    super.buildName,
    super.buildNumber,
    super.pub,
    super.output,
    super.customArgs,
  });

  /// Creates a copy of this Arguments instance with selective updates.
  ///
  /// This method provides immutable update capabilities by creating a new
  /// `Arguments` instance with values from the provided `data` parameter,
  /// falling back to current instance values where `data` doesn't specify
  /// new values. This supports configuration inheritance and modification.
  ///
  /// ## Parameters
  ///
  /// - `data` - Optional Arguments instance containing updated values
  ///
  /// ## Returns
  ///
  /// Returns a new `BuildArguments` instance (as `Arguments`) with:
  /// - Values from `data` where specified
  /// - Current instance values where `data` is null or doesn't specify
  /// - All original configuration preserved for unspecified parameters
  ///
  /// ## Example
  ///
  /// ```dart
  /// final baseArgs = Arguments(variables, binaryType: 'apk', buildMode: 'debug');
  /// final releaseArgs = Arguments(variables, buildMode: 'release');
  ///
  /// // Create release version with base configuration
  /// final updatedArgs = baseArgs.copyWith(releaseArgs);
  /// // Result: APK binary type with release build mode
  /// ```
  BuildArguments copyWith(Arguments? data) {
    return Arguments(
      data?.variables ?? variables,
      buildMode: data?.buildMode ?? buildMode,
      binaryType: data?.binaryType ?? binaryType,
      customArgs: data?.customArgs ?? customArgs,
      target: data?.target ?? target,
      flavor: data?.flavor ?? flavor,
      dartDefines: data?.dartDefines ?? dartDefines,
      dartDefinesFile: data?.dartDefinesFile ?? dartDefinesFile,
      buildName: data?.buildName ?? buildName,
      buildNumber: data?.buildNumber ?? buildNumber,
      pub: data?.pub ?? pub,
      output: data?.output ?? output,
      buildSourceDir: data?.buildSourceDir ?? buildSourceDir,
    );
  }

  /// Command-line argument parser for custom build configuration.
  ///
  /// This static parser defines all available command-line options and flags
  /// for custom build processes. It provides comprehensive configuration
  /// capabilities including binary type specification, build modes, custom
  /// arguments, and output path management.
  ///
  /// ## Available Options
  ///
  /// - `target` (`-t`) - Main entry-point file for device execution
  /// - `binary-type` (`-b`) - Output binary format (apk, aab, ipa, etc.)
  /// - `build-mode` (`-m`) - Build optimization level (debug, profile, release)
  /// - `flavor` (`-f`) - Product flavor or build variant specification
  /// - `arguments` (`-a`) - Custom arguments for specialized build commands
  /// - `dart-defines` (`-d`) - Dart compilation define values
  /// - `build-name` (`-n`) - Human-readable version name
  /// - `build-number` (`-N`) - Numeric version identifier
  /// - `output` (`-o`) - Output directory path for build artifacts
  /// - `pub` (`-p`) - Flag to run pub get before building
  /// - `dart-defines-file` - File containing Dart define configurations
  ///
  /// ## Default Values
  ///
  /// - `binary-type`: 'apk' - Default Android APK output
  /// - `build-mode`: 'release' - Optimized production builds
  /// - `output`: Custom output directory path from Files.customOutputDir
  /// - `pub`: true - Automatically run dependency resolution
  ///
  /// ## Usage Examples
  ///
  /// ```bash
  /// # Basic custom build
  /// --binary-type aab --build-mode profile
  ///
  /// # Advanced build with custom arguments
  /// --binary-type ipa --arguments "--verbose --analyze-size" --flavor production
  ///
  /// # Custom output location
  /// --output ./custom-builds/ --build-name "v2.1.0" --build-number 42
  /// ```
  static ArgParser parser = ArgParser()
    ..addOption('target',
        abbr: 't',
        help:
            'The main entry-point file of the application, as run on the device.')
    ..addOption('binary-type',
        abbr: 'b',
        help: 'Binary type (apk, aab, ipa, ios, macos, etc)',
        defaultsTo: 'apk')
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
        defaultsTo: Files.customOutputDir.path)
    ..addFlag('pub',
        abbr: 'p', help: 'Run pub get before building', defaultsTo: true)
    ..addOption('dart-defines-file', help: 'Dart defines file');

  /// Factory constructor creating Arguments from command-line results.
  ///
  /// Parses command-line argument results and global configuration to create
  /// a fully configured `Arguments` instance for custom build execution.
  /// This factory handles type conversion, default value application, and
  /// argument validation for all supported build parameters.
  ///
  /// ## Parameters
  ///
  /// - `results` - Parsed command-line arguments specific to custom build
  /// - `globalResults` - Global CLI configuration and environment settings
  ///
  /// ## Returns
  ///
  /// Returns a configured `Arguments` instance with:
  /// - All command-line arguments properly parsed and typed
  /// - Default values applied where arguments not specified
  /// - Global configuration integrated with local arguments
  /// - Custom arguments split and processed into list format
  /// - Output path resolved with fallback to default directory
  ///
  /// ## Argument Processing
  ///
  /// The factory performs several processing steps:
  /// - String arguments extracted with proper type casting
  /// - Custom arguments string split on spaces into argument list
  /// - Build number converted to string representation
  /// - Output path resolved with default fallback
  /// - Boolean flags processed with default value support
  /// - Rest arguments used for build source directory specification
  ///
  /// ## Example
  ///
  /// ```dart
  /// // CLI: flutter distribute build custom --binary-type aab --arguments "--verbose"
  /// final args = Arguments.fromArgResults(argResults, globalResults);
  ///
  /// // Result configuration:
  /// // - binaryType: 'aab'
  /// // - customArgs: ['--verbose']
  /// // - buildMode: 'release' (default)
  /// // - pub: true (default)
  /// ```
  factory Arguments.fromArgResults(
      ArgResults results, ArgResults? globalResults) {
    return Arguments(
      Variables.fromSystem(globalResults),
      binaryType: results['binary-type'] as String,
      buildMode: results['build-mode'] as String?,
      target: results['target'] as String?,
      flavor: results['flavor'] as String?,
      dartDefines: results['dart-defines'] as String?,
      dartDefinesFile: results['dart-defines-file'] as String?,
      buildName: results['build-name'] as String?,
      buildNumber: results['build-number']?.toString(),
      pub: results['pub'] as bool? ?? true,
      customArgs: results['arguments']?.split(' ') as List<String>?,
      output: results['output'] as String? ?? Files.customOutputDir.path,
      buildSourceDir: results.rest.firstOrNull ?? Files.customOutputDir.path,
    );
  }

  /// Factory constructor creating Arguments from JSON configuration.
  ///
  /// Deserializes a JSON object into a fully configured `Arguments` instance
  /// for custom build execution. This factory enables configuration loading
  /// from files, API responses, or serialized build configurations with
  /// comprehensive parameter mapping and type safety.
  ///
  /// ## Parameters
  ///
  /// - `json` - Map containing build configuration parameters
  /// - `variables` - Required system and environment variables for build context
  ///
  /// ## Returns
  ///
  /// Returns a configured `Arguments` instance with:
  /// - All JSON parameters properly deserialized and typed
  /// - Required binary type and variables configuration
  /// - Optional parameters with null safety and default fallbacks
  /// - Custom arguments list properly cast from dynamic JSON array
  /// - Output and source directory paths with default value support
  ///
  /// ## JSON Structure
  ///
  /// Expected JSON format includes:
  /// ```json
  /// {
  ///   "binary-type": "aab",
  ///   "build-mode": "release",
  ///   "target": "./lib/main.dart",
  ///   "flavor": "production",
  ///   "dart-defines": "FLAVOR=prod",
  ///   "dart-defines-file": "./defines.json",
  ///   "build-name": "2.1.0",
  ///   "build-number": "42",
  ///   "pub": true,
  ///   "arguments": ["--verbose", "--analyze-size"],
  ///   "output": "./custom-builds/",
  ///   "build-source-dir": "./lib"
  /// }
  /// ```
  ///
  /// ## Type Handling
  ///
  /// The factory performs careful type conversion:
  /// - String parameters cast directly from JSON values
  /// - Boolean parameters with null-safe defaults
  /// - List parameters safely cast from dynamic JSON arrays
  /// - Numeric parameters converted to string representation
  /// - Path parameters with default directory fallbacks
  ///
  /// ## Example
  ///
  /// ```dart
  /// final config = {
  ///   'binary-type': 'ipa',
  ///   'build-mode': 'release',
  ///   'arguments': ['--verbose', '--tree-shake-icons'],
  ///   'pub': true
  /// };
  ///
  /// final args = Arguments.fromJson(config, variables: systemVars);
  /// final result = await args.build();
  /// ```
  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    return Arguments(
      variables,
      binaryType: json['binary-type'] as String,
      buildMode: json['build-mode'] as String?,
      target: json['target'] as String?,
      flavor: json['flavor'] as String?,
      dartDefines: json['dart-defines'] as String?,
      dartDefinesFile: json['dart-defines-file'] as String?,
      buildName: json['build-name']?.toString(),
      buildNumber: json['build-number'] as String?,
      pub: json['pub'] as bool? ?? true,
      customArgs: (json['arguments'] as List<dynamic>?)?.cast<String>(),
      output: json['output'] as String? ?? Files.customOutputDir.path,
      buildSourceDir:
          json['build-source-dir'] as String? ?? Files.customOutputDir.path,
    );
  }

  /// Serializes the Arguments instance to a JSON-compatible map.
  ///
  /// Converts all build configuration parameters into a JSON-serializable
  /// map structure that can be stored, transmitted, or used for configuration
  /// persistence. This method provides the inverse operation of `fromJson`
  /// for complete serialization support.
  ///
  /// ## Returns
  ///
  /// Returns a `Map<String, dynamic>` containing:
  /// - All build configuration parameters as key-value pairs
  /// - JSON-compatible data types (String, bool, List, etc.)
  /// - Null values preserved for optional parameters
  /// - Consistent key naming matching command-line arguments
  ///
  /// ## Output Structure
  ///
  /// The returned map structure includes:
  /// - `binary-type` - Output binary format specification
  /// - `build-mode` - Build optimization mode setting
  /// - `target` - Main application entry-point file
  /// - `flavor` - Product flavor or build variant
  /// - `dart-defines` - Dart compilation define values
  /// - `dart-defines-file` - Dart defines configuration file
  /// - `build-name` - Human-readable version name
  /// - `build-number` - Numeric version identifier
  /// - `pub` - Dependency resolution flag
  /// - `arguments` - Custom build command arguments
  /// - `output` - Build artifacts output directory
  ///
  /// ## Example
  ///
  /// ```dart
  /// final args = Arguments(variables, binaryType: 'aab', buildMode: 'release');
  /// final json = args.toJson();
  ///
  /// // Result:
  /// // {
  /// //   'binary-type': 'aab',
  /// //   'build-mode': 'release',
  /// //   'target': null,
  /// //   'flavor': null,
  /// //   'pub': null,
  /// //   'arguments': null,
  /// //   'output': null
  /// // }
  /// ```
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
        'pub': pub,
        'arguments': customArgs,
        'output': output,
      };
}
