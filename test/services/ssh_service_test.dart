import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/ssh_service.dart';

void main() {
  group('SshService', () {
    test('connection config can be created', () {
      final config = SshConnectionConfig(
        host: '192.168.1.1',
        username: 'root',
        authMethod: SshAuthMethod.password,
        password: 'test',
      );
      expect(config.host, '192.168.1.1');
      expect(config.port, 22);
      expect(config.authMethod, SshAuthMethod.password);
    });

    test('SshService initial state', () {
      final service = SshService();
      expect(service.isConnected, false);
    });
  });
}
