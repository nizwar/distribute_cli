import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:dio/dio.dart';

import '../../files.dart';
import '../../logger.dart';
import '../../parsers/duration.dart';
import '../../parsers/job_arguments.dart';
import '../../parsers/variables.dart';
import '../publisher_arguments.dart';

/// Publishes Android artifacts through the AppGallery Connect REST API.
class Arguments extends PublisherArguments {
  static const defaultBaseUrl = 'https://connect-api.cloud.huawei.com/api';

  final String? credentialFile;
  final String? clientId;
  final String? clientSecret;
  final String? appId;
  final String? releaseNotes;
  final String language;
  final bool submit;
  final int releaseType;
  final Duration pollInterval;
  final Duration pollTimeout;
  final String baseUrl;
  final Dio _dio;
  final CancelToken _cancelToken = CancelToken();

  Arguments(
    Variables variables, {
    required super.filePath,
    required super.binaryType,
    this.credentialFile,
    this.clientId,
    this.clientSecret,
    this.appId,
    this.releaseNotes,
    this.language = 'en-US',
    this.submit = true,
    this.releaseType = 1,
    this.pollInterval = const Duration(seconds: 15),
    this.pollTimeout = const Duration(minutes: 10),
    this.baseUrl = defaultBaseUrl,
    Dio? dio,
  })  : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)),
        super('huawei', variables) {
    final serviceAccount = credentialFile?.trim().isNotEmpty == true;
    final apiClient = clientId?.trim().isNotEmpty == true &&
        clientSecret?.trim().isNotEmpty == true;
    if (serviceAccount == apiClient) {
      throw ArgumentError(
        'Huawei requires either credential-file (recommended Service Account) '
        'or both client-id and client-secret, but not both modes.',
      );
    }
    if (!{'apk', 'aab'}.contains(binaryType.toLowerCase())) {
      throw ArgumentError("Huawei binary-type must be 'apk' or 'aab'.");
    }
    if (releaseType != 1) {
      throw ArgumentError(
        'Huawei currently supports release-type 1 only; phased release '
        'requires additional rollout settings.',
      );
    }
  }

  @override
  Set<String> get secretKeys => const {'client-secret'};

  @override
  List<String> get argumentBuilder => const [];

  @override
  Map<String, dynamic> toJson() => {
        'file-path': filePath,
        'binary-type': binaryType,
        'credential-file': credentialFile,
        'client-id': clientId,
        'client-secret': clientSecret,
        'app-id': appId,
        'release-notes': releaseNotes,
        'language': language,
        'submit': submit,
        'release-type': releaseType,
        'poll-interval': formatDurationValue(pollInterval),
        'poll-timeout': formatDurationValue(pollTimeout),
        'base-url': baseUrl,
      };

  @override
  Future<int> publish() async {
    await registerSecrets();
    final resolved = Arguments.fromJson(
      await variables.processMap(toJson()),
      variables: variables,
      dio: _dio,
    );
    resolved.packageNameOverride = packageNameOverride;
    await resolved.processFilesArgs();
    if (resolved.filePath.isEmpty) {
      if (JobArguments.dryRun) {
        logger.logNote('no $binaryType artifact yet (dry run)');
        return 0;
      }
      logger.logError('No $binaryType artifact found for Huawei.');
      return 1;
    }

    await resolved.printJob();
    if (JobArguments.dryRun) {
      logger.logInfo(
        '[dry-run] would upload ${resolved.filePath} to Huawei AppGallery'
        '${resolved.submit ? ' and submit it for release' : ''}',
      );
      return 0;
    }

    try {
      JobArguments.trackCancellation(
        () => resolved._cancelToken.cancel('job cancelled'),
      );
      await resolved._authenticate();
      final targetAppId = await resolved._resolveAppId();
      final upload = await resolved._upload(targetAppId);
      final packageId = await resolved._attachFile(targetAppId, upload);
      if (packageId != null) {
        await resolved._waitForCompilation(targetAppId, packageId);
      } else {
        logger.logWarning(
          'Huawei did not return a package ID; compile polling was skipped.',
        );
      }
      await resolved._updateReleaseNotes(targetAppId);
      if (resolved.submit) await resolved._submit(targetAppId);
      logger.logSuccess('Huawei AppGallery publish completed');
      return 0;
    } on DioException catch (error) {
      final detail = error.response?.data ?? error.message;
      logger.logError('Huawei API request failed: $detail');
      return 1;
    } on Object catch (error, stack) {
      logger.logError('Huawei publish failed: $error');
      logger.logDebug(stack.toString());
      return 1;
    }
  }

  Future<void> _authenticate() async {
    if (credentialFile?.isNotEmpty == true) {
      final jwt = await _serviceAccountJwt(File(credentialFile!));
      ColorizeLogger.registerSecret(jwt);
      _dio.options.headers['Authorization'] = 'Bearer $jwt';
      return;
    }

    ColorizeLogger.registerSecret(clientSecret!);
    final response = await _dio.post<Map<String, dynamic>>(
      '/oauth2/v1/token',
      data: {
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
      },
      cancelToken: _cancelToken,
    );
    final token = response.data?['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw StateError('Huawei token response did not contain access_token.');
    }
    ColorizeLogger.registerSecret(token);
    _dio.options.headers
      ..['Authorization'] = 'Bearer $token'
      ..['client_id'] = clientId;
  }

  Future<String> _resolveAppId() async {
    if (appId?.trim().isNotEmpty == true) return appId!.trim();
    final response = await _dio.get<dynamic>(
      '/publish/v2/appid-list',
      queryParameters: {'packageName': resolvePackageName()},
      cancelToken: _cancelToken,
    );
    _ensureSuccess(response.data, 'resolve app ID');
    final value = _findValue(response.data, const {'appId', 'appid'});
    if (value == null || value.toString().isEmpty) {
      throw StateError(
        'No Huawei app ID found for package ${resolvePackageName()}.',
      );
    }
    return value.toString();
  }

  Future<Map<String, dynamic>> _upload(String targetAppId) async {
    final urlResponse = await _dio.get<dynamic>(
      '/publish/v2/upload-url',
      queryParameters: {
        'appId': targetAppId,
        'suffix': binaryType,
        'releaseType': releaseType,
      },
      cancelToken: _cancelToken,
    );
    _ensureSuccess(urlResponse.data, 'obtain upload URL');
    final uploadUrl = _findValue(urlResponse.data, const {'uploadUrl'});
    final authCode = _findValue(urlResponse.data, const {'authCode'});
    if (uploadUrl == null || authCode == null) {
      throw StateError(
          'Huawei upload URL response is missing uploadUrl/authCode.');
    }

    final file = File(filePath);
    logger.logInfo('Uploading ${file.path} to Huawei AppGallery');
    final authorization = _dio.options.headers.remove('Authorization');
    final apiClient = _dio.options.headers.remove('client_id');
    late final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        uploadUrl.toString(),
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            file.path,
            filename: file.uri.pathSegments.last,
          ),
          'authCode': authCode.toString(),
          'fileCount': 1,
          'parseType': 1,
        }),
        options: Options(contentType: 'multipart/form-data'),
        cancelToken: _cancelToken,
      );
    } finally {
      if (authorization != null) {
        _dio.options.headers['Authorization'] = authorization;
      }
      if (apiClient != null) _dio.options.headers['client_id'] = apiClient;
    }
    _ensureSuccess(response.data, 'upload file');
    final info = _findMapContaining(
      response.data,
      const {'fileDestUlr', 'fileDestUrl', 'objectId'},
    );
    if (info == null) {
      throw StateError(
          'Huawei upload response did not contain file information.');
    }
    final destination = _findValue(
      info,
      const {'fileDestUlr', 'fileDestUrl', 'objectId'},
    );
    if (destination == null || destination.toString().isEmpty) {
      throw StateError('Huawei upload response has an empty destination URL.');
    }
    return {
      'fileName': file.uri.pathSegments.last,
      'fileDestUrl': destination.toString(),
    };
  }

  Future<String?> _attachFile(
    String targetAppId,
    Map<String, dynamic> upload,
  ) async {
    final response = await _dio.put<dynamic>(
      '/publish/v2/app-file-info',
      queryParameters: {'appId': targetAppId, 'releaseType': releaseType},
      data: {
        'fileType': 5,
        'files': [upload],
      },
      cancelToken: _cancelToken,
    );
    _ensureSuccess(response.data, 'attach uploaded file');
    return _findValue(
      response.data,
      const {'packageId', 'pkgId', 'pkgVersion'},
    )?.toString();
  }

  Future<void> _waitForCompilation(String targetAppId, String packageId) async {
    final deadline = DateTime.now().add(pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _dio.get<dynamic>(
        '/publish/v3/package/compile/status',
        queryParameters: {'appId': targetAppId, 'pkgIds': packageId},
        cancelToken: _cancelToken,
      );
      _ensureSuccess(response.data, 'query package compilation');
      final raw = _findValue(response.data, const {'successStatus'});
      final status = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (status == 0) return;
      if (status != null && status < 0) {
        throw StateError('Huawei package compilation failed (status $status).');
      }
      logger.logInfo('Huawei is still compiling the package; waiting...');
      await Future.any<void>([
        Future<void>.delayed(pollInterval),
        _cancelToken.whenCancel.then<void>((error) => throw error),
      ]);
    }
    throw TimeoutException(
      'Huawei package compilation exceeded ${formatDurationValue(pollTimeout)}.',
    );
  }

  Future<void> _updateReleaseNotes(String targetAppId) async {
    if (releaseNotes == null || releaseNotes!.trim().isEmpty) return;
    final response = await _dio.put<dynamic>(
      '/publish/v2/app-language-info',
      queryParameters: {'appId': targetAppId},
      data: {'lang': language, 'newFeatures': releaseNotes},
      cancelToken: _cancelToken,
    );
    _ensureSuccess(response.data, 'update release notes');
  }

  Future<void> _submit(String targetAppId) async {
    final response = await _dio.post<dynamic>(
      '/publish/v2/app-submit',
      queryParameters: {'appId': targetAppId, 'releaseType': releaseType},
      cancelToken: _cancelToken,
    );
    _ensureSuccess(response.data, 'submit release');
  }

  Future<String> _serviceAccountJwt(File file) async {
    if (!await file.exists()) {
      throw StateError('Huawei credential file not found: ${file.path}');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw StateError('Huawei credential file is invalid.');
    final credentials = Map<String, dynamic>.from(decoded);
    final keyId = credentials['key_id']?.toString();
    final issuer = credentials['sub_account']?.toString();
    final privatePem = credentials['private_key']?.toString();
    final audience = credentials['token_uri']?.toString() ??
        'https://oauth-login.cloud.huawei.com/oauth2/v3/token';
    if ([keyId, issuer, privatePem].any((value) => value?.isEmpty != false)) {
      throw StateError(
        'Huawei credential file requires key_id, sub_account, and private_key.',
      );
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final header = _base64UrlJson({'kid': keyId, 'typ': 'JWT', 'alg': 'PS256'});
    final payload = _base64UrlJson({
      'aud': audience,
      'iss': issuer,
      'iat': now,
      'exp': now + 3600,
    });
    final signingInput = '$header.$payload';
    final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privatePem!);
    final salt = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final signature = CryptoUtils.rsaPssSign(
      privateKey,
      Uint8List.fromList(utf8.encode(signingInput)),
      salt,
      algorithm: 'SHA-256/PSS',
    );
    return '$signingInput.${base64Url.encode(signature).replaceAll('=', '')}';
  }

  static String _base64UrlJson(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  static void _ensureSuccess(dynamic data, String operation) {
    final code = _findValue(data, const {'code', 'retCode'});
    if (code == null) return;
    final parsed = code is num ? code.toInt() : int.tryParse(code.toString());
    if (parsed != null && parsed != 0) {
      final message = _findValue(data, const {'msg', 'desc', 'message'});
      throw StateError(
        'Huawei could not $operation (code $parsed)'
        '${message == null ? '' : ': $message'}',
      );
    }
  }

  static dynamic _findValue(dynamic node, Set<String> keys) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (keys.contains(entry.key.toString())) return entry.value;
      }
      for (final value in node.values) {
        final found = _findValue(value, keys);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findValue(value, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findMapContaining(
    dynamic node,
    Set<String> keys,
  ) {
    if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      if (map.keys.any(keys.contains)) return map;
      for (final value in map.values) {
        final found = _findMapContaining(value, keys);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findMapContaining(value, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static bool _bool(dynamic raw, {bool defaultValue = false}) {
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    return raw.toString().toLowerCase() == 'true';
  }

  factory Arguments.fromJson(
    Map<String, dynamic> json, {
    required Variables variables,
    Dio? dio,
  }) {
    if (json['file-path'] == null || json['file-path'].toString().isEmpty) {
      throw ArgumentError('Huawei file-path is required.');
    }
    return Arguments(
      variables,
      filePath: json['file-path'].toString(),
      binaryType: json['binary-type']?.toString() ?? 'aab',
      credentialFile: json['credential-file']?.toString(),
      clientId: json['client-id']?.toString(),
      clientSecret: json['client-secret']?.toString(),
      appId: json['app-id']?.toString(),
      releaseNotes: json['release-notes']?.toString(),
      language: json['language']?.toString() ?? 'en-US',
      submit: _bool(json['submit'], defaultValue: true),
      releaseType: int.tryParse('${json['release-type'] ?? 1}') ?? 1,
      pollInterval: parseDuration(
        json['poll-interval'] ?? '15s',
        label: 'huawei.poll-interval',
        allowZero: false,
      ),
      pollTimeout: parseDuration(
        json['poll-timeout'] ?? '10m',
        label: 'huawei.poll-timeout',
        allowZero: false,
      ),
      baseUrl: json['base-url']?.toString() ?? defaultBaseUrl,
      dio: dio,
    );
  }

  factory Arguments.fromArgResults(ArgResults results, ArgResults? global) =>
      Arguments(
        Variables.fromSystem(global),
        filePath: results['file-path'] as String,
        binaryType: results['binary-type'] as String,
        credentialFile: results['credential-file'] as String?,
        clientId: results['client-id'] as String?,
        clientSecret: results['client-secret'] as String?,
        appId: results['app-id'] as String?,
        releaseNotes: results['release-notes'] as String?,
        language: results['language'] as String,
        submit: results['submit'] as bool,
        releaseType: int.parse(results['release-type'] as String),
        pollInterval: parseDuration(
          results['poll-interval'],
          label: '--poll-interval',
          allowZero: false,
        ),
        pollTimeout: parseDuration(
          results['poll-timeout'],
          label: '--poll-timeout',
          allowZero: false,
        ),
        baseUrl: results['base-url'] as String,
      )..packageNameOverride = results['package-name'] as String?;

  factory Arguments.defaultConfigs(ArgResults? globalResults) => Arguments(
        Variables.fromSystem(globalResults),
        filePath: Files.androidDistributionOutputDir.path,
        binaryType: 'aab',
        credentialFile: r'${{HUAWEI_CREDENTIAL_FILE}}',
      );

  static ArgParser get parser => ArgParser()
    ..addOption('file-path', mandatory: true)
    ..addOption('binary-type', allowed: const ['apk', 'aab'], defaultsTo: 'aab')
    ..addOption('package-name')
    ..addOption('credential-file')
    ..addOption('client-id')
    ..addOption('client-secret')
    ..addOption('app-id')
    ..addOption('release-notes')
    ..addOption('language', defaultsTo: 'en-US')
    ..addFlag('submit', defaultsTo: true)
    ..addOption('release-type', defaultsTo: '1')
    ..addOption('poll-interval', defaultsTo: '15s')
    ..addOption('poll-timeout', defaultsTo: '10m')
    ..addOption('base-url', defaultsTo: defaultBaseUrl);
}
