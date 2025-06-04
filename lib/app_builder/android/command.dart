import 'package:args/args.dart';

import '../../command.dart';
import 'arguments.dart';

/// Comprehensive Android build command implementation.
///
/// Extends the base `Commander` class to provide Android-specific build
/// workflow, supporting APK/AAB generation, build modes, flavors, signing,
/// and output customization.
///
/// Key Android features:
/// - APK and Android App Bundle (AAB) generation
/// - Build mode flexibility: debug, profile, release
/// - Product flavor and variant support
/// - Automated signing with keystore integration
/// - Gradle dependency management
/// - Customizable output paths and file naming
///
/// Example usage:
/// ```dart
/// final command = Command();
/// final result = await command.run();
/// if (result == 0) {
///   print('Android build completed successfully');
/// }
/// ```
class Command extends Commander {
  /// Provides a comprehensive description of the Android build command.
  ///
  /// Returns a detailed explanation of the command's purpose and capabilities,
  /// including supported build types, configuration options, and expected
  /// behavior for Android application builds.
  @override
  String get description =>
      "Build an Android application using the specified configuration and options provided in the arguments. "
      "Supports APK and AAB generation with customizable build modes, flavors, signing configurations, "
      "and output specifications for creating production-ready Android applications.";

  /// Returns the command identifier used in CLI invocation.
  ///
  /// This name is used when invoking the Android build command from the
  /// command line interface, allowing users to specifically target Android
  /// builds within the distribute CLI tool.
  @override
  String get name => "android";

  /// Provides the argument parser for Android build configuration.
  ///
  /// Returns the `Arguments.parser` which defines all available command-line
  /// options, flags, and parameters specific to Android builds including
  /// build modes, output formats, signing options, and flavor configurations.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the Android application build process.
  ///
  /// This method orchestrates the complete Android build workflow by:
  ///
  /// 1. **Argument Processing**: Parses command-line arguments and global results
  /// 2. **Configuration Setup**: Creates Arguments instance with build settings
  /// 3. **Build Execution**: Delegates to Arguments.build() for actual compilation
  /// 4. **Result Handling**: Returns build exit code for success/failure indication
  ///
  /// ## Parameters
  ///
  /// - Uses `argResults` - Command-specific argument results from CLI parsing
  /// - Uses `globalResults` - Global configuration and environment variables
  ///
  /// ## Returns
  ///
  /// Returns a `Future` that completes with:
  /// - `0` - Build completed successfully
  /// - `>0` - Build failed with specific error code
  /// - `null` - Build process encountered unexpected termination
  ///
  /// ## Build Process
  ///
  /// The execution flow includes:
  /// - Environment validation (Android SDK, build tools)
  /// - Dependency resolution and Gradle setup
  /// - Source compilation and resource processing
  /// - APK/AAB generation with specified configuration
  /// - Signing process using provided credentials
  /// - Output file generation and validation
  ///
  /// ## Error Handling
  ///
  /// Common failure scenarios include:
  /// - Missing or invalid Android SDK installation
  /// - Incorrect signing configuration or missing keystore
  /// - Build dependency conflicts or resolution failures
  /// - Insufficient disk space or memory for build process
  /// - Invalid build arguments or configuration parameters
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Command execution through CLI
  /// final result = await command.run();
  ///
  /// // Handle build results
  /// switch (result) {
  ///   case 0:
  ///     logger.logInfo('Android build completed successfully');
  ///     break;
  ///   case 1:
  ///     logger.logError('Build failed due to configuration errors');
  ///     break;
  ///   default:
  ///     logger.logError('Build failed with exit code: $result');
  /// }
  /// ```
  @override
  Future? run() => Arguments.fromArgResults(argResults!, globalResults).build();
}
