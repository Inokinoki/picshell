import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/forward_rule.dart';
import 'package:picshell/services/ssh_config_parser.dart';

void main() {
  group('SshConfigParser', () {
    test('parses a basic host block', () {
      const text = '''
Host my-server
  HostName 10.0.0.1
  Port 2222
  User admin
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.length, 1);
      expect(hosts.first.primaryAlias, 'my-server');
      expect(hosts.first.hostName, '10.0.0.1');
      expect(hosts.first.port, 2222);
      expect(hosts.first.user, 'admin');
    });

    test('drops wildcard host blocks', () {
      const text = '''
Host *
  User root
Host real-host
  HostName example.com
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.length, 1);
      expect(hosts.first.primaryAlias, 'real-host');
    });

    test('ignores comments and blank lines', () {
      const text = '''
# leading comment

Host h1
  HostName a.com
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.length, 1);
      expect(hosts.first.hostName, 'a.com');
    });

    test('strips inline comments', () {
      const text = '''
Host h1
  HostName a.com   # this is the prod box
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.hostName, 'a.com');
    });

    test('parses LocalForward colon form', () {
      const text = '''
Host db
  HostName db.internal
  LocalForward 8080 localhost:5432
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.forwards.length, 1);
      final f = hosts.first.forwards.first;
      expect(f.type, ForwardType.local);
      expect(f.localPort, 8080);
      expect(f.remoteHost, 'localhost');
      expect(f.remotePort, 5432);
    });

    test('parses LocalForward space form', () {
      const text = '''
Host db
  LocalForward 8080 db 5432
''';
      final hosts = SshConfigParser.parse(text);
      final f = hosts.first.forwards.first;
      expect(f.remoteHost, 'db');
      expect(f.remotePort, 5432);
    });

    test('parses RemoteForward and DynamicForward', () {
      const text = '''
Host h
  RemoteForward 9000 localhost:22
  DynamicForward 1080
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.forwards.length, 2);
      expect(hosts.first.forwards[0].type, ForwardType.remote);
      expect(hosts.first.forwards[1].type, ForwardType.socks);
      expect(hosts.first.forwards[1].localPort, 1080);
    });

    test('parses RemoteForward bind-address one-arg form', () {
      const text = '''
Host h
  RemoteForward 0.0.0.0:8080:intranet.example:443
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.forwards.length, 1);
      final f = hosts.first.forwards.first;
      expect(f.type, ForwardType.remote);
      expect(f.localHost, '0.0.0.0');
      expect(f.localPort, 8080);
      expect(f.remoteHost, 'intranet.example');
      expect(f.remotePort, 443);
    });

    test('parses RemoteForward bind-address multi-arg form', () {
      const text = '''
Host h
  RemoteForward localhost 8080 intranet.example 443
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.forwards.length, 1);
      final f = hosts.first.forwards.first;
      expect(f.type, ForwardType.remote);
      expect(f.localHost, 'localhost');
      expect(f.localPort, 8080);
      expect(f.remoteHost, 'intranet.example');
      expect(f.remotePort, 443);
    });

    test('parses LocalForward bind-address one-arg form', () {
      const text = '''
Host h
  LocalForward 0.0.0.0:8080:db:5432
''';
      final hosts = SshConfigParser.parse(text);
      final f = hosts.first.forwards.single;
      expect(f.localHost, '0.0.0.0');
      expect(f.localPort, 8080);
      expect(f.remoteHost, 'db');
      expect(f.remotePort, 5432);
    });

    test('skips listen-only RemoteForward', () {
      const text = '''
Host h
  RemoteForward 8080
  RemoteForward 0.0.0.0:9090
  RemoteForward 19999
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.forwards, isEmpty);
    });

    test('parses ProxyJump and IdentityFile', () {
      const text = '''
Host target
  HostName internal.example.com
  ProxyJump jump-host
  IdentityFile ~/.ssh/id_ed25519
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.proxyJump, 'jump-host');
      expect(hosts.first.identityFilePath, '~/.ssh/id_ed25519');
    });

    test('imported forwards default to manual start', () {
      const text = '''
Host h
  LocalForward 8080 db:5432
''';
      expect(
        SshConfigParser.parse(text).first.forwards.first.autoStart,
        false,
      );
    });

    test('keywords are case-insensitive', () {
      const text = '''
Host h
  hostname a.com
  PORT 2222
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.first.hostName, 'a.com');
      expect(hosts.first.port, 2222);
    });

    test('returns empty for blank input', () {
      expect(SshConfigParser.parse(''), isEmpty);
      expect(SshConfigParser.parse('   \n  \n# only comments\n'), isEmpty);
    });

    test('handles multiple aliases on Host line', () {
      const text = '''
Host prod prod-1 prod-2
  HostName prod.example.com
''';
      final hosts = SshConfigParser.parse(text);
      expect(hosts.length, 1);
      expect(hosts.first.aliases, ['prod', 'prod-1', 'prod-2']);
      expect(hosts.first.primaryAlias, 'prod');
    });
  });
}
