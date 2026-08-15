import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/local_file_service.dart';
import 'dart:io' show Platform;

void main() {
  group('joinLocalPath', () {
    test('adds separator when dir has none', () {
      final sep = Platform.pathSeparator;
      expect(joinLocalPath('/tmp', 'file.txt'), '/tmp${sep}file.txt');
    });
    test('no double separator when dir already ends with one', () {
      final sep = Platform.pathSeparator;
      expect(joinLocalPath('/tmp$sep', 'file.txt'), '/tmp${sep}file.txt');
    });
    test('empty filename yields trailing separator', () {
      final sep = Platform.pathSeparator;
      expect(joinLocalPath('/tmp', ''), '/tmp$sep');
    });
  });

  group('LocalFileService.downloadDir', () {
    test('uses the injected resolver', () async {
      final svc = LocalFileService(downloadDirResolver: () async => '/fake');
      expect(await svc.downloadDir(), '/fake');
    });
    test('default resolver is wired when none provided', () {
      // Just verify construction doesn't throw; the real resolver runs only
      // when called (and touches platform plugins), so we don't invoke it.
      expect(LocalFileService(), isNotNull);
    });
  });
}
