import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'sftp_entry.dart';

/// Resolves platform-specific local directories. Pluggable so the path logic
/// can be unit-tested without a real platform environment.
typedef DirectoryResolver = Future<String> Function();

/// Default resolver: the user's Downloads dir on desktop, the app documents
/// dir on mobile (where a Downloads folder may not be writable).
Future<String> defaultDownloadDir() async {
  if (isMobilePlatform) {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
  // Desktop (macOS/Linux/Windows): prefer Downloads, fall back to Documents.
  final downloads = await getDownloadsDirectory();
  if (downloads != null) return downloads.path;
  final docs = await getApplicationDocumentsDirectory();
  return docs.path;
}

/// Picks a local source file for upload. Returns null if the user cancels.
Future<String?> pickUploadSource() async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: false);
  final path = result?.files.first.path;
  return path;
}

/// Picks/computes the local destination for a download given a suggested
/// [fileName]. Desktop prompts via saveFile; mobile writes into the download
/// directory with that name.
Future<String?> pickDownloadTarget(String fileName) async {
  if (isMobilePlatform) {
    // saveFile support is unreliable on iOS/Android; write directly into the
    // app-visible download/docs directory.
    final dir = await defaultDownloadDir();
    return joinLocalPath(dir, fileName);
  }
  // Desktop: let the user choose location and rename.
  final chosen = await FilePicker.platform.saveFile(fileName: fileName);
  return chosen;
}

/// Joins a local directory path with a filename using the platform separator.
/// Pure top-level function so join logic is unit-testable.
String joinLocalPath(String dir, String name) {
  if (dir.endsWith(Platform.pathSeparator)) return '$dir$name';
  return '$dir${Platform.pathSeparator}$name';
}

/// High-level local-filesystem helper. The download-dir resolution is
/// overridable so tests can inject a temp directory without touching the
/// platform plugins.
class LocalFileService {
  final DirectoryResolver _downloadDirResolver;

  LocalFileService({DirectoryResolver? downloadDirResolver})
      : _downloadDirResolver = downloadDirResolver ?? defaultDownloadDir;

  Future<String> downloadDir() => _downloadDirResolver();
  Future<String?> pickUpload() => pickUploadSource();

  /// Resolves the mobile download target using this service's resolver
  /// (testable); desktop still goes through the saveFile picker.
  Future<String?> pickDownload(String fileName) async {
    if (isMobilePlatform) {
      final dir = await _downloadDirResolver();
      return joinLocalPath(dir, fileName);
    }
    return FilePicker.platform.saveFile(fileName: fileName);
  }
}
