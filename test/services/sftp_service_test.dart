import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/services/sftp_entry.dart';
import 'package:picshell/services/sftp_service.dart';

void main() {
  group('joinPath', () {
    test('joins base and child', () {
      expect(joinPath('/a', 'b'), '/a/b');
    });
    test('collapses repeated slashes', () {
      expect(joinPath('/a/', '/b/'), '/a/b');
    });
    test('child under root', () {
      expect(joinPath('/', 'b'), '/b');
    });
    test('empty base', () {
      expect(joinPath('', 'b'), 'b');
    });
    test('relative base', () {
      expect(joinPath('.', 'b'), './b');
    });
    test('handles child with no slash and base without trailing', () {
      expect(joinPath('/home/user', 'docs'), '/home/user/docs');
    });
  });

  group('parentPath', () {
    test('one level deep', () {
      expect(parentPath('/a'), '/');
    });
    test('two levels deep', () {
      expect(parentPath('/a/b'), '/a');
    });
    test('root stays root', () {
      expect(parentPath('/'), '/');
    });
    test('empty is root', () {
      expect(parentPath(''), '/');
    });
    test('trailing slash trimmed before parent', () {
      expect(parentPath('/a/b/'), '/a');
    });
    test('relative without slash is returned unchanged', () {
      // '.' has no '/', so it has no parent.
      expect(parentPath('.'), '.');
      expect(parentPath('a'), 'a');
    });
  });

  group('sftpErrorMessage', () {
    test('permission denied maps to friendly text', () {
      final e = SftpStatusError(SftpStatusCode.permissionDenied, '');
      expect(sftpErrorMessage(e), 'Permission denied');
    });
    test('no such file maps to friendly text', () {
      final e = SftpStatusError(SftpStatusCode.noSuchFile, '');
      expect(sftpErrorMessage(e), 'No such file or directory');
    });
    test('generic failure surfaces message', () {
      final e = SftpStatusError(SftpStatusCode.failure, 'Failure');
      expect(sftpErrorMessage(e), 'Failure');
    });
    test('generic failure with empty message falls back', () {
      final e = SftpStatusError(SftpStatusCode.failure, '');
      expect(sftpErrorMessage(e), 'Operation failed');
    });
    test('connection lost', () {
      final e = SftpStatusError(SftpStatusCode.connectionLost, '');
      expect(sftpErrorMessage(e), 'Connection lost');
    });
    test('plain SftpError surfaces its message', () {
      expect(sftpErrorMessage(SftpError('boom')), 'boom');
    });
    test('non-SFTP error stringifies', () {
      expect(sftpErrorMessage(Exception('x')), contains('x'));
    });
  });

  group('formatBytes', () {
    test('bytes under 1024 show as B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });
    test('1024 → KB', () {
      expect(formatBytes(1024), '1.0 KB');
    });
    test('MB threshold', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 2), '2.0 MB');
    });
    test('one decimal place for KB and up', () {
      expect(formatBytes(1536), '1.5 KB'); // 1.5 KB
    });
    test('negative falls back to raw', () {
      expect(formatBytes(-1), '-1 B');
    });
  });

  group('SftpEntry.sizeLabel', () {
    test('directory', () {
      const e = SftpEntry(name: 'x', isDirectory: true);
      expect(e.sizeLabel, 'Directory');
    });
    test('file with size', () {
      const e = SftpEntry(name: 'x', isDirectory: false, size: 2048);
      expect(e.sizeLabel, '2.0 KB');
    });
    test('file with null size', () {
      const e = SftpEntry(name: 'x', isDirectory: false);
      expect(e.sizeLabel, '');
    });
  });

  group('validateEntryName', () {
    test('accepts plain names', () {
      expect(validateEntryName('readme.txt'), isNull);
      expect(validateEntryName('my folder'), isNull);
      expect(validateEntryName('a.b.c'), isNull);
      expect(validateEntryName('  padded  '), isNull);
    });
    test('rejects empty and whitespace-only', () {
      expect(validateEntryName(''), isNotNull);
      expect(validateEntryName('   '), isNotNull);
    });
    test('rejects dot entries', () {
      expect(validateEntryName('.'), isNotNull);
      expect(validateEntryName('..'), isNotNull);
    });
    test('rejects path separators (both styles)', () {
      expect(validateEntryName('a/b'), isNotNull);
      expect(validateEntryName('../evil'), isNotNull);
      expect(validateEntryName('a\\b'), isNotNull);
      expect(validateEntryName('/abs'), isNotNull);
    });
  });

  group('awaitZoneGuardedWrite', () {
    test('completes normally when the write succeeds', () async {
      final done = Completer<void>();
      var aborted = false;
      await awaitZoneGuardedWrite(
        start: () => done.complete(),
        done: () => done.future,
        abort: () async => aborted = true,
      );
      expect(aborted, isFalse);
    });

    test('propagates an unhandled zone error instead of hanging', () async {
      // Simulates dartssh2's SftpFileWriter: `done` never completes, but a
      // failed writeBytes() escapes as an unhandled zone error.
      final done = Completer<void>();
      var aborted = false;
      await expectLater(
        awaitZoneGuardedWrite(
          start: () {
            scheduleMicrotask(() => throw StateError('write failed'));
          },
          done: () => done.future,
          abort: () async {
            aborted = true;
            if (!done.isCompleted) done.complete();
          },
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'write failed')),
      );
      expect(aborted, isTrue);
    });

    test('propagates an async error thrown from a detached future', () async {
      final done = Completer<void>();
      await expectLater(
        awaitZoneGuardedWrite(
          start: () {
            // Un-awaited future error → unhandled error in the guarded zone.
            Future<void>.delayed(
              const Duration(milliseconds: 10),
            ).then((_) => throw ArgumentError('lost connection'));
          },
          done: () => done.future,
          abort: () async => done.complete(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rethrows even if abort itself fails', () async {
      await expectLater(
        awaitZoneGuardedWrite(
          start: () => scheduleMicrotask(() => throw StateError('boom')),
          done: () => Completer<void>().future,
          abort: () async => throw StateError('already closed'),
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom')),
      );
    });
  });
}
