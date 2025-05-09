import 'package:args/args.dart';

import '../../../files.dart';
import '../../../parsers/job_arguments.dart';
import '../../publisher_arguments.dart';

class Arguments extends PublisherArguments {
  /// The app id of your Firebase app
  final String appId;

  /// Release notes to include
  final String? releaseNotes;

  /// Path to file with release notes
  final String? releaseNotesFile;

  /// A comma-separated list of tester emails to distribute to
  final String? testers;

  /// Path to file with a comma- or newline-separated list of tester emails to distribute to
  final String? testersFile;

  /// A comma-separated list of group aliases to distribute to
  final String? groups;

  /// Path to file with a comma- or newline-separated list of group aliases to distribute to
  final String? groupsFile;

  Arguments({
    required super.filePath,
    required this.appId,
    required super.binaryType,
    this.releaseNotes,
    this.releaseNotesFile,
    this.testers,
    this.testersFile,
    this.groups,
    this.groupsFile,
  }) : super('firebase');

  factory Arguments.fromArgResults(ArgResults results) => Arguments(
        filePath: results.rest.firstOrNull ?? Files.androidDistributionOutputDir.path,
        binaryType: results['binary-type'] as String,
        appId: results['app-id'] as String,
        releaseNotes: results['release-notes'] as String?,
        releaseNotesFile: results['release-notes-file'] as String?,
        testers: results['testers'] as String?,
        testersFile: results['testers-file'] as String?,
        groups: results['groups'] as String?,
        groupsFile: results['groups-file'] as String?,
      );
  factory Arguments.fromJson(Map<String, dynamic> json) {
    return Arguments(
      filePath: json["file-path"] as String,
      appId: json['app-id'] as String,
      binaryType: json['binary-type'] as String,
      releaseNotes: json['release-notes'] as String?,
      releaseNotesFile: json['release-notes-file'] as String?,
      testers: json['testers'] as String?,
      testersFile: json['testers-file'] as String?,
      groups: json['groups'] as String?,
      groupsFile: json['groups-file'] as String?,
    );
  }

  @override
  List<String> get results => [
        'appdistribution:distribute',
        filePath,
        '--app',
        appId,
        if (releaseNotes != null) '--release-notes=$releaseNotes',
        if (releaseNotesFile != null) '--release-notes-file=$releaseNotesFile',
        if (testers != null) '--testers=$testers',
        if (testersFile != null) '--testers-file=$testersFile',
        if (groups != null) '--groups=$groups',
        if (groupsFile != null) '--groups-file=$groupsFile',
      ];

  static ArgParser parser = ArgParser()
    ..addOption('file-path', abbr: 'f', help: 'Path to the file to upload', mandatory: true)
    ..addOption('binary-type', abbr: 'b', help: 'The binary type of the application to use. Valid values are apk, aab.', defaultsTo: 'apk')
    ..addOption('app-id', abbr: 'a', help: 'The app id of your Firebase app', mandatory: true)
    ..addOption('release-notes', abbr: 'r', help: 'Release notes to include')
    ..addOption('release-notes-file', help: 'Path to file with release notes')
    ..addOption('testers', abbr: 't', help: 'A comma-separated list of tester emails to distribute to')
    ..addOption('testers-file', abbr: 'T', help: 'Path to file with a comma- or newline-separated list of tester emails to distribute to')
    ..addOption('groups', abbr: 'g', help: 'A comma-separated list of group aliases to distribute to')
    ..addOption('groups-file', abbr: 'G', help: 'Path to file with a comma- or newline-separated list of group aliases to distribute to');

  static JobArguments? defaultConfigs(String appId) => Arguments(
        filePath: Files.androidDistributionOutputDir.path,
        appId: appId,
        binaryType: 'apk',
      );

  @override
  Map<String, dynamic> toJson() => {
        'file-path': filePath,
        'app-id': appId,
        'binary-type': binaryType,
        'release-notes': releaseNotes,
        'release-notes-file': releaseNotesFile,
        'testers': testers,
        'testers-file': testersFile,
        'groups': groups,
        'groups-file': groupsFile,
      };
}
