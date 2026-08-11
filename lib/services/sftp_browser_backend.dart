import 'sftp_entry.dart';

/// Abstraction over the SFTP operations a browser screen needs. Decouples
/// the UI from dartssh2 so the screen can be widget-tested with a fake.
///
/// The production implementation is [SftpService]. Progress callbacks receive
/// a byte count (read for download, total-acked for upload).
abstract class SftpBrowserBackend {
  Future<List<SftpEntry>> listdir(String path);
  Future<String> absolute(String path);
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int bytesRead)? onProgress,
  });
  Future<void> upload(
    String localPath,
    String remotePath, {
    void Function(int total)? onProgress,
  });
  Future<void> mkdir(String path);
  Future<void> rmdir(String path);
  Future<void> remove(String path);
  Future<void> rename(String oldPath, String newPath);
}
