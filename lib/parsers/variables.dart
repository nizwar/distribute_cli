import 'dart:io';

import 'package:args/args.dart';

class Variables {
  Map<String, dynamic> variables;

  final ArgResults? globalResults;

  Variables(this.variables, this.globalResults);

  factory Variables.fromSystem(ArgResults? globalResults) =>
      Variables(Map<String, dynamic>.from(Platform.environment), globalResults);

  /// Substitutes variables in a string with their corresponding values from a map.
  ///
  /// This function replaces placeholders in the format `${{VAR_NAME}}` or `${VAR_NAME}`
  /// with the values of the corresponding variables from the provided map.
  ///
  /// - [input]: The input string containing placeholders.
  /// - [variables]: A map of variable names and their values (default is an empty map).
  ///
  /// Returns the string with placeholders replaced by their corresponding values.
  Future<String> process(String? input) async {
    if (input == null) return "";

    input = await substituteCLIArguments(input);

    final pattern = RegExp(r'\$\{\{(\w+)\}\}|\$\{(\w+)\}');
    input = input.replaceAllMapped(pattern, (match) {
      final varName = match.group(1) ?? match.group(2); // capture either style
      final value = variables[varName?.trim()];

      if (value != null) {
        return value.toString();
      } else {
        return match.group(0)!;
      }
    });
    return input;
  }

  Future<String> substituteCLIArguments(String? input) async {
    if (input == null) return "";
    // Pattern matches %{{COMMAND}} OR %{COMMAND}
    final pattern = RegExp(r'\%\{\{([^\}]+)\}\}|\%\{([^\}]+)\}');

    // Use replaceAllMapped to handle each match individually and asynchronously
    final matches = pattern.allMatches(input).toList();
    if (matches.isEmpty) return input;

    // Since replaceAllMapped cannot be async, we process matches manually
    String result = input;
    for (final match in matches.reversed) {
      final value = match.group(1) ?? match.group(2) ?? "";
      String processResults;
      try {
        if (value.trim().isEmpty) {
          processResults = "";
        } else if (value.contains(" ")) {
          final args = value.split(" ");
          final process = await Process.run(args.first, args.sublist(1));
          processResults = process.exitCode == 0
              ? process.stdout.toString().trim()
              : process.stderr.toString().trim();
        } else {
          final process = await Process.run(value, []);
          processResults = process.exitCode == 0
              ? process.stdout.toString().trim()
              : process.stderr.toString().trim();
        }
      } catch (e) {
        processResults = "";
      }
      // Replace only the current match
      result = result.replaceRange(match.start, match.end, processResults);
    }
    return result;
  }

  void addVariables(Map<String, dynamic> newVariables) {
    variables.addAll(newVariables);
  }

  void replaceVariables(Map<String, dynamic> newVariables) {
    variables = newVariables;
  }

  Future<Map<String, dynamic>> processMap(Map<String, dynamic> json) async {
    Map<String, dynamic> processedMap = {};
    for (var key in json.keys) {
      processedMap[key] = await process(json[key].toString());
    }
    return processedMap;
  }

  static Future<String> processBySystem(
      String? input, ArgResults? globalResults) async {
    return Variables.fromSystem(globalResults).process(input);
  }
}
