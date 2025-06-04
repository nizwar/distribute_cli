import 'package:args/args.dart';
import '../../command.dart';
import 'arguments.dart' as github;

/// Command to publish an application to GitHub Releases.
///
/// This command uploads a release asset to a specified GitHub repository.
class Command extends Commander {
  /// Creates a new [Command] for publishing to GitHub.
  Command();

  /// Description of the command.
  @override
  String get description => "Publish app to GitHub.";

  /// Name of the command.
  @override
  String get name => "github";

  /// Argument parser for the command.
  @override
  ArgParser argParser = github.Arguments.parser;

  /// Executes the command.
  ///
  /// Parses the arguments and publishes the application using the [Arguments] class.
  /// Returns a [Future] that completes with the exit code of the publish process.
  @override
  Future? run() =>
      github.Arguments.fromArgResults(argResults!, globalResults).publish();
}
