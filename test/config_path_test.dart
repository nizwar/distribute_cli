import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:distribute_cli/command.dart';
import 'package:test/test.dart';

/// A command that only reports which configuration file it resolved to.
class _ProbeCommand extends Commander {
  String? resolved;

  @override
  String get description => 'probe';

  @override
  String get name => 'probe';

  @override
  ArgParser get argParser => ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: 'distribution.yaml',
    );

  @override
  Future<int> run() async {
    resolved = configPath;
    return 0;
  }
}

/// A command with no `--config` of its own.
class _BareCommand extends Commander {
  String? resolved;

  @override
  String get description => 'bare';

  @override
  String get name => 'bare';

  @override
  Future<int> run() async {
    resolved = configPath;
    return 0;
  }
}

void main() {
  late CommandRunner<int> runner;
  late _ProbeCommand probe;
  late _BareCommand bare;

  setUp(() {
    runner = CommandRunner<int>('distribute', 'test')
      ..argParser.addOption('config', defaultsTo: 'distribution.yaml');
    probe = _ProbeCommand();
    bare = _BareCommand();
    runner.addCommand(probe);
    runner.addCommand(bare);
  });

  group('configPath', () {
    test('honours the global --config', () async {
      // Regression: every sub-command declares its own `--config` with a
      // default, and that default used to shadow the global option — making a
      // documented global flag silently do nothing.
      await runner.run(['--config', 'custom.yaml', 'probe']);
      expect(probe.resolved, 'custom.yaml');
    });

    test('a sub-command flag wins over the global one', () async {
      await runner
          .run(['--config', 'global.yaml', 'probe', '-c', 'local.yaml']);
      expect(probe.resolved, 'local.yaml');
    });

    test('falls back to the default when neither is given', () async {
      await runner.run(['probe']);
      expect(probe.resolved, 'distribution.yaml');
    });

    test('works for a command that declares no --config of its own', () async {
      await runner.run(['--config', 'custom.yaml', 'bare']);
      expect(bare.resolved, 'custom.yaml');
    });
  });
}
