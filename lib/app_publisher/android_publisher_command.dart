import 'package:distribute_cli/app_publisher/fastlane/fastlane_android_command.dart';
import 'package:distribute_cli/app_publisher/firebase/firebase_android_command.dart';

import '../command.dart';

class AndroidPublisherCommand extends Commander {
  AndroidPublisherCommand() {
    addSubcommand(FastlaneAndroidCommand());
    addSubcommand(FirebaseAndroidCommand());
  }
  @override
  String get description => "Publish android app using choosen one.";

  @override
  String get name => "android";

  @override
  Future? run() async {}
}
