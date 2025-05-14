import 'package:args/args.dart';

import '../../files.dart';
import '../publisher_arguments.dart';

/// Arguments for publishing iOS apps using Xcrun.
///
/// This class encapsulates all the options and parameters required to distribute
/// an iOS app via Xcrun.
class Arguments extends PublisherArguments {
  /// Constructor for `XcrunIosPublisherArguments`.
  Arguments({
    required super.filePath,
    this.username,
    this.password,
    this.apiKey,
    this.apiIssuer,
    this.appleId,
    this.bundleVersion,
    this.bundleShortVersionString,
    this.ascPublicId,
    this.type,
    this.validateApp = false,
    this.uploadPackage,
    this.bundleId,
    this.productId,
    this.sku,
    this.outputFormat,
  }) : super("xcrun", binaryType: "ipa");

  /// Username for validation and upload.
  final String? username;

  /// Password for authentication. Can be plaintext, keychain, or environment variable.
  final String? password;

  /// API key for JWT authentication.
  final String? apiKey;

  /// Issuer ID for JWT authentication.
  final String? apiIssuer;

  /// Apple ID of the app package.
  final String? appleId;

  /// Bundle version of the app package.
  final String? bundleVersion;

  /// Short version string of the app package.
  final String? bundleShortVersionString;

  /// Public ID for accounts with multiple providers.
  final String? ascPublicId;

  /// The type of distribution (e.g., app-store, ad-hoc).
  final String? type;

  /// Whether to validate the app before uploading.
  final bool validateApp;

  /// Path to the upload package.
  final String? uploadPackage;

  /// Bundle ID of the app.
  final String? bundleId;

  /// Product ID of the app.
  final String? productId;

  /// SKU of the app.
  final String? sku;

  /// Output format for the command.
  final String? outputFormat;

  factory Arguments.fromArgParser(ArgResults results) => Arguments(
        filePath: results.rest.firstOrNull ?? Files.iosDistributionOutputDir.path,
        username: results['username'] as String?,
        password: results['password'] as String?,
        apiKey: results['api-key'] as String?,
        apiIssuer: results['api-issuer'] as String?,
        appleId: results['apple-id'] as String?,
        bundleVersion: results['bundle-version'] as String?,
        bundleShortVersionString: results['bundle-short-version-string'] as String?,
        ascPublicId: results['asc-public-id'] as String?,
        type: results['type'] as String?,
        validateApp: results['validate-app'] as bool? ?? false,
        uploadPackage: results['upload-package'] as String?,
        bundleId: results['bundle-id'] as String?,
        productId: results['product-id'] as String?,
        sku: results['sku'] as String?,
        outputFormat: results['output-format'] as String?,
      );

  factory Arguments.fromJson(Map<String, dynamic> json) {
    if (json['file-path'] == null) throw Exception("file-path is required");
    return Arguments(
      filePath: json['file-path'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      apiKey: json['api-key'] as String?,
      apiIssuer: json['api-issuer'] as String?,
      appleId: json['apple-id'] as String?,
      bundleVersion: json['bundle-version'] as String?,
      bundleShortVersionString: json['bundle-short-version-string'] as String?,
      ascPublicId: json['asc-public-id'] as String?,
      type: json['type'] as String?,
      validateApp: json['validate-app'] as bool? ?? false,
      uploadPackage: json['upload-package'] as String?,
      bundleId: json['bundle-id'] as String?,
      productId: json['product-id'] as String?,
      sku: json['sku'] as String?,
      outputFormat: json['output-format'] as String?,
    );
  }

  @override

  /// Converts the arguments to a list of strings for command-line execution.
  List<String> get results {
    return [
      "altool",
      '--upload-app',
      '-f',
      filePath,
      if (username != null) ...['-u', username!],
      if (password != null) ...['-p', password!],
      if (apiKey != null) ...['--apiKey', apiKey!],
      if (apiIssuer != null) ...['--apiIssuer', apiIssuer!],
      if (appleId != null) ...['--apple-id', appleId!],
      if (bundleVersion != null) ...['--bundle-version', bundleVersion!],
      if (bundleShortVersionString != null) ...['--bundle-short-version-string', bundleShortVersionString!],
      if (ascPublicId != null) ...['--asc-public-id', ascPublicId!],
      if (type != null) ...['-t', type!] else ...['--type', "iphoneos"],
      if (validateApp) '-v',
      if (bundleId != null) ...['--bundle-id', bundleId!],
      if (productId != null) ...['--product-id', productId!],
      if (sku != null) ...['--sku', sku!],
      if (outputFormat != null) ...['--output-format', outputFormat!],
    ];
  }

  static ArgParser parser = ArgParser()
    ..addOption('file-path', abbr: 'f', help: 'Path to the file to upload', mandatory: true)
    ..addOption('username', abbr: 'u', help: 'Username for validation and upload')
    ..addOption('password', abbr: 'p', help: 'Password for authentication. Can be plaintext, keychain, or environment variable')
    ..addOption('api-key', help: 'API key for JWT authentication')
    ..addOption('api-issuer', help: 'Issuer ID for JWT authentication')
    ..addOption('apple-id', help: 'Apple ID of the app package')
    ..addOption('bundle-version', help: 'Bundle version of the app package')
    ..addOption('bundle-short-version-string', help: 'Short version string of the app package')
    ..addOption('asc-public-id', help: 'Public ID for accounts with multiple providers')
    ..addOption('type', help: 'Platform type (e.g., macos, ios, appletvos, visionos)')
    ..addFlag('validate-app', negatable: false, help: 'Validates the app archive for the App Store')
    ..addOption('upload-package', help: 'Path to the app archive for upload')
    ..addOption('bundle-id', help: 'Bundle ID of the app')
    ..addOption('product-id', help: 'Product ID for hosted content')
    ..addOption('sku', help: 'SKU for hosted content')
    ..addOption('output-format', help: 'Output format (e.g., xml, json, normal)');

  @override
  Map<String, dynamic> toJson() => {
        "file-path": filePath,
        "username": username,
        "password": password,
        "binary-type": binaryType,
        "api-key": apiKey,
        "api-issuer": apiIssuer,
        "apple-id": appleId,
        "bundle-version": bundleVersion,
        "bundle-short-version-string": bundleShortVersionString,
        "asc-public-id": ascPublicId,
        "type": type,
        "validate-app": validateApp,
        "upload-package": uploadPackage,
        "bundle-id": bundleId,
        "product-id": productId,
        "sku": sku,
        "output-format": outputFormat,
      };

  factory Arguments.defaultConfigs() => Arguments(filePath: Files.iosDistributionOutputDir.path);
}
