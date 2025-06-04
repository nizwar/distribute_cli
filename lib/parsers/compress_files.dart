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
        ["Get-Command", "Compress-Archive"],
        runInShell: true,
      ).then((value) => value.exitCode == 0);
    } else if (Platform.isMacOS || Platform.isLinux) {
      // Check if zip command is available in PATH
      return await Process.run("which", ["zip"])
          .then((value) => value.exitCode == 0);
    } else {
      throw UnsupportedError(
          "Unsupported platform for compression tools check");
    }
  }

  /// Compresses files from the source directory into a ZIP archive.
  ///
  /// - `source` - Source directory path containing files to compress
  /// - `destination` - Destination path for the compressed archive
  ///
  /// Returns the process exit code (0 indicates success).
  ///
  /// The compression includes all files in the source directory and creates
  /// a file named "debug_symbols.zip" in the source directory. The method
  /// uses platform-specific compression tools:
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
  ///   '/path/to/output.zip',
  /// );
  /// if (exitCode == 0) {
  ///   print('Compression successful');
  /// } else {
  ///   print('Compression failed with exit code: $exitCode');
  /// }
  /// ```
  static Future<int> compress(String source, String destination) {
    if (Platform.isWindows) {
      // Use PowerShell Compress-Archive to create ZIP file
      return Process.run(
        "powershell",
        [
          "Compress-Archive",
          "-Path",
          "*", // Compress all files in the working directory
          "-DestinationPath",
          "debug_symbols.zip"
        ],
        runInShell: true,
        workingDirectory: source, // Set working directory to source path
      ).then((value) => value.exitCode);
    } else if (Platform.isMacOS || Platform.isLinux) {
      // Use zip command with recursive option
      return Process.run("zip", ["-r", "debug_symbols.zip", "."],
              workingDirectory: source) // Set working directory to source path
          .then((value) => value.exitCode);
    } else {
      throw UnsupportedError("Unsupported platform for compression");
    }
  }
}
