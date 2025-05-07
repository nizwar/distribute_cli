import '../parsers/job_arguments.dart';

/// Abstract class representing build arguments.
///
/// The `BuildArguments` class defines the structure for arguments
/// used in the build process, such as binary type, build mode, and
/// additional custom arguments.
abstract class BuildArguments extends JobArguments {
  /// The type of binary to build (e.g., apk, aab).
  final String binaryType;

  /// The target file to build (optional).
  final String? target;

  /// The build mode (e.g., release, debug).
  final String? buildMode;

  /// The flavor of the build (optional).
  final String? flavor;

  /// Dart defines as a string (optional).
  final String? dartDefines;

  /// Path to a file containing Dart defines (optional).
  final String? dartDefinesFile;

  /// The build name (optional).
  final String? buildName;

  /// The build number (optional).
  final String? buildNumber;

  /// Whether to run `pub get` before building.
  final bool pub;

  /// Additional custom arguments for the build process (optional).
  final List<String>? customArgs;

  /// Creates a new `BuildArguments` instance.
  ///
  /// - [binaryType]: The type of binary to build.
  /// - [buildMode]: The build mode (default is 'release').
  /// - [target]: The target file to build (optional).
  /// - [flavor]: The flavor of the build (optional).
  /// - [dartDefines]: Dart defines as a string (optional).
  /// - [dartDefinesFile]: Path to a file containing Dart defines (optional).
  /// - [customArgs]: Additional custom arguments for the build process (optional).
  /// - [buildName]: The build name (optional).
  /// - [buildNumber]: The build number (optional).
  /// - [pub]: Whether to run `pub get` before building (default is true).
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

  /// Returns the list of arguments for the build process.
  @override
  List<String> get results => [
        if (binaryType.isNotEmpty) binaryType,
        if (target?.isNotEmpty ?? false) '--target=$target',
        if (buildMode?.isNotEmpty ?? false) '--$buildMode',
        if (flavor?.isNotEmpty ?? false) '--flavor=$flavor',
        if (dartDefines?.isNotEmpty ?? false) '--dart-defines=$dartDefines',
        if (dartDefinesFile?.isNotEmpty ?? false)
          '--dart-defines-file=$dartDefinesFile',
        if (buildName?.isNotEmpty ?? false) '--build-name=$buildName',
        if (buildNumber?.isNotEmpty ?? false) '--build-number=$buildNumber',
        if (pub) '--pub' else '--no-pub',
        if (customArgs != null) ...customArgs!,
      ];

  /// The job mode for the build process.
  @override
  JobMode get jobMode => JobMode.build;
}
