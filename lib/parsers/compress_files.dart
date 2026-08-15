import 'dart:io';

/// Utility class for cross-platform file compression operations.
///
/// Provides static methods for checking compression tool availability
/// and performing file compression using platform-appropriate tools.
/// Handles Windows, macOS, and Linux platforms with their respective
/// native compression utilities.
class CompressFiles {
  /// Checks if the required compression tools are available on the current platform.
  ///
  /// Returns `true` if the compression tools are available, `false` otherwise.
  ///
  /// Platform-specific tools checked:
  /// - Windows: PowerShell's `Compress-Archive` cmdlet
  /// - macOS/Linux: `zip` command-line utility
  ///
  /// Throws `UnsupportedError` for unsupported platforms.
  ///
  /// Example usage:
  /// ```dart
  /// if (await CompressFiles.checkTools()) {
  ///   print('Compression tools are available');
  /// } else {
  ///   print('Compression tools not found');
  /// }
  /// ```
  static Future<bool> checkTools() async {
    if (Platform.isWindows) {
      // Check if PowerShell Compress-Archive cmdlet is available
      return await Process.run(
              "powershell",
              [
                "Get-Command",
                "Compress-Archive",
              ],
              runInShell: true)
          .then((value) => value.exitCode == 0);
    } else if (Platform.isMacOS || Platform.isLinux) {
      // Check if zip command is available in PATH
      return await Process.run("which", [
        "zip",
      ]).then((value) => value.exitCode == 0);
    } else {
      throw UnsupportedError(
        "Unsupported platform for compression tools check",
      );
    }
  }

  /// Compresses the contents of [source] into an archive named [archiveName].
  ///
  /// - `source` - Source directory whose contents are archived
  /// - `archiveName` - File name of the archive, created inside [source]
  ///
  /// Returns the process exit code (0 indicates success), or `127` when the
  /// archiver is not installed.
  ///
  /// The method uses platform-specific compression tools:
  ///
  /// - Windows: PowerShell's `Compress-Archive` cmdlet
  /// - macOS/Linux: `zip` command with recursive option
  ///
  /// Throws `UnsupportedError` for unsupported platforms.
  ///
  /// Example usage:
  /// ```dart
  /// final exitCode = await CompressFiles.compress(
  ///   '/path/to/source/directory',
  ///   'debug_symbols.zip',
  /// );
  /// ```
  static Future<int> compress(String source, String archiveName) async {
    final List<String> executable;
    if (Platform.isWindows) {
      executable = [
        "powershell",
        "Compress-Archive",
        "-Path",
        "*", // Compress all files in the working directory
        "-DestinationPath",
        archiveName,
        "-Force",
      ];
    } else if (Platform.isMacOS || Platform.isLinux) {
      executable = ["zip", "-r", archiveName, "."];
    } else {
      throw UnsupportedError("Unsupported platform for compression");
    }

    try {
      final result = await Process.run(
        executable.first,
        executable.sublist(1),
        runInShell: Platform.isWindows,
        workingDirectory: source,
      );
      return result.exitCode;
    } on ProcessException {
      return 127;
    }
  }
}
