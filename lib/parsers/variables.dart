import 'dart:io';

import 'package:args/args.dart';

/// A utility class for managing and processing variables with support for
/// environment variables, CLI arguments, and command execution.
///
/// This class handles variable substitution in strings using patterns like
/// `${{VAR_NAME}}` or `${VAR_NAME}` and command execution using patterns like
/// `%{{COMMAND}}` or `%{COMMAND}`.
class Variables {
  /// A map containing all available variables for substitution
  /// - Keys: Variable names (e.g., "HOME", "USER")
  /// - Values: Variable values (can be strings, numbers, etc.)
  Map<String, dynamic> variables;

  /// Optional command line arguments results from the global CLI parser
  /// - Used for accessing CLI flags and options
  /// - Can be null if no CLI arguments are provided
  final ArgResults? globalResults;

  /// Creates a new Variables instance with the specified variables and CLI results.
  ///
  /// Parameters:
  /// - `variables` - Map of variable names to their values
  /// - `globalResults` - Optional CLI argument results
  Variables(this.variables, this.globalResults);

  /// Creates a Variables instance using system environment variables
  ///
  /// Parameters:
  /// - `globalResults` - Optional CLI argument results to include
  ///
  /// Returns a new Variables instance with all system environment variables
  factory Variables.fromSystem(ArgResults? globalResults) =>
      Variables(Map<String, dynamic>.from(Platform.environment), globalResults);

  /// Processes and substitutes variables in a string with their corresponding values.
  ///
  /// This function replaces placeholders in the format `${{VAR_NAME}}` or `${VAR_NAME}`
  /// with the values of the corresponding variables from the variables map.
  ///
  /// Parameters:
  /// - `input` - The input string containing placeholders (can be null)
  ///
  /// Returns the string with placeholders replaced by their corresponding values.
  /// If input is null, returns an empty string.
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

  /// Substitutes CLI command arguments in a string with their execution results.
  ///
  /// This function finds patterns like `%{{COMMAND}}` or `%{COMMAND}` and replaces them
  /// with the output of executing the command.
  ///
  /// Parameters:
  /// - `input` - The input string containing command placeholders (can be null)
  ///
  /// Returns the string with command placeholders replaced by their execution results.
  /// If a command fails, it returns stderr output or empty string on error.
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
          final args = _parseCommandArguments(value);
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

  /// Adds new variables to the existing variables map.
  ///
  /// Parameters:
  /// - `newVariables` - A map of new variables to add
  void addVariables(Map<String, dynamic> newVariables) {
    variables.addAll(newVariables);
  }

  /// Replaces the entire variables map with a new one.
  ///
  /// Parameters:
  /// - `newVariables` - A map of variables to replace the current ones
  void replaceVariables(Map<String, dynamic> newVariables) {
    variables = newVariables;
  }

  /// Processes all values in a JSON map by substituting variables.
  ///
  /// This method takes each value in the provided map, converts it to a string,
  /// and processes it for variable substitution.
  ///
  /// Parameters:
  /// - `json` - A map containing key-value pairs to process
  ///
  /// Returns a new map with all values processed for variable substitution.
  Future<Map<String, dynamic>> processMap(Map<String, dynamic> json) async {
    Map<String, dynamic> processedMap = {};
    for (var key in json.keys) {
      processedMap[key] = await process(json[key].toString());
    }
    return processedMap;
  }

  /// Processes input string using system environment variables.
  ///
  /// This is a static utility method that creates a Variables instance from
  /// system environment variables and processes the input string.
  ///
  /// Parameters:
  /// - `input` - The input string to process (can be null)
  /// - `globalResults` - Optional CLI argument results
  ///
  /// Returns the processed string with variables substituted
  static Future<String> processBySystem(
      String? input, ArgResults? globalResults) async {
    return Variables.fromSystem(globalResults).process(input);
  }

  /// Parses command arguments respecting quotes and escaping.
  ///
  /// This private method handles complex command parsing including:
  /// - Single and double quotes
  /// - Escape characters
  /// - Spaces within quoted arguments
  ///
  /// Example: `git log --pretty='format:(%h) %s' --since=yesterday`
  ///
  /// Parameters:
  /// - `command` - The command string to parse
  ///
  /// Returns a list of individual command arguments
  List<String> _parseCommandArguments(String command) {
    final List<String> args = [];
    final StringBuffer currentArg = StringBuffer();
    bool inSingleQuotes = false;
    bool inDoubleQuotes = false;
    bool escaped = false;

    for (int i = 0; i < command.length; i++) {
      final char = command[i];

      if (escaped) {
        currentArg.write(char);
        escaped = false;
        continue;
      }

      if (char == '\\') {
        escaped = true;
        continue;
      }

      if (char == "'" && !inDoubleQuotes) {
        inSingleQuotes = !inSingleQuotes;
        continue;
      }

      if (char == '"' && !inSingleQuotes) {
        inDoubleQuotes = !inDoubleQuotes;
        continue;
      }

      if (char == ' ' && !inSingleQuotes && !inDoubleQuotes) {
        if (currentArg.isNotEmpty) {
          args.add(currentArg.toString());
          currentArg.clear();
        }
        continue;
      }

      currentArg.write(char);
    }

    if (currentArg.isNotEmpty) {
      args.add(currentArg.toString());
    }

    return args;
  }
}
