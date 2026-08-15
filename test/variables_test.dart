import 'package:distribute_cli/parsers/variables.dart';
import 'package:test/test.dart';

void main() {
  _processMapNulls();

  Variables variables([Map<String, dynamic>? values]) =>
      Variables(values ?? <String, dynamic>{}, null);

  group('variable substitution', () {
    test('replaces the double brace form', () async {
      final result =
          await variables({'PKG': 'com.example'}).process(r'${{PKG}}.debug');
      expect(result, 'com.example.debug');
    });

    test('replaces the single brace form', () async {
      final result =
          await variables({'PKG': 'com.example'}).process(r'${PKG}.debug');
      expect(result, 'com.example.debug');
    });

    test('leaves unknown variables untouched so they stay visible', () async {
      final result = await variables().process(r'${{MISSING}}');
      expect(result, r'${{MISSING}}');
    });

    test('replaces several variables in one string', () async {
      final result = await variables({'A': '1', 'B': '2'})
          .process(r'${{A}}-${{B}}-${{A}}');
      expect(result, '1-2-1');
    });

    test('returns an empty string for a null input', () async {
      expect(await variables().process(null), '');
    });
  });

  group('command substitution', () {
    test('replaces %{{command}} with the command output', () async {
      final result = await variables().process('%{{echo hello}}');
      expect(result.trim(), 'hello');
    });

    test('honours quoting when splitting arguments', () async {
      final result = await variables().process('%{{echo "a b"}}');
      expect(result.trim(), 'a b');
    });

    test('resolves a command embedded in surrounding text', () async {
      final result = await variables().process('v%{{echo 1.2.3}}-release');
      expect(result.trim(), 'v1.2.3-release');
    });

    test('fails when the command does not exist', () async {
      // It used to substitute an empty string, so `%{{git describe}}` on a
      // machine without git produced `--build-name=` and a green run.
      expect(
        variables().process('%{{definitely-not-a-real-binary}}'),
        throwsA(isA<VariableException>()),
      );
    });

    test('fails when the command exits non-zero', () async {
      // The old behaviour substituted stderr, which contains spaces and so
      // split into extra arguments on the flutter command line.
      expect(
        variables().process('%{{sh -c "echo boom >&2; exit 3"}}'),
        throwsA(
          isA<VariableException>().having(
            (e) => e.message,
            'message',
            allOf(contains('exited with 3'), contains('boom')),
          ),
        ),
      );
    });

    test('a whitespace-only substitution resolves to nothing', () async {
      expect(await variables().process('a%{{   }}b'), 'ab');
    });
  });

  group('processMap', () {
    test('resolves every value of a map', () async {
      final result = await variables({'HOST': 'example.com'}).processMap({
        'url': r'https://${{HOST}}/api',
        'plain': 'unchanged',
      });

      expect(result['url'], 'https://example.com/api');
      expect(result['plain'], 'unchanged');
    });
  });
}

/// `processMap` stringified everything, turning a null into the literal "null".
void _processMapNulls() {
  group('processMap and null', () {
    test('a null value stays null', () async {
      // It used to become the four-character string "null", which then passed
      // every `isNotEmpty` check — that is how an unset `target-commitish`
      // reached the GitHub API as a branch literally named "null".
      final result = await Variables({}, null).processMap({
        'set': 'value',
        'unset': null,
      });

      expect(result['set'], 'value');
      expect(result['unset'], isNull);
    });

    test('a non-string value is still substituted', () async {
      final result = await Variables({'N': 7}, null).processMap({
        'number': 42,
        'flag': true,
        'ref': r'v${{N}}',
      });

      expect(result['number'], '42');
      expect(result['flag'], 'true');
      expect(result['ref'], 'v7');
    });
  });
}
