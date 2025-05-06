import '../parsers/job_arguments.dart';

abstract class BuildArguments extends JobArguments {
  final String binaryType;
  final String? target;
  final String? buildMode;
  final String? flavor;
  final String? dartDefines;
  final String? dartDefinesFile;
  final String? buildName;
  final String? buildNumber;
  final bool pub;
  final List<String>? customArgs;

  BuildArguments({
    this.buildMode = 'release',
    this.target,
    required this.binaryType,
    this.flavor,
    this.dartDefines,
    this.dartDefinesFile,
    this.customArgs,
    this.buildName,
    this.buildNumber,
    this.pub = true,
  });

  @override
  List<String> get results => [
        if (binaryType.isNotEmpty) binaryType,
        if (target?.isNotEmpty ?? false) '--target=$target',
        if (buildMode?.isNotEmpty ?? false) '--$buildMode',
        if (flavor?.isNotEmpty ?? false) '--flavor=$flavor',
        if (dartDefines?.isNotEmpty ?? false) '--dart-defines=$dartDefines',
        if (dartDefinesFile?.isNotEmpty ?? false) '--dart-defines-file=$dartDefinesFile',
        if (buildName?.isNotEmpty ?? false) '--build-name=$buildName',
        if (buildNumber?.isNotEmpty ?? false) '--build-number=$buildNumber',
        if (pub) '--pub' else '--no-pub',
        if (customArgs != null) ...customArgs!,
      ];

  @override
  JobMode get jobMode => JobMode.build;
}
