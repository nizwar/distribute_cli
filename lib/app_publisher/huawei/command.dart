import 'package:args/args.dart';

import '../../command.dart';
import 'arguments.dart' as huawei;

class Command extends Commander {
  @override
  String get name => 'huawei';

  @override
  String get description =>
      'Upload an APK/AAB and optionally submit it to Huawei AppGallery.';

  @override
  ArgParser get argParser => huawei.Arguments.parser;

  @override
  Future<int> run() =>
      huawei.Arguments.fromArgResults(argResults!, globalResults).publish();
}
