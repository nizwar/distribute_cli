import 'dart:convert';
import 'dart:io';

import 'package:distribute_cli/logger.dart';
import 'package:distribute_cli/parsers/notification_config.dart';
import 'package:distribute_cli/parsers/variables.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> received;
  late Directory sandbox;
  late int status;

  setUp(() async {
    sandbox = Directory.systemTemp.createTempSync('distribute_cli_notifier');
    ColorizeLogger.logFilePath =
        '${sandbox.path}${Platform.pathSeparator}distribution.log';
    ColorizeLogger.clearSecrets();

    received = [];
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add(jsonDecode(body) as Map<String, dynamic>);
      request.response.statusCode = status;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    ColorizeLogger.clearSecrets();
    sandbox.deleteSync(recursive: true);
  });

  String url() => 'http://${server.address.host}:${server.port}/hook';

  Notifier notifier([Map<String, dynamic>? variables]) => Notifier(
        ColorizeLogger(false),
        Variables(variables ?? <String, dynamic>{}, null),
      );

  test('posts the run summary to a slack webhook', () async {
    await notifier().dispatch(
      [
        NotificationConfig(
          provider: NotifyProvider.slack,
          webhookUrl: url(),
          title: 'Android release',
        ),
      ],
      succeeded: true,
      summary: '2/2 job(s) succeeded in 1m 4s',
    );

    expect(received, hasLength(1));
    expect(received.single['text'], contains('Android release'));
    expect(received.single['text'], contains('2/2 job(s) succeeded'));
    expect(received.single['text'], contains('✅'));
  });

  test('marks a failed run and uses the discord body shape', () async {
    await notifier().dispatch(
      [NotificationConfig(provider: NotifyProvider.discord, webhookUrl: url())],
      succeeded: false,
      summary: '0/1 job(s) succeeded',
    );

    expect(received.single.containsKey('content'), isTrue);
    expect(received.single['content'], contains('0/1 job(s) succeeded'));
  });

  test('only fires the notifications matching the outcome', () async {
    await notifier().dispatch(
      [
        NotificationConfig(
          provider: NotifyProvider.slack,
          webhookUrl: url(),
          on: NotifyOn.failure,
        ),
        NotificationConfig(
          provider: NotifyProvider.slack,
          webhookUrl: url(),
          on: NotifyOn.success,
        ),
        NotificationConfig(
          provider: NotifyProvider.slack,
          webhookUrl: url(),
          on: NotifyOn.always,
        ),
      ],
      succeeded: true,
      summary: 'summary',
    );

    expect(received, hasLength(2), reason: 'success + always');
  });

  test('substitutes variables in the webhook url and the message', () async {
    await notifier({'HOOK': url(), 'APP': 'Demo'}).dispatch(
      [
        NotificationConfig(
          provider: NotifyProvider.webhook,
          webhookUrl: r'${{HOOK}}',
          message: r'${{APP}} shipped',
        ),
      ],
      succeeded: true,
      summary: 'ignored because message is set',
    );

    expect(received.single['text'], 'Demo shipped');
    expect(received.single['source'], 'distribute_cli');
  });

  test('a rejected delivery is reported but does not throw', () async {
    status = 500;
    await expectLater(
      notifier().dispatch(
        [NotificationConfig(provider: NotifyProvider.slack, webhookUrl: url())],
        succeeded: true,
        summary: 'summary',
      ),
      completes,
    );
  });

  test('an unreachable endpoint does not throw either', () async {
    // Capture the address before closing: `server.address` throws once the
    // socket is gone.
    final deadUrl = url();
    await server.close(force: true);

    await expectLater(
      notifier().dispatch(
        [
          NotificationConfig(
              provider: NotifyProvider.slack, webhookUrl: deadUrl)
        ],
        succeeded: true,
        summary: 'summary',
      ),
      completes,
    );
    expect(received, isEmpty);
  });

  test('the webhook url is registered as a secret', () async {
    await notifier().dispatch(
      [NotificationConfig(provider: NotifyProvider.slack, webhookUrl: url())],
      succeeded: true,
      summary: 'summary',
    );

    expect(ColorizeLogger.redact('posting to ${url()}'), 'posting to ***');
  });
}
