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

/// Returns the parent directory of [path], or '/' at the root.
/// Pure top-level function for testability.
///
/// Examples: parentPath('/a/b') → '/a'; parentPath('/a') → '/';
/// parentPath('/') → '/'; parentPath('.') → '.'.
String parentPath(String path) {
  if (path == '/' || path.isEmpty) return '/';
  final trimmed = _trimTrailingSlash(path);
  final lastSlash = trimmed.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
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

String _trimSlashes(String s) => s.replaceAll(RegExp(r'^/+|/$'), '');
String _trimTrailingSlash(String s) => s.endsWith('/') && s.length > 1
    ? s.substring(0, s.length - 1)
    : s;

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

  /// Returns a usable SftpClient, opening one if needed and reopening if the
  /// underlying SSH client has been replaced since last use.
  Future<SftpClient> _client() async {
    final sshClient = _ssh.client;
    if (sshClient == null) {
      throw SftpError('SSH session is not connected');
    }
    if (_sftp == null || _sftpOwner != sshClient) {
      _sftp?.close();
      _sftp = await sshClient.sftp();
      _sftpOwner = sshClient;
    }
    return _sftp!;
  }

  /// Lists [path], returning UI-friendly [SftpEntry]s sorted directories-first.
  Future<List<SftpEntry>> listdir(String path) async {
    final sftp = await _client();
    final names = await sftp.listdir(path);
    final entries = names
        .where((n) => n.filename != '.' && n.filename != '..')
        .map((n) => SftpEntry(
              name: n.filename,
              isDirectory: n.attr.isDirectory,
              size: n.attr.size,
              modifyTime: n.attr.modifyTime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      n.attr.modifyTime! * 1000,
                    ),
            ))
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
    } finally {
      await sink.close();
      await file.close();
    }
  }

  /// Uploads [localPath] to [remotePath], streaming with a progress callback.
  Future<void> upload(
    String localPath,
    String remotePath, {
    void Function(int total)? onProgress,
  }) async {
    final sftp = await _client();
    final localFile = File(localPath);
    final size = await localFile.length();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      // Stream the local file in 16KB chunks and translate to byte-progress.
      const chunkSize = 16 * 1024;
      var sent = 0;
      final controller = StreamController<Uint8List>();
      final writer = file.write(controller.stream, onProgress: (acked) {
        // dartssh2 reports acknowledged bytes; report the min of acked/sent
        // so we never show >100% during the final flush.
        onProgress?.call(acked < sent ? acked : sent);
      });
      await for (final chunk in localFile.openRead(chunkSize, chunkSize)) {
        controller.add(Uint8List.fromList(chunk));
        sent += chunk.length;
      }
      await controller.close();
      await writer;
      onProgress?.call(size);
    } finally {
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
