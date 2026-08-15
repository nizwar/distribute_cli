import 'package:dio/dio.dart';

import '../logger.dart';
import 'variables.dart';

/// When a notification should be delivered.
enum NotifyOn {
  /// Deliver regardless of the outcome.
  always,

  /// Deliver only when every job succeeded.
  success,

  /// Deliver only when at least one job failed.
  failure;

  /// Parses the `on:` key, defaulting to [NotifyOn.always].
  static NotifyOn parse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case null:
      case '':
      case 'always':
        return NotifyOn.always;
      case 'success':
        return NotifyOn.success;
      case 'failure':
        return NotifyOn.failure;
      default:
        throw ArgumentError(
          "Invalid notification 'on' value '$value'. "
          "Expected one of: always, success, failure.",
        );
    }
  }

  /// Whether this trigger fires for a run that ended in [succeeded].
  bool shouldFire({required bool succeeded}) => switch (this) {
        NotifyOn.always => true,
        NotifyOn.success => succeeded,
        NotifyOn.failure => !succeeded,
      };
}

/// The chat platform a notification is delivered to.
///
/// Each provider only differs in the JSON body it expects; the transport is an
/// ordinary webhook POST in every case.
enum NotifyProvider {
  /// Slack incoming webhook.
  slack,

  /// Discord webhook.
  discord,

  /// Telegram bot `sendMessage` API.
  telegram,

  /// Any endpoint accepting an arbitrary JSON body.
  webhook;

  /// Parses the `provider:` key.
  static NotifyProvider parse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'slack':
        return NotifyProvider.slack;
      case 'discord':
        return NotifyProvider.discord;
      case 'telegram':
        return NotifyProvider.telegram;
      case null:
      case '':
      case 'webhook':
        return NotifyProvider.webhook;
      default:
        throw ArgumentError(
          "Invalid notification provider '$value'. "
          "Expected one of: slack, discord, telegram, webhook.",
        );
    }
  }
}

/// A single entry of the top level `notifications:` section.
///
/// Notifications are delivered once, after every task has finished, and receive
/// the run summary. Modelling them at run level rather than as a job is what
/// makes `on: failure` possible: a job placed after a failing build would never
/// be reached.
///
/// ```yaml
/// notifications:
///   - provider: slack
///     webhook-url: "${{SLACK_WEBHOOK}}"
///     on: always
///     title: "Android release"
/// ```
class NotificationConfig {
  /// Target chat platform.
  final NotifyProvider provider;

  /// Endpoint the payload is posted to.
  final String webhookUrl;

  /// Condition under which the notification fires.
  final NotifyOn on;

  /// Optional heading prepended to the generated summary.
  final String? title;

  /// Optional message replacing the generated summary entirely.
  final String? message;

  /// Telegram chat identifier. Required for [NotifyProvider.telegram].
  final String? chatId;

  /// Creates a notification entry.
  NotificationConfig({
    required this.provider,
    required this.webhookUrl,
    this.on = NotifyOn.always,
    this.title,
    this.message,
    this.chatId,
  });

  /// Builds a notification from its YAML mapping.
  ///
  /// Throws [ArgumentError] with an actionable message when a required key is
  /// missing, so [ConfigParser] can surface it with the position in the file.
  factory NotificationConfig.fromJson(Map<String, dynamic> json) {
    final provider = NotifyProvider.parse(_text(json, 'provider'));
    final webhookUrl = _text(json, 'webhook-url');

    if (webhookUrl == null || webhookUrl.trim().isEmpty) {
      throw ArgumentError("notifications entry requires a 'webhook-url'.");
    }

    final chatId = json['chat-id']?.toString();
    if (provider == NotifyProvider.telegram &&
        (chatId == null || chatId.isEmpty)) {
      throw ArgumentError(
        "The telegram notification provider requires a 'chat-id'.",
      );
    }

    return NotificationConfig(
      provider: provider,
      webhookUrl: webhookUrl,
      on: NotifyOn.parse(_text(json, 'on')),
      title: _text(json, 'title'),
      message: _text(json, 'message'),
      chatId: chatId,
    );
  }

  /// Reads a text field, naming the key when the YAML holds another shape.
  ///
  /// A bare cast here throws a TypeError, which is an Error rather than an
  /// Exception; it escaped the handler in [ConfigParser] and reached the user
  /// as a raw Dart message that named neither the entry nor the key.
  static String? _text(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    throw ArgumentError("'$key' must be text, not ${value.runtimeType}.");
  }

  /// Serialises the entry back to its YAML shape.
  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'webhook-url': webhookUrl,
        'on': on.name,
        if (title != null) 'title': title,
        if (message != null) 'message': message,
        if (chatId != null) 'chat-id': chatId,
      };

  /// Renders the request body for [provider].
  Map<String, dynamic> buildPayload(String text) => switch (provider) {
        NotifyProvider.slack => {'text': text},
        NotifyProvider.discord => {'content': text},
        NotifyProvider.telegram => {'chat_id': chatId, 'text': text},
        // A generic endpoint gets a self-describing body rather than a shape
        // borrowed from one of the chat providers.
        NotifyProvider.webhook => {
            'text': text,
            'source': 'distribute_cli',
          },
      };
}

/// Delivers [NotificationConfig] entries over HTTP.
class Notifier {
  final ColorizeLogger _logger;
  final Variables _variables;
  final Dio _dio;

  /// Creates a notifier bound to a logger and a variable resolver.
  ///
  /// All three timeouts are bounded on purpose: notifications are delivered
  /// after the last job, so an unroutable webhook host would otherwise hold the
  /// run open for the operating system's TCP timeout with nothing left to do.
  Notifier(this._logger, this._variables, {Dio? client})
      : _dio = client ??
            Dio(
              BaseOptions(
                connectTimeout: _timeout,
                sendTimeout: _timeout,
                receiveTimeout: _timeout,
              ),
            );

  static const Duration _timeout = Duration(seconds: 10);

  /// Sends every notification whose trigger matches the run outcome.
  ///
  /// Delivery failures are reported but never change the exit code: a broken
  /// webhook must not turn a successful release into a failed one.
  Future<void> dispatch(
    List<NotificationConfig> notifications, {
    required bool succeeded,
    required String summary,
  }) async {
    final pending = notifications
        .where(
            (notification) => notification.on.shouldFire(succeeded: succeeded))
        .toList();
    if (pending.isEmpty) return;

    for (final notification in pending) {
      await _send(notification, succeeded: succeeded, summary: summary);
    }
  }

  Future<void> _send(
    NotificationConfig notification, {
    required bool succeeded,
    required String summary,
  }) async {
    final url = await _variables.process(notification.webhookUrl);
    ColorizeLogger.registerSecret(url);

    final body = notification.message != null
        ? await _variables.process(notification.message)
        : summary;
    final title = notification.title == null
        ? null
        : await _variables.process(notification.title);

    final icon = succeeded ? '✅' : '❌';
    final heading = title == null ? '' : '$icon $title\n';
    final text = notification.message != null ? body : '$heading$body';

    try {
      final response = await _dio.post(
        url,
        data: notification.buildPayload(text),
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        _logger.logSuccess(
          "Notification sent to ${notification.provider.name}",
        );
      } else {
        _logger.logWarning(
          "Notification to ${notification.provider.name} returned status $status",
        );
      }
    } on DioException catch (e) {
      _logger.logWarning(
        "Failed to notify ${notification.provider.name}: ${e.message}",
      );
    }
  }
}
