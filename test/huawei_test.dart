import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:dio/dio.dart';
import 'package:distribute_cli/app_publisher/huawei/arguments.dart';
import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/job_arguments.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    ColorizeLogger.verbosity = LogVerbosity.silent;
    ColorizeLogger.logFilePath = '';
    JobArguments.dryRun = false;
  });

  test('requires exactly one supported authentication mode', () {
    Arguments create({String? credential, String? id, String? secret}) =>
        Arguments(
          Variables(<String, dynamic>{}, null),
          filePath: 'app.aab',
          binaryType: 'aab',
          credentialFile: credential,
          clientId: id,
          clientSecret: secret,
        );

    expect(create, throwsArgumentError);
    expect(
      () => create(credential: 'service.json', id: 'id', secret: 'secret'),
      throwsArgumentError,
    );
    expect(() => create(id: 'id', secret: 'secret'), returnsNormally);
    expect(
      () => Arguments(
        Variables(<String, dynamic>{}, null),
        filePath: 'app.aab',
        binaryType: 'aab',
        clientId: 'id',
        clientSecret: 'secret',
        releaseType: 2,
      ),
      throwsArgumentError,
    );
  });

  test('uploads, attaches, polls, adds notes, and submits through AGC',
      () async {
    final sandbox = Directory.systemTemp.createTempSync('distribute_huawei');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final artifact = File('${sandbox.path}/app.aab')
      ..writeAsBytesSync([1, 2, 3]);
    final adapter = _HuaweiAdapter();
    final dio = Dio(BaseOptions(baseUrl: Arguments.defaultBaseUrl))
      ..httpClientAdapter = adapter;
    final arguments = Arguments(
      Variables(<String, dynamic>{}, null),
      filePath: artifact.path,
      binaryType: 'aab',
      clientId: 'client',
      clientSecret: 'secret',
      releaseNotes: 'Fixed bugs',
      releaseType: 1,
      pollInterval: const Duration(milliseconds: 1),
      dio: dio,
    )..packageNameOverride = 'com.example.app';

    expect(await arguments.publish(), 0);
    expect(
      adapter.calls,
      containsAllInOrder([
        'POST /api/oauth2/v1/token',
        'GET /api/publish/v2/appid-list',
        'GET /api/publish/v2/upload-url',
        'POST /binary',
        'PUT /api/publish/v2/app-file-info',
        'GET /api/publish/v3/package/compile/status',
        'PUT /api/publish/v2/app-language-info',
        'POST /api/publish/v2/app-submit',
      ]),
    );
    final uploadUrlRequest = adapter.requests.firstWhere(
      (request) => request.path.endsWith('/publish/v2/upload-url'),
    );
    expect(uploadUrlRequest.queryParameters['releaseType'], 1);

    final uploadRequest = adapter.requests.firstWhere(
      (request) => request.uri.path == '/binary',
    );
    expect(uploadRequest.headers.containsKey('Authorization'), isFalse);
    expect(uploadRequest.headers.containsKey('client_id'), isFalse);

    final attachRequest = adapter.requests.firstWhere(
      (request) => request.path.endsWith('/publish/v2/app-file-info'),
    );
    final attachBody = Map<String, dynamic>.from(attachRequest.data as Map);
    final attachedFile = Map<String, dynamic>.from(
      (attachBody['files'] as List).single as Map,
    );
    expect(attachedFile['fileDestUrl'], 'dest/app.aab');
    expect(attachedFile.containsKey('fileDestUlr'), isFalse);
  });

  test('service account creates the required PS256 JWT claims', () async {
    final sandbox = Directory.systemTemp.createTempSync('distribute_huawei');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final artifact = File('${sandbox.path}/app.aab')
      ..writeAsBytesSync([1, 2, 3]);
    final dynamic keyPair = CryptoUtils.generateRSAKeyPair(keySize: 1024);
    final credential = File('${sandbox.path}/service-account.json')
      ..writeAsStringSync(jsonEncode({
        'key_id': 'key-123',
        'sub_account': 'account-456',
        'private_key': CryptoUtils.encodeRSAPrivateKeyToPem(
          keyPair.privateKey,
        ),
        'token_uri': 'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
      }));
    final adapter = _HuaweiAdapter();
    final dio = Dio(BaseOptions(baseUrl: Arguments.defaultBaseUrl))
      ..httpClientAdapter = adapter;
    final arguments = Arguments(
      Variables(<String, dynamic>{}, null),
      filePath: artifact.path,
      binaryType: 'aab',
      credentialFile: credential.path,
      appId: 'app-123',
      submit: false,
      pollInterval: const Duration(milliseconds: 1),
      dio: dio,
    )..packageNameOverride = 'com.example.app';

    expect(await arguments.publish(), 0);
    final authenticated = adapter.requests.firstWhere(
      (request) => request.path.endsWith('/publish/v2/upload-url'),
    );
    final authorization = authenticated.headers['Authorization'] as String;
    final parts = authorization.substring('Bearer '.length).split('.');
    expect(parts, hasLength(3));
    final header = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
    ) as Map;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map;
    expect(header, containsPair('alg', 'PS256'));
    expect(header, containsPair('kid', 'key-123'));
    expect(payload, containsPair('iss', 'account-456'));
    expect(
      payload,
      containsPair(
        'aud',
        'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
      ),
    );
    expect((payload['exp'] as int) - (payload['iat'] as int), 3600);
  });

  test('cancellation interrupts the compilation polling delay', () async {
    final sandbox = Directory.systemTemp.createTempSync('distribute_huawei');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final artifact = File('${sandbox.path}/app.aab')
      ..writeAsBytesSync([1, 2, 3]);
    final adapter = _HuaweiAdapter(compileStatus: 1);
    final dio = Dio(BaseOptions(baseUrl: Arguments.defaultBaseUrl))
      ..httpClientAdapter = adapter;
    final arguments = Arguments(
      Variables(<String, dynamic>{}, null),
      filePath: artifact.path,
      binaryType: 'aab',
      clientId: 'client',
      clientSecret: 'secret',
      appId: 'app-123',
      submit: false,
      pollInterval: const Duration(seconds: 5),
      dio: dio,
    )..packageNameOverride = 'com.example.app';

    final stopwatch = Stopwatch()..start();
    final result = await JobArguments.withProcessScope(() async {
      final publishing = arguments.publish();
      while (!adapter.calls.any(
        (call) => call.contains('/package/compile/status'),
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await JobArguments.terminateScopedProcesses();
      return publishing;
    });
    stopwatch.stop();

    expect(result, 1);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}

class _HuaweiAdapter implements HttpClientAdapter {
  final int compileStatus;
  final List<String> calls = [];
  final List<RequestOptions> requests = [];

  _HuaweiAdapter({this.compileStatus = 0});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.uri.path}');
    requests.add(options);
    final path = options.uri.path;
    final Object body;
    if (path.endsWith('/oauth2/v1/token')) {
      body = {'access_token': 'test-token'};
    } else if (path.endsWith('/publish/v2/appid-list')) {
      body = {
        'code': 0,
        'data': [
          {'appId': 'app-123'},
        ],
      };
    } else if (path.endsWith('/publish/v2/upload-url')) {
      body = {
        'code': 0,
        'data': {
          'uploadUrl': 'https://upload.test/binary',
          'authCode': 'upload-auth',
        },
      };
    } else if (path == '/binary') {
      body = {
        'code': 0,
        'data': {
          'fileInfoList': [
            {'fileDestUlr': 'dest/app.aab'},
          ],
        },
      };
    } else if (path.endsWith('/publish/v2/app-file-info')) {
      body = {
        'code': 0,
        'data': {'packageId': 'package-123'},
      };
    } else if (path.endsWith('/publish/v3/package/compile/status')) {
      body = {
        'code': 0,
        'data': {'successStatus': compileStatus},
      };
    } else if (path.endsWith('/publish/v2/app-language-info') ||
        path.endsWith('/publish/v2/app-submit')) {
      body = {'code': 0};
    } else {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
