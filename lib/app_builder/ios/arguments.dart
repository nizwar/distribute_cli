import 'package:args/args.dart';

import '../../files.dart';
import '../../parsers/job_arguments.dart';
import '../build_arguments.dart';

class Arguments extends BuildArguments {
  final String? exportOptionsPlist;
  final String? exportMethod;
  Arguments({
    super.buildMode,
    required super.binaryType,
    super.output,
    super.target,
    super.flavor,
    super.dartDefines,
    super.dartDefinesFile,
    super.customArgs,
    super.buildName,
    super.buildNumber,
    super.pub,
    this.exportOptionsPlist,
    this.exportMethod,
  }) : super(buildSourceDir: Files.iosDistributionOutputDir.path);

  Arguments copyWith(Arguments? data) {
    return Arguments(
      buildMode: data?.buildMode ?? buildMode,
      binaryType: data?.binaryType ?? binaryType,
      flavor: data?.flavor ?? flavor,
      dartDefines: data?.dartDefines ?? dartDefines,
      dartDefinesFile: data?.dartDefinesFile ?? dartDefinesFile,
      customArgs: data?.customArgs ?? customArgs,
      target: data?.target ?? target,
      buildName: data?.buildName ?? buildName,
      buildNumber: data?.buildNumber ?? buildNumber,
      pub: data?.pub ?? pub,
      exportOptionsPlist: data?.exportOptionsPlist ?? exportOptionsPlist,
      exportMethod: data?.exportMethod ?? exportMethod,
      output: data?.output ?? output,
    );
  }

  static ArgParser parser = ArgParser()
    ..addOption('target', abbr: 't', help: 'The main entry-point file of the application, as run on the device.')
    ..addOption('binary-type', abbr: 'b', help: 'Binary type (ipa, ios)', defaultsTo: 'ipa')
    ..addOption('build-mode', abbr: 'm', help: 'Build mode (debug, profile, release)', defaultsTo: 'release')
    ..addOption('flavor', abbr: 'f', help: 'Build flavor')
    ..addOption('arguments', abbr: 'a', help: 'Custom arguments to pass to the build command')
    ..addOption('dart-defines', abbr: 'd', help: 'Dart defines')
    ..addOption('build-name', abbr: 'n', help: 'Build name')
    ..addOption('build-number', abbr: 'N', help: 'Build number')
    ..addOption('export-options-plist', help: 'Path to export options plist file')
    ..addOption('export-method', help: 'Export method (ad-hoc, app-store, enterprise, development)')
    ..addFlag('pub', abbr: 'p', help: 'Run pub get before building', defaultsTo: true)
    ..addOption("output", abbr: 'o', help: 'Output path for the build', defaultsTo: Files.iosDistributionOutputDir.path)
    ..addOption('dart-defines-file', help: 'Dart defines file');

  factory Arguments.fromArgResults(ArgResults results) {
    return Arguments(
      buildMode: results['build-mode'] as String?,
      binaryType: results.rest.firstOrNull ?? 'ipa',
      target: results['target'] as String?,
      flavor: results['flavor'] as String?,
      dartDefines: results['dart-defines'] as String?,
      dartDefinesFile: results['dart-defines-file'] as String?,
      buildName: results['build-name'] as String?,
      buildNumber: results['build-number']?.toString(),
      pub: results['pub'] as bool? ?? true,
      exportOptionsPlist: results['export-options-plist'] as String?,
      exportMethod: results['export-method'] as String?,
      customArgs: results['arguments']?.split(' ') as List<String>?,
      output: results['output'] as String? ?? Files.iosDistributionOutputDir.path,
    );
  }

  factory Arguments.fromJson(Map<String, dynamic> json) {
    return Arguments(
      output: json['output'] as String? ?? Files.iosDistributionOutputDir.path,
      binaryType: json['binary-type'] ?? "ipa",
      buildMode: json['build-mode'] as String?,
      target: json['target'] as String?,
      flavor: json['flavor'] as String?,
      dartDefines: json['dart-defines'] as String?,
      dartDefinesFile: json['dart-defines-file'] as String?,
      buildName: json['build-name'] as String?,
      buildNumber: json['build-number']?.toString(),
      pub: json['pub'] as bool? ?? true,
      exportOptionsPlist: json['export-options-plist'] as String?,
      exportMethod: json['export-method'] as String?,
      customArgs: (json['arguments'] as List<dynamic>?)?.cast<String>(),
    );
  }

  static JobArguments defaultConfigs() => Arguments(
        binaryType: 'ipa',
        buildMode: 'release',
        target: null,
        flavor: null,
        dartDefines: null,
        dartDefinesFile: null,
        buildName: null,
        buildNumber: null,
        pub: true,
        exportOptionsPlist: null,
        exportMethod: null,
        output: Files.iosDistributionOutputDir.path,
        customArgs: [],
      );

  @override
  Map<String, dynamic> toJson() => {
        'binary-type': binaryType,
        'build-mode': buildMode,
        'target': target,
        'flavor': flavor,
        'dart-defines': dartDefines,
        'dart-defines-file': dartDefinesFile,
        'build-name': buildName,
        'build-number': buildNumber,
        'export-options-plist': exportOptionsPlist,
        'export-method': exportMethod,
        'arguments': customArgs,
        'pub': pub,
        'output': output,
      };

  @override
  List<String> get results => super.results
    ..addAll([
      if (exportOptionsPlist != null) '--export-options-plist=$exportOptionsPlist',
      if (exportMethod != null) '--export-method=$exportMethod',
    ]);
}
