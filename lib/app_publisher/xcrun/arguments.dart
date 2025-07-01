import 'package:args/args.dart';
import 'package:distribute_cli/parsers/build_info.dart';

import '../../files.dart';
import '../../parsers/variables.dart';
import '../publisher_arguments.dart';

/// Comprehensive Xcrun arguments for automated iOS App Store distribution.
///
/// Extends `PublisherArguments` to provide Xcrun-specific configuration for
/// distributing iOS applications through App Store Connect. Supports advanced
/// features like JWT authentication, app validation, and multi-platform support.
///
/// Key capabilities:
/// - Xcrun altool integration
/// - App Store Connect API authentication
/// - Application validation workflows
/// - Bundle and version management
/// - Multi-platform iOS distribution
/// - Automated upload processes
///
/// Example usage:
/// ```dart
/// final args = Arguments(
///   variables,
///   filePath: '/path/to/MyApp.ipa',
///   apiKey: 'ABC123DEF4',
///   apiIssuer: '12345678-1234-1234-1234-123456789012',
///   bundleId: 'com.example.myapp',
///   type: 'ios',
///   validateApp: true,
/// );
/// ```
class Arguments extends PublisherArguments {
  /// Creates a new Xcrun publisher arguments instance.
  ///
  /// Initializes Xcrun-specific configuration for automated iOS app distribution
  /// through App Store Connect. Sets up authentication and validation parameters
  /// for Apple's command-line tools.
  ///
  /// Required parameters:
  /// - `variables` - System and environment variables
  /// - `filePath` - Path to the IPA file to upload
  ///
  /// Authentication options (choose one):
  /// - Username/password authentication
  /// - JWT authentication with API key and issuer
  ///
  /// Example:
  /// ```dart
  /// final args = Arguments(
  ///   variables,
  ///   filePath: '/path/to/MyApp.ipa',
  ///   apiKey: 'ABC123DEF4',
  ///   apiIssuer: '12345678-1234-1234-1234-123456789012',
  ///   bundleId: 'com.example.myapp',
  ///   validateApp: true,
  /// );
  /// ```
  Arguments(
    Variables variables, {
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
  }) : super("xcrun", variables, binaryType: "ipa");

  /// Apple ID username for App Store Connect authentication.
  ///
  /// The Apple ID email address used for authentication with App Store Connect.
  /// Required when using username/password authentication method.
  /// Alternative to JWT authentication using API key and issuer.
  ///
  /// Example: "developer@example.com"
  final String? username;

  /// Password for Apple ID authentication.
  ///
  /// Password for the specified Apple ID username. Can be provided as:
  /// - Plain text password (not recommended for production)
  /// - Keychain reference (@keychain:AC_PASSWORD)
  /// - Environment variable (@env:AC_PASSWORD)
  ///
  /// For security, use app-specific passwords when 2FA is enabled.
  /// Example: "@keychain:AC_PASSWORD"
  final String? password;

  /// App Store Connect API key identifier for JWT authentication.
  ///
  /// The key ID of the API key created in App Store Connect.
  /// Used for JWT-based authentication as an alternative to username/password.
  /// Requires corresponding `apiIssuer` for proper authentication.
  ///
  /// Example: "ABC123DEF4"
  /// Can be found in App Store Connect > Users and Access > Keys
  final String? apiKey;

  /// App Store Connect API issuer identifier for JWT authentication.
  ///
  /// The issuer ID associated with the API key from App Store Connect.
  /// Required when using JWT authentication with `apiKey`.
  /// Provides the organization context for API key validation.
  ///
  /// Format: UUID string
  /// Example: "12345678-1234-1234-1234-123456789012"
  final String? apiIssuer;

  /// Apple ID of the target application package.
  ///
  /// The unique Apple ID number assigned to the application in App Store Connect.
  /// Used to identify the specific app for upload and validation operations.
  /// Can be found in App Store Connect app information.
  ///
  /// Example: "1234567890"
  final String? appleId;

  /// Bundle version (CFBundleVersion) of the application.
  ///
  /// The build number or version identifier for the specific build.
  /// Must be unique for each submission to App Store Connect.
  /// Typically incremented for each build.
  ///
  /// Example: "42" or "2024.1.15.1"
  final String? bundleVersion;

  /// Bundle short version string (CFBundleShortVersionString).
  ///
  /// The user-visible version string for the application.
  /// Follows semantic versioning conventions and is displayed
  /// to users in the App Store and device settings.
  ///
  /// Example: "1.2.3" or "2024.1.0"
  final String? bundleShortVersionString;

  /// App Store Connect public ID for multi-provider accounts.
  ///
  /// Required when the Apple ID is associated with multiple App Store Connect
  /// provider organizations. Specifies which provider to use for the upload.
  /// Found in App Store Connect provider information.
  ///
  /// Example: "1234567890"
  final String? ascPublicId;

  /// Platform type for the application distribution.
  ///
  /// Specifies the target platform for the application upload.
  /// Determines validation rules and distribution channels.
  ///
  /// Supported platforms:
  /// - `ios` - iPhone and iPad applications
  /// - `macos` - macOS applications
  /// - `appletvos` - Apple TV applications
  /// - `visionos` - Apple Vision Pro applications
  ///
  /// Default: "iphoneos"
  final String? type;

  /// Whether to validate the application before uploading.
  ///
  /// When `true`, performs comprehensive validation of the IPA file
  /// including code signing, entitlements, and App Store requirements
  /// before attempting upload. Helps catch issues early in the process.
  ///
  /// Validation includes:
  /// - Code signing verification
  /// - Entitlements validation
  /// - App Store compliance checks
  /// - Bundle structure verification
  ///
  /// Default: `false`
  final bool validateApp;

  /// Path to the application archive for upload operations.
  ///
  /// Alternative file path specification for upload operations.
  /// Used when the main `filePath` is used for validation
  /// and a separate path is needed for upload.
  ///
  /// Example: "/path/to/MyApp-Upload.ipa"
  final String? uploadPackage;

  /// Bundle identifier (CFBundleIdentifier) of the application.
  ///
  /// The unique identifier for the application bundle.
  /// Must match the bundle identifier configured in App Store Connect
  /// and the application's Info.plist file.
  ///
  /// Format: Reverse DNS notation
  /// Example: "com.example.myapp"
  final String? bundleId;

  /// Product identifier for hosted content distribution.
  ///
  /// Used for applications that include hosted content or in-app purchases.
  /// Specifies the product ID for content validation and upload.
  /// Required for apps with server-hosted content.
  ///
  /// Example: "com.example.myapp.content"
  final String? productId;

  /// Stock Keeping Unit (SKU) for hosted content.
  ///
  /// Unique identifier for hosted content packages associated with
  /// the application. Used for content management and distribution
  /// tracking in App Store Connect.
  ///
  /// Example: "MyApp-Content-v1"
  final String? sku;

  /// Output format for command execution results.
  ///
  /// Specifies the format for command output and response data.
  /// Useful for parsing results and integration with automation tools.
  ///
  /// Supported formats:
  /// - `normal` - Human-readable text output
  /// - `xml` - Structured XML format
  /// - `json` - JSON format for programmatic parsing
  ///
  /// Default: "normal"
  final String? outputFormat;

  /// Creates Arguments instance from command-line arguments.
  ///
  /// Parses command-line arguments and optional global results to create
  /// a fully configured Xcrun Arguments instance. Handles type conversion
  /// and validation for all Xcrun-specific parameters.
  ///
  /// Parameters:
  /// - `results` - Parsed command-line arguments
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns configured Arguments instance with parsed values.
  /// Uses first rest argument as file path if available, otherwise
  /// defaults to standard iOS distribution output directory.
  factory Arguments.fromArgParser(
          ArgResults results, ArgResults? globalResults) =>
      Arguments(
        Variables.fromSystem(globalResults),
        filePath:
            results.rest.firstOrNull ?? Files.iosDistributionOutputDir.path,
        username: results['username'] as String?,
        password: results['password'] as String?,
        apiKey: results['api-key'] as String?,
        apiIssuer: results['api-issuer'] as String?,
        appleId: results['apple-id'] as String?,
        bundleVersion: results['bundle-version'] as String?,
        bundleShortVersionString:
            results['bundle-short-version-string'] as String?,
        ascPublicId: results['asc-public-id'] as String?,
        type: results['type'] as String?,
        validateApp: results['validate-app'] as bool? ?? false,
        uploadPackage: results['upload-package'] as String?,
        bundleId: results['bundle-id'] as String?,
        productId: results['product-id'] as String?,
        sku: results['sku'] as String?,
        outputFormat: results['output-format'] as String?,
      );

  /// Creates Arguments instance from JSON configuration.
  ///
  /// Deserializes JSON configuration data to create an Xcrun Arguments
  /// instance. Validates required fields and provides proper error handling
  /// for missing or invalid configuration.
  ///
  /// Parameters:
  /// - `json` - JSON configuration map
  /// - `variables` - System variables for interpolation
  ///
  /// Returns configured Arguments instance from JSON data.
  ///
  /// Throws Exception if required field is missing:
  /// - "file-path" is required
  ///
  /// Example JSON:
  /// ```json
  /// {
  ///   "file-path": "/path/to/MyApp.ipa",
  ///   "api-key": "ABC123DEF4",
  ///   "api-issuer": "12345678-1234-1234-1234-123456789012",
  ///   "bundle-id": "com.example.myapp",
  ///   "validate-app": true
  /// }
  /// ```
  factory Arguments.fromJson(Map<String, dynamic> json,
      {required Variables variables}) {
    if (json['file-path'] == null) throw Exception("file-path is required");
    return Arguments(
      variables,
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

  /// Builds the Xcrun altool command arguments list.
  ///
  /// Constructs the complete command-line arguments for the Xcrun altool
  /// command. Formats all parameters according to altool expectations
  /// and includes conditional arguments based on configuration.
  ///
  /// Key behavior:
  /// - Uses altool `--upload-app` command
  /// - Includes file path as primary target
  /// - Adds authentication parameters (username/password or JWT)
  /// - Includes validation and upload options
  /// - Handles platform-specific parameters
  ///
  /// Returns list of formatted Xcrun altool command arguments.
  ///
  /// Example output:
  /// ```
  /// ["altool", "--upload-app", "-f", "/path/to/app.ipa",
  ///  "--apiKey", "ABC123DEF4", "--apiIssuer", "12345678..."]
  /// ```
  @override
  List<String> get argumentBuilder {
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
      if (bundleShortVersionString != null) ...[
        '--bundle-short-version-string',
        bundleShortVersionString!
      ],
      if (ascPublicId != null) ...['--asc-public-id', ascPublicId!],
      if (type != null) ...['-t', type!] else ...['--type', "iphoneos"],
      if (validateApp) '-v',
      if (bundleId != null) ...['--bundle-id', bundleId!],
      if (productId != null) ...['--product-id', productId!],
      if (sku != null) ...['--sku', sku!],
      if (outputFormat != null) ...['--output-format', outputFormat!],
    ];
  }

  /// Command-line argument parser for Xcrun publisher.
  ///
  /// Defines all supported command-line options for the Xcrun publisher
  /// with their descriptions, types, defaults, and validation rules.
  /// Used for parsing user input and generating help documentation.
  ///
  /// Includes comprehensive options for:
  /// - File paths and IPA targets
  /// - Authentication methods
  /// - App Store Connect configuration
  /// - Validation and upload controls
  /// - Bundle and version management
  /// - Platform-specific settings
  static ArgParser parser = ArgParser()
    ..addOption('file-path',
        abbr: 'f', help: 'Path to the file to upload', mandatory: true)
    ..addOption('username',
        abbr: 'u', help: 'Username for validation and upload')
    ..addOption('password',
        abbr: 'p',
        help:
            'Password for authentication. Can be plaintext, keychain, or environment variable')
    ..addOption('api-key', help: 'API key for JWT authentication')
    ..addOption('api-issuer', help: 'Issuer ID for JWT authentication')
    ..addOption('apple-id', help: 'Apple ID of the app package')
    ..addOption('bundle-version', help: 'Bundle version of the app package')
    ..addOption('bundle-short-version-string',
        help: 'Short version string of the app package')
    ..addOption('asc-public-id',
        help: 'Public ID for accounts with multiple providers')
    ..addOption('type',
        help: 'Platform type (e.g., macos, ios, appletvos, visionos)')
    ..addFlag('validate-app',
        negatable: false, help: 'Validates the app archive for the App Store')
    ..addOption('upload-package', help: 'Path to the app archive for upload')
    ..addOption('bundle-id',
        help: 'Bundle ID of the app', defaultsTo: BuildInfo.iosBundleId)
    ..addOption('product-id', help: 'Product ID for hosted content')
    ..addOption('sku', help: 'SKU for hosted content')
    ..addOption('output-format',
        help: 'Output format (e.g., xml, json, normal)');

  /// Serializes Arguments instance to JSON format.
  ///
  /// Converts all configuration parameters to a JSON-serializable map
  /// for storage, transmission, or configuration file generation.
  /// Includes all Xcrun-specific parameters for complete configuration.
  ///
  /// Returns map containing all configuration parameters with their
  /// current values. Null values are preserved for proper deserialization
  /// and configuration completeness.
  ///
  /// Example output:
  /// ```json
  /// {
  ///   "file-path": "/path/to/MyApp.ipa",
  ///   "api-key": "ABC123DEF4",
  ///   "api-issuer": "12345678-1234-1234-1234-123456789012",
  ///   "bundle-id": "com.example.myapp",
  ///   "validate-app": true,
  ///   "type": "ios"
  /// }
  /// ```
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

  /// Creates default Xcrun configuration for basic usage.
  ///
  /// Generates a basic Xcrun Arguments instance with default settings
  /// suitable for most iOS App Store distribution scenarios. Uses standard
  /// paths and minimal configuration.
  ///
  /// Parameters:
  /// - `globalResults` - Optional global command arguments
  ///
  /// Returns Arguments instance with default configuration:
  /// - Standard iOS distribution output directory
  /// - No authentication or validation configured
  /// - Requires additional setup before use
  ///
  /// Note: This configuration requires proper authentication
  /// parameters (username/password or API key/issuer) before use.
  factory Arguments.defaultConfigs(ArgResults? globalResults) =>
      Arguments(Variables.fromSystem(globalResults),
          filePath: Files.iosDistributionOutputDir.path);
}
