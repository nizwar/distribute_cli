import 'package:args/args.dart';
import '../../command.dart';
import 'arguments.dart' as github;

/// GitHub Releases publishing command implementation.
///
/// Extends `Commander` to provide GitHub-specific command-line interface
/// for distributing applications through repository releases. Handles
/// argument parsing, validation, and execution of GitHub API operations.
///
/// Key capabilities:
/// - Command-line argument processing
/// - GitHub API integration
/// - Release management workflow
/// - Asset upload coordination
/// - Error handling and validation
/// - Integration with publishing pipeline
///
/// Command structure:
/// ```
/// distribute_cli publish github [options]
/// ```
///
/// Example usage:
/// ```bash
/// # Basic release upload
/// distribute_cli publish github \
///   --file-path app.apk \
///   --repo-owner myorg \
///   --repo-name myapp \
///   --token ghp_xxxxxxxxxxxxxxxxxxxx \
///   --release-name v1.0.0
///
/// # Release with detailed information
/// distribute_cli publish github \
///   --file-path build/outputs/ \
///   --repo-owner flutter-team \
///   --repo-name awesome-app \
///   --token ghp_xxxxxxxxxxxxxxxxxxxx \
///   --release-name v2.1.0-beta \
///   --release-body "Beta release with new features and bug fixes"
/// ```
class Command extends Commander {
  /// Creates a new GitHub Releases command instance.
  ///
  /// Initializes the command with default configuration for GitHub
  /// Releases publishing. Sets up argument parsing and command
  /// execution capabilities for repository release operations.
  ///
  /// The command integrates with the GitHub API to perform release
  /// management, asset uploads, and provides comprehensive error
  /// handling for common GitHub operations.
  Command();

  /// Human-readable description of the GitHub command.
  ///
  /// Provides clear explanation of the command's purpose for help
  /// documentation and user guidance. Describes the GitHub Releases
  /// functionality and target use cases.
  ///
  /// Displayed in:
  /// - Command help output (`--help`)
  /// - CLI documentation
  /// - Error messages and usage instructions
  @override
  String get description => "Publish app to GitHub.";

  /// Command identifier for CLI invocation.
  ///
  /// The unique name used to invoke this command from the command line.
  /// Used in command routing and help system organization.
  ///
  /// Usage: `distribute_cli publish github [options]`
  @override
  String get name => "github";

  /// Command-line argument parser configuration.
  ///
  /// Provides the argument parser instance that defines all supported
  /// command-line options for GitHub Releases publishing. Delegates to
  /// the Arguments class parser for consistent option handling.
  ///
  /// Includes options for:
  /// - File paths and upload targets
  /// - Repository identification
  /// - Authentication and security
  /// - Release management
  /// - Content and metadata
  @override
  ArgParser argParser = github.Arguments.parser;

  /// Executes the GitHub Releases publishing workflow.
  ///
  /// Parses command-line arguments, creates Arguments instance, and
  /// initiates the GitHub publishing process. Handles the complete
  /// release workflow including validation, file processing,
  /// and GitHub API integration.
  ///
  /// Process flow:
  /// 1. Parse and validate command-line arguments
  /// 2. Create Arguments instance with configuration
  /// 3. Execute GitHub API release operations
  /// 4. Handle results and error conditions
  ///
  /// Returns Future that completes with the exit code:
  /// - 0 = Success (release created/updated with assets)
  /// - Non-zero = Error (release or upload failed)
  ///
  /// Throws exception if required arguments are missing or invalid.
  @override
  Future? run() =>
      github.Arguments.fromArgResults(argResults!, globalResults).publish();
}
