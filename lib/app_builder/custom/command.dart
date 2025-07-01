import 'package:args/args.dart';
import 'arguments.dart';

import '../../command.dart';

/// Comprehensive custom build command implementation.
///
/// Extends the base `Commander` class to provide a highly flexible and configurable
/// build workflow supporting arbitrary binary types, user-defined arguments, and
/// integration with external build systems. This enables advanced customization
/// for multi-platform targets and specialized deployment scenarios.
///
/// Key features:
/// - Universal binary output support (APK, AAB, IPA, desktop, web, custom formats)
/// - Flexible argument passing for custom build tools and workflows
/// - Multi-platform compatibility (Android, iOS, desktop, web)
/// - Integration with CI/CD pipelines and external toolchains
/// - Advanced configuration management and artifact output control
/// - Extensible foundation for future enhancements and specialized requirements
///
/// Example usage:
/// ```dart
/// final command = Command();
/// final result = await command.run();
/// if (result == 0) {
///   print('Custom build completed successfully');
/// } else {
///   print('Build failed with exit code: $result');
/// }
/// ```
class Command extends Commander {
  /// Provides a comprehensive description of the custom build command.
  ///
  /// Returns a detailed explanation of the command's purpose, flexibility,
  /// and capabilities for creating customized build workflows that extend
  /// beyond standard platform builds with user-defined configurations.
  @override
  String get description =>
      "Build a custom application by selecting specific configurations and options tailored to your requirements. "
      "Supports flexible binary type specification, user-defined arguments, multi-platform targets, and integration "
      "with existing build systems for specialized workflows and deployment scenarios.";

  /// Returns the command identifier used in CLI invocation.
  ///
  /// This name is used when invoking the custom build command from the
  /// command line interface, allowing users to access flexible build
  /// capabilities within the distribute CLI tool.
  @override
  String get name => "custom";

  /// Provides the argument parser for custom build configuration.
  ///
  /// Returns the `Arguments.parser` which defines all available command-line
  /// options, flags, and parameters for custom builds including binary type
  /// specification, build modes, custom arguments, and output management.
  @override
  ArgParser get argParser => Arguments.parser;

  /// Executes the custom application build process.
  ///
  /// This method orchestrates flexible build workflows by processing user-defined
  /// configurations and delegating to the Arguments build system for execution:
  ///
  /// ## Build Workflow
  ///
  /// 1. **Argument Processing**: Parses custom build arguments and global settings
  /// 2. **Configuration Validation**: Validates binary type and parameter compatibility
  /// 3. **Build Execution**: Delegates to Arguments.build() with custom configuration
  /// 4. **Result Management**: Returns build exit code for success/failure indication
  ///
  /// ## Parameters
  ///
  /// - Uses `argResults` - Custom build argument results from CLI parsing
  /// - Uses `globalResults` - Global configuration and environment variables
  ///
  /// ## Returns
  ///
  /// Returns a `Future` that completes with:
  /// - `0` - Build completed successfully with specified configuration
  /// - `>0` - Build failed with specific error code
  /// - `null` - Build process encountered unexpected termination
  ///
  /// ## Build Flexibility
  ///
  /// The execution supports diverse scenarios:
  /// - **Binary Types**: APK, AAB, IPA, desktop apps, web builds, custom formats
  /// - **Build Modes**: Debug, profile, release, and custom optimization levels
  /// - **Custom Arguments**: User-defined flags and parameters for specialized tools
  /// - **Output Control**: Configurable artifact paths and naming conventions
  /// - **Integration**: Compatibility with existing build systems and toolchains
  ///
  /// ## Error Handling
  ///
  /// Common failure scenarios include:
  /// - Invalid binary type specification or unsupported format
  /// - Incorrect custom arguments or incompatible parameter combinations
  /// - Missing build dependencies or environment configuration issues
  /// - Output path conflicts or insufficient disk space
  /// - Integration failures with external build tools or systems
  ///
  /// ## Example Scenarios
  ///
  /// **Enterprise iOS Build:**
  /// ```dart
  /// // CLI: flutter distribute build custom --binary-type ipa --flavor enterprise
  /// final result = await command.run();
  /// ```
  ///
  /// **Multi-Platform Desktop Build:**
  /// ```dart
  /// // CLI: flutter distribute build custom --binary-type macos --arguments "--analyze-size"
  /// final result = await command.run();
  /// ```
  ///
  /// **Custom Web Build:**
  /// ```dart
  /// // CLI: flutter distribute build custom --binary-type web --build-mode profile
  /// final result = await command.run();
  /// ```
  ///
  /// ## Integration Benefits
  ///
  /// The custom command enables:
  /// - Seamless integration with existing CI/CD pipelines
  /// - Support for specialized deployment requirements
  /// - Compatibility with custom build tools and optimization workflows
  /// - Flexible artifact management and post-build processing
  /// - Extensible foundation for future build system enhancements
  @override
  Future? run() => Arguments.fromArgResults(argResults!, globalResults).build();
}
