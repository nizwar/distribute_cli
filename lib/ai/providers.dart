import 'dart:convert';

import 'package:dio/dio.dart';

import 'ai_config.dart';
import 'ai_provider.dart';

/// Builds the provider matching [config].
AiProvider createProvider(AiConfig config, {Dio? client}) =>
    switch (config.provider) {
      AiProviderKind.openai => OpenAiCompatibleProvider(config, client: client),
      AiProviderKind.anthropic => AnthropicProvider(config, client: client),
    };

/// Shared HTTP plumbing for both providers.
abstract class _HttpProvider extends AiProvider {
  final Dio _dio;

  _HttpProvider(super.config, {Dio? client})
      : _dio = client ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 120),
              ),
            );

  /// POSTs [body] to [url] and returns the decoded map.
  ///
  /// Turns every transport and protocol failure into an [AiException] carrying
  /// a message that names the endpoint, so a wrong `base-url` is obvious.
  Future<Map<String, dynamic>> post(
    String url,
    Map<String, dynamic> body,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.post(
        url,
        data: body,
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! Map) {
        throw AiException('$name returned an unexpected response from $url');
      }
      return Map<String, dynamic>.from(data);
    } on DioException catch (e) {
      throw AiException(_describe(e, url));
    }
  }

  /// Turns a Dio failure into something a user can act on.
  String _describe(DioException e, String url) {
    final status = e.response?.statusCode;
    final payload = e.response?.data;
    final detail = payload is Map
        ? (payload['error'] is Map
            ? payload['error']['message']?.toString()
            : payload['error']?.toString())
        : null;

    if (status == 401 || status == 403) {
      return '$name rejected the API key (HTTP $status). '
          'Re-run `distribute ai setup`, or check the key in distribution.yaml.';
    }
    if (status == 404) {
      return '$name returned 404 for $url. Check `base-url` and `model`.';
    }
    if (status == 429) {
      return '$name rate limited the request (HTTP 429). Try again shortly.';
    }
    if (status != null) {
      return '$name failed with HTTP $status${detail == null ? '' : ': $detail'}';
    }
    return 'Could not reach $name at $url: ${e.message}';
  }
}

/// Talks to any endpoint exposing `POST {base-url}/chat/completions`.
///
/// That covers OpenAI itself plus the many services and local runtimes that
/// copied its shape — OpenRouter, Groq, Together, DeepSeek, Ollama — so one
/// adapter serves most of the ecosystem.
class OpenAiCompatibleProvider extends _HttpProvider {
  /// Creates an OpenAI-compatible provider.
  OpenAiCompatibleProvider(super.config, {super.client});

  @override
  String get name => 'OpenAI-compatible endpoint';

  @override
  Future<AiReply> complete({
    required String context,
    required String prompt,
  }) async {
    final body = await post(
      '${config.baseUrl}/chat/completions',
      {
        'model': config.model,
        'max_tokens': config.maxTokens,
        'messages': [
          {'role': 'system', 'content': context},
          {'role': 'user', 'content': prompt},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': AiProvider.toolName,
              'description': AiProvider.toolDescription,
              'parameters': AiProvider.toolSchema,
            },
          },
        ],
        'tool_choice': 'auto',
      },
      {
        'Content-Type': 'application/json',
        if (config.hasApiKey) 'Authorization': 'Bearer ${config.apiKey}',
      },
    );

    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiException('$name returned no choices');
    }
    final message = choices.first['message'];
    if (message is! Map) {
      throw AiException('$name returned a malformed choice');
    }

    final toolCalls = message['tool_calls'];
    if (toolCalls is List && toolCalls.isNotEmpty) {
      // A reply cut off by the token ceiling still carries a tool call, but its
      // argument JSON is only as complete as the model got. Running that means
      // running a command it never finished choosing.
      if (choices.first['finish_reason'] == 'length') {
        throw AiException(
          'the reply was cut off by the token limit, so the command it was '
          'choosing is incomplete — raise `max-tokens` (currently '
          '${config.maxTokens}) and try again',
        );
      }
      final function = toolCalls.first['function'];
      // Arguments arrive as a JSON *string* here, unlike Anthropic's parsed map.
      final arguments = _decodeArguments(function?['arguments']);
      return AiReply(action: AiAction.fromJson(arguments));
    }

    return AiReply(text: message['content']?.toString());
  }

  /// Parses the JSON-encoded argument string from a function call.
  Map<String, dynamic> _decodeArguments(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        throw AiException('$name returned unparseable tool arguments: $raw');
      }
    }
    throw AiException('$name returned no tool arguments');
  }

  @override
  Future<String> rewrite({
    required String instruction,
    required String text,
  }) async {
    final body = await post(
      '${config.baseUrl}/chat/completions',
      {
        'model': config.model,
        'max_tokens': config.maxTokens,
        'messages': [
          {'role': 'system', 'content': instruction},
          {'role': 'user', 'content': text},
        ],
      },
      {
        'Content-Type': 'application/json',
        if (config.hasApiKey) 'Authorization': 'Bearer ${config.apiKey}',
      },
    );

    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiException('$name returned no choices');
    }
    // Shape first: reading a field off a non-map choice would surface as a raw
    // Dart type error rather than "this endpoint sent something unexpected".
    final choice = choices.first;
    if (choice is! Map) {
      throw AiException('$name returned a malformed choice');
    }
    if (choice['finish_reason'] == 'length') {
      throw AiException(
        'the reply was cut off by the token limit — raise `max-tokens` '
        '(currently ${config.maxTokens}) and try again',
      );
    }
    final message = choice['message'];
    if (message is! Map) {
      throw AiException('$name returned a malformed choice');
    }

    final content = message['content']?.toString().trim() ?? '';
    if (content.isEmpty) throw AiException('$name returned nothing to use');
    return content;
  }
}

/// Talks to Anthropic's Messages API.
///
/// Kept separate from the OpenAI adapter because the shapes genuinely differ:
/// authentication is `x-api-key` rather than a bearer token, tools are declared
/// with `input_schema` instead of a nested `function` object, tool arguments
/// arrive already parsed, and the response is a list of typed content blocks.
class AnthropicProvider extends _HttpProvider {
  /// Creates an Anthropic provider.
  AnthropicProvider(super.config, {super.client});

  @override
  String get name => 'Anthropic';

  @override
  Future<AiReply> complete({
    required String context,
    required String prompt,
  }) async {
    final body = await post(
      '${config.baseUrl}/v1/messages',
      {
        'model': config.model,
        'max_tokens': config.maxTokens,
        // Deliberately no `output_config`/`effort` here. It would suit this
        // task — mapping one sentence to one command needs little reasoning —
        // but it is rejected outright by older Claude models, and the model is
        // the user's choice. Correctness across the range beats the saving.
        'system': context,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'tools': [
          {
            'name': AiProvider.toolName,
            'description': AiProvider.toolDescription,
            'input_schema': AiProvider.toolSchema,
          },
        ],
      },
      {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        if (config.hasApiKey) 'x-api-key': config.apiKey,
      },
    );

    // Safety classifiers can decline a request with a successful HTTP 200, so
    // the stop reason has to be checked before reading any content.
    if (body['stop_reason'] == 'refusal') {
      final details = body['stop_details'];
      final category = details is Map ? details['category']?.toString() : null;
      return AiReply(
        refusal: category == null
            ? 'the model declined this request'
            : 'the model declined this request ($category)',
      );
    }

    // A response cut short by the token ceiling still arrives as HTTP 200 with
    // a `tool_use` block, but its `input` is whatever had been emitted so far.
    // Acting on it means running a command the model never finished choosing —
    // a half-written `{"command":"run"}` is a full-configuration run.
    final truncated = body['stop_reason'] == 'max_tokens';

    final content = body['content'];
    if (content is! List) {
      throw AiException('$name returned no content');
    }

    final buffer = StringBuffer();
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'tool_use':
          final input = block['input'];
          if (input is Map) {
            if (truncated) {
              throw AiException(
                'the reply was cut off by the token limit, so the command it '
                'was choosing is incomplete — raise `max-tokens` (currently '
                '${config.maxTokens}) and try again',
              );
            }
            return AiReply(
                action: AiAction.fromJson(
              Map<String, dynamic>.from(input),
            ));
          }
        case 'text':
          buffer.write(block['text'] ?? '');
      }
    }

    final text = buffer.toString().trim();
    return AiReply(text: text.isEmpty ? null : text);
  }

  @override
  Future<String> rewrite({
    required String instruction,
    required String text,
  }) async {
    final body = await post(
      '${config.baseUrl}/v1/messages',
      {
        'model': config.model,
        'max_tokens': config.maxTokens,
        'system': instruction,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': text},
            ],
          },
        ],
      },
      {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        if (config.hasApiKey) 'x-api-key': config.apiKey,
      },
    );

    if (body['stop_reason'] == 'refusal') {
      throw AiException('the model declined to rewrite this text');
    }
    if (body['stop_reason'] == 'max_tokens') {
      throw AiException(
        'the reply was cut off by the token limit — raise `max-tokens` '
        '(currently ${config.maxTokens}) and try again',
      );
    }

    final content = body['content'];
    if (content is! List) throw AiException('$name returned no content');

    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] ?? '');
      }
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) throw AiException('$name returned nothing to use');
    return result;
  }
}
