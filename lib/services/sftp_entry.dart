import 'dart:io' show Platform;

/// UI-facing, immutable view of one SFTP directory entry. Decouples the
/// browser from dartssh2's `SftpName` so the UI layer never imports the SSH
/// package directly.
class SftpEntry {
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modifyTime;

  const SftpEntry({
    required this.name,
    required this.isDirectory,
    this.size,
    this.modifyTime,
  });

  /// Human-readable size for subtitle display: "" / "Directory" / "1.2 KB"...
  String get sizeLabel {
    if (isDirectory) return 'Directory';
    final s = size;
    if (s == null) return '';
    return formatBytes(s);
  }
}

/// Formats a byte count into a compact human-readable string.
///
/// Pure top-level function so it can be unit-tested in isolation. Uses binary
/// units (1024), matching the convention of `ls -lh` and most file managers.
String formatBytes(int bytes) {
  if (bytes < 0) return '$bytes B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  // Whole bytes show no decimals; larger units get one decimal place.
  return unit == 0
      ? '${size.toInt()} ${units[unit]}'
      : '${size.toStringAsFixed(1)} ${units[unit]}';
}

/// Returns true when the current platform is mobile (Android/iOS), where the
/// downloads directory differs from desktop. Top-level for testability.
bool get isMobilePlatform =>
    Platform.isAndroid || Platform.isIOS;
