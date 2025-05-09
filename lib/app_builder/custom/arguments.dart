import 'package:args/args.dart';

import '../../files.dart';
import '../build_arguments.dart';

class Arguments extends BuildArguments {
  Arguments({
    super.buildMode,
    required super.binaryType,
    required super.buildSourceDir,
    super.target,
    super.flavor,
    super.dartDefines,
    super.dartDefinesFile,
    super.buildName,
    super.buildNumber,
    super.pub,
    super.output,
    super.customArgs,
  });

  BuildArguments copyWith(Arguments? data) {
    return Arguments(
      buildMode: data?.buildMode ?? buildMode,
      binaryType: data?.binaryType ?? binaryType,
      customArgs: data?.customArgs ?? customArgs,
      target: data?.target ?? target,
      flavor: data?.flavor ?? flavor,
      dartDefines: data?.dartDefines ?? dartDefines,
      dartDefinesFile: data?.dartDefinesFile ?? dartDefinesFile,
      buildName: data?.buildName ?? buildName,
      buildNumber: data?.buildNumber ?? buildNumber,
      pub: data?.pub ?? pub,
      output: data?.output ?? output,
      buildSourceDir: data?.buildSourceDir ?? buildSourceDir,
    );
  }

  static ArgParser parser = ArgParser()
    ..addOption('target', abbr: 't', help: 'The main entry-point file of the application, as run on the device.')
    ..addOption('binary-type', abbr: 'b', help: 'Binary type (apk, aab, ipa, ios, macos, etc)', defaultsTo: 'apk')
    ..addOption('build-mode', abbr: 'm', help: 'Build mode (debug, profile, release)', defaultsTo: 'release')
    ..addOption('flavor', abbr: 'f', help: 'Build flavor')
    ..addOption('arguments', abbr: 'a', help: 'Custom arguments to pass to the build command')
    ..addOption('dart-defines', abbr: 'd', help: 'Dart defines')
    ..addOption('build-name', abbr: 'n', help: 'Build name')
    ..addOption('build-number', abbr: 'N', help: 'Build number')
    ..addOption('output', abbr: 'o', help: 'Output path for the build', defaultsTo: Files.customOutputDir.path)
    ..addFlag('pub', abbr: 'p', help: 'Run pub get before building', defaultsTo: true)
    ..addOption('dart-defines-file', help: 'Dart defines file');

  factory Arguments.fromArgResults(ArgResults results) {
    return Arguments(
      binaryType: results['binary-type'] as String,
      buildMode: results['build-mode'] as String?,
      target: results['target'] as String?,
      flavor: results['flavor'] as String?,
      dartDefines: results['dart-defines'] as String?,
      dartDefinesFile: results['dart-defines-file'] as String?,
      buildName: results['build-name'] as String?,
      buildNumber: results['build-number']?.toString(),
      pub: results['pub'] as bool? ?? true,
      customArgs: results['arguments']?.split(' ') as List<String>?,
      output: results['output'] as String? ?? Files.customOutputDir.path,
      buildSourceDir: results.rest.firstOrNull ?? Files.customOutputDir.path,
    );
  }

  factory Arguments.fromJson(Map<String, dynamic> json) {
    return Arguments(
      binaryType: json['binary-type'] as String,
      buildMode: json['build-mode'] as String?,
      target: json['target'] as String?,
      flavor: json['flavor'] as String?,
      dartDefines: json['dart-defines'] as String?,
      dartDefinesFile: json['dart-defines-file'] as String?,
      buildName: json['build-name']?.toString(),
      buildNumber: json['build-number'] as String?,
      pub: json['pub'] as bool? ?? true,
      customArgs: (json['arguments'] as List<dynamic>?)?.cast<String>(),
      output: json['output'] as String? ?? Files.customOutputDir.path,
      buildSourceDir: json['build-source-dir'] as String? ?? Files.customOutputDir.path,
    );
  }

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
        'pub': pub,
        'arguments': customArgs,
        'output': output,
      };
}
