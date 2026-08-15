import 'dart:convert';
import 'dart:io';

import 'package:distribute_cli/ai/ai_config.dart';
import 'package:distribute_cli/ai/ai_provider.dart';
import 'package:distribute_cli/ai/providers.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> requests;
  late List<Map<String, String>> headers;
  late Map<String, dynamic> reply;
  late int status;

  setUp(() async {
    requests = [];
    headers = [];
    status = 200;
    reply = {};

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(jsonDecode(body) as Map<String, dynamic>);
      headers.add({
        for (final name in ['authorization', 'x-api-key', 'anthropic-version'])
          if (request.headers.value(name) != null)
            name: request.headers.value(name)!,
      });

      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(reply));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  String url() => 'http://${server.address.host}:${server.port}';

  AiConfig configFor(AiProviderKind kind) => AiConfig(
        provider: kind,
        baseUrl: url(),
        model: 'test-model',
        apiKey: 'secret-key-value',
      );

  group('AiAction', () {
    test('builds the argument vector for a scoped run', () {
      final action = AiAction.fromJson({
        'command': 'run',
        'operation': 'ios.build',
        'reason': 'Builds the iOS binary only.',
      });

      expect(action.toArguments(), ['run', '-o', 'ios.build']);
      expect(action.commandLine, 'distribute run -o ios.build');
    });

    test('carries the dry-run flag', () {
      final action = AiAction.fromJson({
        'command': 'run',
        'operation': 'android',
        'dry_run': true,
        'reason': 'Preview only.',
      });

      expect(action.toArguments(), ['run', '-o', 'android', '--dry-run']);
    });

    test('drops run-only options from other commands', () {
      final action = AiAction.fromJson({
        'command': 'doctor',
        'operation': 'android',
        'dry_run': true,
        'reason': 'Checks the environment.',
      });

      expect(action.toArguments(), ['doctor']);
    });

    test('rejects a command outside the schema', () {
      // The model can only reach commands that exist; anything else is refused
      // rather than executed.
      expect(
        () => AiAction.fromJson({'command': 'rm -rf /', 'reason': 'nope'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing command', () {
      expect(
        () => AiAction.fromJson({'reason': 'nope'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OpenAI-compatible provider', () {
    test('sends a bearer token and a function tool', () async {
      reply = {
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'function': {
                    'name': 'run_distribute',
                    'arguments':
                        '{"command":"run","operation":"ios.build","reason":"Builds iOS."}',
                  },
                },
              ],
            },
          },
        ],
      };

      final result = await createProvider(configFor(AiProviderKind.openai))
          .complete(context: 'ctx', prompt: 'build the ios app');

      expect(result.action!.toArguments(), ['run', '-o', 'ios.build']);
      expect(headers.single['authorization'], 'Bearer secret-key-value');
      expect(requests.single['model'], 'test-model');
      expect(requests.single['tools'][0]['type'], 'function');
    });

    test('returns prose when the model does not call the tool', () async {
      reply = {
        'choices': [
          {
            'message': {'content': 'There is no ios task in this project.'}
          },
        ],
      };

      final result = await createProvider(configFor(AiProviderKind.openai))
          .complete(context: 'ctx', prompt: 'build ios');

      expect(result.hasAction, isFalse);
      expect(result.text, contains('no ios task'));
    });

    test('reports an unauthorized key in a way the user can act on', () async {
      status = 401;
      reply = {
        'error': {'message': 'bad key'}
      };

      expect(
        () => createProvider(configFor(AiProviderKind.openai))
            .complete(context: 'ctx', prompt: 'build'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('rejected the API key'), contains('ai setup')),
          ),
        ),
      );
    });

    test('names the endpoint on a 404 so a bad base-url is obvious', () async {
      status = 404;

      expect(
        () => createProvider(configFor(AiProviderKind.openai))
            .complete(context: 'ctx', prompt: 'build'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('base-url'), contains('chat/completions')),
          ),
        ),
      );
    });
  });

  group('Anthropic provider', () {
    test('sends x-api-key and a version header, not a bearer token', () async {
      reply = {
        'stop_reason': 'tool_use',
        'content': [
          {
            'type': 'tool_use',
            'name': 'run_distribute',
            'input': {
              'command': 'run',
              'operation': 'android',
              'reason': 'Ships Android.',
            },
          },
        ],
      };

      final result = await createProvider(configFor(AiProviderKind.anthropic))
          .complete(context: 'ctx', prompt: 'release android');

      expect(result.action!.toArguments(), ['run', '-o', 'android']);
      expect(headers.single['x-api-key'], 'secret-key-value');
      expect(headers.single['anthropic-version'], '2023-06-01');
      expect(headers.single.containsKey('authorization'), isFalse);
      // Tools are declared with input_schema here, not a nested function object.
      expect(requests.single['tools'][0]['input_schema'], isA<Map>());
    });

    test('handles a refusal, which arrives as a successful response', () async {
      // The classifier declines with HTTP 200 — reading content without
      // checking stop_reason first would crash or return nothing.
      reply = {
        'stop_reason': 'refusal',
        'stop_details': {'category': 'cyber'},
        'content': [],
      };

      final result = await createProvider(configFor(AiProviderKind.anthropic))
          .complete(context: 'ctx', prompt: 'something declined');

      expect(result.refusal, contains('declined'));
      expect(result.refusal, contains('cyber'));
      expect(result.hasAction, isFalse);
    });

    test('reads text blocks when no tool was called', () async {
      reply = {
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': 'No matching task.'},
        ],
      };

      final result = await createProvider(configFor(AiProviderKind.anthropic))
          .complete(context: 'ctx', prompt: 'build windows');

      expect(result.text, 'No matching task.');
    });
  });

  group('AiConfig', () {
    test('layers command line over yaml over global over environment', () {
      final resolved = AiConfig.resolve(
        yaml: {'model': 'from-yaml', 'base-url': 'https://yaml.example'},
        global: {'model': 'from-global', 'api-key': 'global-key'},
        overrides: {'model': 'from-flag'},
        environment: {'OPENAI_API_KEY': 'env-key'},
      );

      expect(resolved.model, 'from-flag');
      expect(resolved.baseUrl, 'https://yaml.example');
      expect(resolved.apiKey, 'global-key');
    });

    test('yaml can override the global store, including the key', () {
      final resolved = AiConfig.resolve(
        yaml: {'api-key': 'yaml-key'},
        global: {'api-key': 'global-key'},
        environment: {},
      );

      expect(resolved.apiKey, 'yaml-key');
    });

    test('falls back to the environment when nothing else has a key', () {
      final resolved = AiConfig.resolve(
        yaml: {'provider': 'anthropic'},
        global: {},
        environment: {'ANTHROPIC_API_KEY': 'env-key'},
      );

      expect(resolved.apiKey, 'env-key');
      expect(resolved.model, 'claude-opus-5');
      expect(resolved.baseUrl, 'https://api.anthropic.com');
    });

    test('defaults to manual permission', () {
      expect(AiConfig.resolve(global: {}, environment: {}).permission,
          AiPermission.manual);
    });

    test('parses the three permission modes', () {
      expect(AiPermission.parse('manual'), AiPermission.manual);
      expect(AiPermission.parse('auto'), AiPermission.auto);
      expect(AiPermission.parse('plan'), AiPermission.plan);
      expect(() => AiPermission.parse('yolo'), throwsA(isA<ArgumentError>()));
    });

    test('trims a trailing slash so path joining stays predictable', () {
      final resolved = AiConfig.resolve(
        yaml: {'base-url': 'https://example.com/v1/'},
        global: {},
        environment: {},
      );
      expect(resolved.baseUrl, 'https://example.com/v1');
    });

    test('keeps the api key out of the committed section by default', () {
      final config = AiConfig.resolve(global: {}, environment: {});
      expect(config.toYamlSection().containsKey('api-key'), isFalse);
      expect(
        config.toYamlSection(apiKey: r'${{OPENAI_API_KEY}}')['api-key'],
        r'${{OPENAI_API_KEY}}',
      );
    });

    test('distinguishes a literal secret from a placeholder', () {
      expect(AiConfig.looksLikeLiteralSecret('sk-abc123'), isTrue);
      expect(AiConfig.looksLikeLiteralSecret(r'${{OPENAI_API_KEY}}'), isFalse);
      expect(AiConfig.looksLikeLiteralSecret(null), isFalse);
    });
  });
}
