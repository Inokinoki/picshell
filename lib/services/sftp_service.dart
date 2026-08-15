import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'sftp_browser_backend.dart';
import 'sftp_entry.dart';
import 'ssh_service.dart';

/// Joins two SFTP path segments, normalising repeated/trailing slashes.
/// Pure top-level function so path logic is unit-testable without an SFTP
/// connection.
///
/// Examples: joinPath('/a', 'b') → '/a/b'; joinPath('/a/', '/b/') → '/a/b';
/// joinPath('/', 'b') → '/b'; joinPath('.', 'b') → './b'.
String joinPath(String base, String child) {
  if (base.isEmpty) return _trimSlashes(child);
  if (base == '/') return '/${_trimSlashes(child)}';
  return '${_trimTrailingSlash(base)}/${_trimSlashes(child)}';
}

/// Returns the parent directory of [path], or '/' at the root. A relative
/// path with no '/' has no parent, so it is returned unchanged.
/// Pure top-level function for testability.
///
/// Examples: parentPath('/a/b') → '/a'; parentPath('/a') → '/';
/// parentPath('/') → '/'; parentPath('.') → '.'; parentPath('a') → 'a'.
String parentPath(String path) {
  if (path == '/' || path.isEmpty) return '/';
  final trimmed = _trimTrailingSlash(path);
  final lastSlash = trimmed.lastIndexOf('/');
  if (lastSlash < 0) return trimmed;
  if (lastSlash == 0) return '/';
  return trimmed.substring(0, lastSlash);
}

/// Maps an SFTP/IO error to a short user-facing message. Pure top-level
/// function so the mapping is testable without a live connection.
String sftpErrorMessage(Object e) {
  if (e is SftpStatusError) {
    switch (e.code) {
      case SftpStatusCode.permissionDenied:
        return 'Permission denied';
      case SftpStatusCode.noSuchFile:
        return 'No such file or directory';
      case SftpStatusCode.failure:
        // Generic failure often hides "directory not empty" on rmdir.
        return e.message.isEmpty ? 'Operation failed' : e.message;
      case SftpStatusCode.connectionLost:
      case SftpStatusCode.noConnection:
        return 'Connection lost';
      default:
        return e.message.isEmpty ? 'SFTP error (${e.code})' : e.message;
    }
  }
  if (e is SftpError) return e.message.isEmpty ? 'SFTP error' : e.message;
  return e.toString();
}

/// Validates a user-supplied file/folder name before it is joined into a
/// remote path. Returns null when the name is safe, or a short user-facing
/// error message describing why it was rejected. Pure top-level function for
/// testability.
String? validateEntryName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Name cannot be empty';
  if (trimmed == '.' || trimmed == '..') {
    return '"$trimmed" is not a valid name';
  }
  if (trimmed.contains('/') || trimmed.contains('\\')) {
    return 'Name cannot contain "/" or "\\"';
  }
  return null;
}

String _trimSlashes(String s) => s.replaceAll(RegExp(r'^/+|/$'), '');
String _trimTrailingSlash(String s) =>
    s.endsWith('/') && s.length > 1 ? s.substring(0, s.length - 1) : s;

/// Awaits a streaming write whose failures surface only as unhandled zone
/// errors. dartssh2 2.14.0's `SftpFileWriter` completes its `done` completer
/// only on success or explicit `abort()`: a failed `writeBytes()` (connection
/// lost, permission/quota) or an error in the source stream escapes as an
/// unhandled zone error and `done` never completes, so a plain
/// `await writer.done` would hang forever.
///
/// [start] is invoked inside `runZonedGuarded`, so any such unhandled error
/// is captured into an error completer instead of leaking to the root zone.
/// The write is then awaited as a race between [done] and the captured error.
/// On error, [abort] is called (which stops the source stream and completes
/// [done], letting the await unwind) and the original error is rethrown with
/// its stack trace so callers can handle it as a normal exception.
///
/// Pure plumbing (no dartssh2 types), so it is unit-testable without an SFTP
/// connection — see test/services/sftp_service_test.dart.
Future<void> awaitZoneGuardedWrite({
  required void Function() start,
  required Future<void> Function() done,
  required Future<void> Function() abort,
}) async {
  final errors = Completer<void>();
  runZonedGuarded(start, (e, st) {
    if (!errors.isCompleted) errors.completeError(e, st);
  });
  try {
    await Future.any([done(), errors.future]);
  } catch (e, st) {
    try {
      await abort();
    } catch (_) {
      // The writer may already be torn down; the original error matters.
    }
    Error.throwWithStackTrace(e, st);
  }
}

/// Wraps an [SshService] to provide SFTP file operations. Lazily opens an
/// SFTP subsystem on first use and transparently reopens it after the SSH
/// client is replaced (e.g. on reconnect).
class SftpService implements SftpBrowserBackend {
  final SshService _ssh;
  SftpClient? _sftp;
  // The SSH client identity the cached _sftp was opened on. If it changes
  // (reconnect swaps the client), we discard _sftp and reopen.
  SSHClient? _sftpOwner;

  SftpService(this._ssh);

  // Memoised in-flight open so concurrent callers during (re)connect share a
  // single SFTP subsystem instead of each opening (and leaking) one.
  Future<SftpClient>? _opening;

  /// Returns a usable SftpClient, opening one if needed and reopening if the
  /// underlying SSH client has been replaced since last use.
  Future<SftpClient> _client() {
    final sshClient = _ssh.client;
    if (sshClient == null) {
      throw SftpError('SSH session is not connected');
    }
    if (_sftp != null && _sftpOwner == sshClient) {
      return Future.value(_sftp);
    }
    return _opening ??= () {
      // The cached client belongs to a replaced SSH client; close it before
      // opening a fresh subsystem on the current one.
      _sftp?.close();
      _sftp = null;
      _sftpOwner = null;
      return sshClient
          .sftp()
          .then((client) {
            _sftp = client;
            _sftpOwner = sshClient;
            return client;
          })
          .whenComplete(() {
            _opening = null;
          });
    }();
  }

  /// Lists [path], returning UI-friendly [SftpEntry]s sorted directories-first.
  Future<List<SftpEntry>> listdir(String path) async {
    final sftp = await _client();
    final names = await sftp.listdir(path);
    final entries = names
        .where((n) => n.filename != '.' && n.filename != '..')
        .map(
          (n) => SftpEntry(
            name: n.filename,
            isDirectory: n.attr.isDirectory,
            size: n.attr.size,
            modifyTime: n.attr.modifyTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    n.attr.modifyTime! * 1000,
                  ),
          ),
        )
        .toList();
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// Canonicalises [path] to an absolute form via the SFTP realpath op.
  Future<String> absolute(String path) async {
    final sftp = await _client();
    return sftp.absolute(path);
  }

  /// Downloads [remotePath] to [localPath], streaming with a progress callback.
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int bytesRead)? onProgress,
  }) async {
    final sftp = await _client();
    final file = await sftp.open(remotePath);
    final sink = File(localPath).openWrite();
    try {
      await for (final chunk in file.read(onProgress: onProgress)) {
        sink.add(chunk);
      }
      await sink.flush();
    } catch (_) {
      // Don't leave a truncated file that looks like a successful download.
      try {
        await sink.close();
      } finally {
        try {
          await File(localPath).delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await sink.close();
      await file.close();
    }
  }

  /// Returns whether [path] exists on the remote, without throwing on
  /// "no such file".
  Future<bool> exists(String path) async {
    final sftp = await _client();
    try {
      await sftp.stat(path);
      return true;
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return false;
      rethrow;
    }
  }

  /// Uploads [localPath] to [remotePath], streaming with progress callbacks.
  /// [onStart] fires once with the total byte count before the first chunk,
  /// so callers can show a determinate progress bar.
  Future<void> upload(
    String localPath,
    String remotePath, {
    void Function(int total)? onProgress,
    void Function(int total)? onStart,
  }) async {
    final sftp = await _client();
    final localFile = File(localPath);
    final size = await localFile.length();
    final file = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      // Pipe the local file stream straight into the SFTP writer so reads
      // respect the writer's pace (real backpressure) instead of buffering
      // the whole file in a StreamController queue. The map() tracks how
      // many bytes have been handed to the writer so progress can be
      // reported as min(acked, sent) — never >100% during the final flush.
      var sent = 0;
      final stream = localFile.openRead().cast<Uint8List>().map((chunk) {
        sent += chunk.length;
        return chunk;
      });
      onStart?.call(size);
      // SftpFile.write() starts piping immediately and returns the writer.
      // dartssh2's writer only completes its `done` future on success or
      // abort(); mid-upload errors escape as unhandled zone errors, so the
      // write is awaited through awaitZoneGuardedWrite (see its doc) which
      // bridges such errors into a normal exception and aborts the writer.
      late final SftpFileWriter writer;
      await awaitZoneGuardedWrite(
        start: () {
          writer = file.write(
            stream,
            onProgress: (acked) {
              onProgress?.call(acked < sent ? acked : sent);
            },
          );
        },
        done: () => writer.done,
        abort: () => writer.abort(),
      );
      onProgress?.call(size);
    } finally {
      // SftpFile.close() is idempotent, so this is safe after an abort.
      await file.close();
    }
  }

  Future<void> mkdir(String path) async => (await _client()).mkdir(path);
  Future<void> rmdir(String path) async => (await _client()).rmdir(path);
  Future<void> remove(String path) async => (await _client()).remove(path);
  Future<void> rename(String oldPath, String newPath) async =>
      (await _client()).rename(oldPath, newPath);

  /// Closes the SFTP subsystem. Does NOT close the underlying SSH session.
  Future<void> close() async {
    _sftp?.close();
    _sftp = null;
    _sftpOwner = null;
  }
}
