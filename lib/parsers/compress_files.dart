import 'dart:io';

class CompressFiles {
  static Future<bool> checkTools() async {
    if (Platform.isWindows) {
      return await Process.run(
        "powershell",
        ["Get-Command", "Compress-Archive"],
        runInShell: true,
      ).then((value) => value.exitCode == 0);
    } else if (Platform.isMacOS || Platform.isLinux) {
      return await Process.run("which", ["zip"])
          .then((value) => value.exitCode == 0);
    } else {
      throw UnsupportedError(
          "Unsupported platform for compression tools check");
    }
  }

  static Future<int> compress(String path, String destination) {
    if (Platform.isWindows) {
      return Process.run(
        "powershell",
        [
          "Compress-Archive",
          "-Path",
          path,
          "-DestinationPath",
          "debug_symbols.zip"
        ],
        runInShell: true,
      ).then((value) => value.exitCode);
    } else if (Platform.isMacOS || Platform.isLinux) {
      return Process.run(
        "zip",
        ["-r", "debug_symbols.zip", path],
      ).then((value) => value.exitCode);
    } else {
      throw UnsupportedError("Unsupported platform for compression");
    }
  }
}
