
import '../command.dart';
// import 'github/command.dart' as github;
import 'xcrun/ios/command.dart' as xcrun;

/// A command to publish an iOS application using the XCrun tool.
///
/// The `IosPublisherCommand` class provides functionality to publish iOS apps
/// by interacting with Xcode and managing app distribution tasks.
class IosPublisherCommand extends Commander {
  IosPublisherCommand() {
    addSubcommand(xcrun.Command());
    // addSubcommand(github.Command("ios"));
  }

  /// A description of the command.
  @override
  String get description => "Publish an iOS application using the XCrun tool.";

  /// The name of the command.
  @override
  String get name => "ios";

  @override
  Future? run() async {}
}
