import 'package:args/args.dart';
import '../../command.dart';
import 'arguments.dart' as xcrun;

/// Xcrun App Store publishing command implementation.
///
/// Extends `Commander` to provide Xcrun-specific command-line interface
/// for distributing iOS applications through App Store Connect. Handles
/// argument parsing, validation, and execution of Xcrun altool operations.
///
/// Key capabilities:
/// - Command-line argument processing
/// - Xcrun altool integration
/// - Publishing workflow execution
/// - Authentication management
/// - Validation and upload coordination
/// - Error handling and reporting
///
/// Command structure:
/// ```
/// distribute_cli publish xcrun [options]
/// ```
///
/// Example usage:
/// ```bash
/// # Basic App Store upload with JWT authentication
/// distribute_cli publish xcrun \
///   --file-path MyApp.ipa \
///   --api-key ABC123DEF4 \
///   --api-issuer 12345678-1234-1234-1234-123456789012
///
/// # Upload with validation and bundle information
/// distribute_cli publish xcrun \
///   --file-path MyApp.ipa \
///   --username developer@example.com \
///   --password @keychain:AC_PASSWORD \
///   --bundle-id com.example.myapp \
///   --validate-app \
///   --type ios
/// ```
class Command extends Commander {
  /// Creates a new Xcrun App Store command instance.
  ///
  /// Initializes the command with default configuration for Xcrun
  /// App Store publishing. Sets up argument parsing and command
  /// execution capabilities for iOS distribution workflows.
  ///
  /// The command integrates with Apple's Xcrun altool to perform
  /// actual upload operations and provides comprehensive error
  /// handling for common App Store Connect scenarios.
  Command();

  /// Human-readable description of the Xcrun command.
  ///
  /// Provides clear explanation of the command's purpose for help
  /// documentation and user guidance. Describes the Xcrun altool
  /// functionality and target use cases for iOS distribution.
  ///
  /// Displayed in:
  /// - Command help output (`--help`)
  /// - CLI documentation
  /// - Error messages and usage instructions
  @override
  String get description =>
      "Publish an iOS application using the XCrun tool, which provides a command-line interface for interacting with Xcode and managing app distribution tasks.";

  /// Command identifier for CLI invocation.
  ///
  /// The unique name used to invoke this command from the command line.
  /// Used in command routing and help system organization.
  ///
  /// Usage: `distribute_cli publish xcrun [options]`
  @override
  String get name => "xcrun";

  /// Command-line argument parser configuration.
  ///
  /// Provides the argument parser instance that defines all supported
  /// command-line options for Xcrun publishing. Delegates to the
  /// Arguments class parser for consistent option handling.
  ///
  /// Includes options for:
  /// - File paths and IPA targets
  /// - Authentication methods
  /// - App Store Connect configuration
  /// - Validation and upload controls
  /// - Bundle and version management
  @override
  ArgParser get argParser => xcrun.Arguments.parser;

  /// Executes the Xcrun App Store publishing workflow.
  ///
  /// Parses command-line arguments, creates Arguments instance, and
  /// initiates the Xcrun publishing process. Handles the complete
  /// App Store workflow including validation, file processing,
  /// and altool integration.
  ///
  /// Process flow:
  /// 1. Parse and validate command-line arguments
  /// 2. Create Arguments instance with configuration
  /// 3. Execute Xcrun altool upload command
  /// 4. Handle results and error conditions
  ///
  /// Returns Future that completes with the exit code:
  /// - 0 = Success (app uploaded successfully)
  /// - Non-zero = Error (upload or validation failed)
  ///
  /// Throws exception if required arguments are missing or invalid.
  @override
  Future? run() =>
      xcrun.Arguments.fromArgParser(argResults!, globalResults).publish();
}
