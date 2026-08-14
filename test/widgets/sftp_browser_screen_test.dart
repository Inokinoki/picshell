import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/screens/sftp/sftp_browser_screen.dart';
import 'package:picshell/services/local_file_service.dart';
import 'package:picshell/services/sftp_browser_backend.dart';
import 'package:picshell/services/sftp_entry.dart';

/// Fake backend with a tiny in-memory filesystem. Records every call so tests
/// can assert on them.
class _FakeBackend implements SftpBrowserBackend {
  // path → entry list (directories recorded separately for isDirectory truth)
  final Map<String, List<SftpEntry>> _dirs = {};
  final List<String> calls = [];
  String nextAbsolute = '/home/user';
  // Set of remote paths reported as existing by exists(); upload uses this
  // to decide whether to ask for overwrite confirmation.
  final Set<String> existingPaths = {};
  bool failAbsolute = false;

  _FakeBackend() {
    _dirs['/home/user'] = [
      const SftpEntry(name: 'docs', isDirectory: true),
      const SftpEntry(name: 'readme.txt', isDirectory: false, size: 1024),
    ];
    _dirs['/home/user/docs'] = [];
  }

  @override
  Future<List<SftpEntry>> listdir(String path) async {
    calls.add('listdir:$path');
    return List.unmodifiable(_dirs[path] ?? []);
  }

  @override
  Future<String> absolute(String path) async {
    calls.add('absolute:$path');
    if (failAbsolute) throw Exception('backend init failed');
    return nextAbsolute;
  }

  @override
  Future<bool> exists(String path) async {
    calls.add('exists:$path');
    return existingPaths.contains(path);
  }

  @override
  Future<void> download(remotePath, localPath, {onProgress}) async {
    calls.add('download:$remotePath->$localPath');
  }

  @override
  Future<void> upload(localPath, remotePath, {onProgress}) async {
    calls.add('upload:$localPath->$remotePath');
    // Reflect into the dir so a refresh shows it.
    final dir = remotePath.substring(0, remotePath.lastIndexOf('/'));
    (_dirs.putIfAbsent(
      dir,
      () => [],
    )).add(SftpEntry(name: remotePath.split('/').last, isDirectory: false));
  }

  @override
  Future<void> mkdir(String path) async {
    calls.add('mkdir:$path');
    final dir = path.substring(0, path.lastIndexOf('/'));
    (_dirs.putIfAbsent(
      dir,
      () => [],
    )).add(SftpEntry(name: path.split('/').last, isDirectory: true));
    _dirs[path] = [];
  }

  @override
  Future<void> rmdir(String path) async {
    calls.add('rmdir:$path');
    final dir = path.substring(0, path.lastIndexOf('/'));
    _dirs[dir]?.removeWhere((e) => e.name == path.split('/').last);
  }

  @override
  Future<void> remove(String path) async {
    calls.add('remove:$path');
    final dir = path.substring(0, path.lastIndexOf('/'));
    _dirs[dir]?.removeWhere((e) => e.name == path.split('/').last);
  }

  @override
  Future<void> rename(oldPath, newPath) async {
    calls.add('rename:$oldPath->$newPath');
  }

  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class _FakeLocalFiles extends LocalFileService {
  String? uploadSource;
  String? downloadTarget;
  _FakeLocalFiles({this.uploadSource, this.downloadTarget})
    : super(downloadDirResolver: () async => '/fake');

  @override
  Future<String?> pickUpload() async => uploadSource;
  @override
  Future<String?> pickDownload(String fileName) async => downloadTarget;
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('renders entries after load', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('docs'), findsOneWidget);
    expect(find.text('readme.txt'), findsOneWidget);
    // absolute('.') was called to normalise the start path.
    expect(backend.calls, contains('absolute:.'));
  });

  testWidgets('tapping a directory navigates into it', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();

    // Now listing the child dir; the empty-state should show.
    expect(find.text('Empty folder'), findsOneWidget);
    expect(backend.calls, contains('listdir:/home/user/docs'));
  });

  testWidgets('up button returns to parent', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('docs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Up'));
    await tester.pumpAndSettle();

    // Back to root listing showing both entries.
    expect(find.text('readme.txt'), findsOneWidget);
  });

  testWidgets('tapping a file triggers download', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(downloadTarget: '/fake/readme.txt'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('readme.txt'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      contains('download:/home/user/readme.txt->/fake/readme.txt'),
    );
  });

  testWidgets('delete on a file calls remove', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open readme.txt's popup menu (second row) and pick Delete.
    await tester.tap(find.byIcon(Icons.more_vert).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    // Confirm dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(backend.calls, anyElement(contains('remove:')));
  });

  testWidgets('rename calls backend with new path', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // readme.txt is the second row; its more_vert is the second one.
    await tester.tap(find.byIcon(Icons.more_vert).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'renamed.txt');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      contains('rename:/home/user/readme.txt->/home/user/renamed.txt'),
    );
  });

  testWidgets('new folder dialog calls mkdir', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New Folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'newdir');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('mkdir:/home/user/newdir'));
  });

  testWidgets('new folder rejects names with path separators', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New Folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '../evil');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    // Rejected with a friendly message, and mkdir was never called.
    expect(find.textContaining('Name cannot contain'), findsOneWidget);
    expect(backend.calls.any((c) => c.startsWith('mkdir:')), isFalse);
  });

  testWidgets('rename rejects traversal names', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '..');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a valid name'), findsOneWidget);
    expect(backend.calls.any((c) => c.startsWith('rename:')), isFalse);
  });

  testWidgets('upload over an existing file asks for confirmation', (
    tester,
  ) async {
    final backend = _FakeBackend();
    backend.existingPaths.add('/home/user/readme.txt');
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(uploadSource: '/fake/readme.txt'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Upload Here'));
    await tester.pumpAndSettle();

    // Confirmation dialog shown (title + confirm button); cancelling must
    // not upload.
    expect(find.text('Overwrite'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(backend.calls.any((c) => c.startsWith('upload:')), isFalse);

    // Confirming uploads.
    await tester.tap(find.byTooltip('Upload Here'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Overwrite'));
    await tester.pumpAndSettle();
    expect(
      backend.calls,
      contains('upload:/fake/readme.txt->/home/user/readme.txt'),
    );
  });

  testWidgets('upload of a new file skips confirmation', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(uploadSource: '/fake/other.bin'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Upload Here'));
    await tester.pumpAndSettle();

    expect(find.text('Overwrite'), findsNothing);
    expect(
      backend.calls,
      contains('upload:/fake/other.bin->/home/user/other.bin'),
    );
  });

  testWidgets('action buttons are disabled when backend init fails', (
    tester,
  ) async {
    final backend = _FakeBackend()..failAbsolute = true;
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Error state shown, and both actions are disabled (onPressed == null).
    expect(find.textContaining('backend init failed'), findsOneWidget);
    IconButton buttonFor(String tooltip) => tester.widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip),
    );
    expect(buttonFor('New Folder').onPressed, isNull);
    expect(buttonFor('Upload Here').onPressed, isNull);
  });

  testWidgets('screen closes its backend on dispose', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(
      _wrap(
        SftpBrowserScreen(
          sessionId: 's1',
          backend: backend,
          localFiles: _FakeLocalFiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(backend.closeCount, 1);
  });
}
