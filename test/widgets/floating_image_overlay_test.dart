import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/floating_image.dart';
import 'package:picshell/providers/floating_image_provider.dart';
import 'package:picshell/widgets/floating_image_overlay.dart';
import 'package:picshell/widgets/floating_image_widget.dart';

void main() {
  group('FloatingImageOverlay', () {
    late Uint8List testPngBytes;

    setUpAll(() {
      testPngBytes = _createMinimalPng();
    });

    testWidgets('shows no floating widget when provider is empty',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FloatingImageWidget), findsNothing);
      expect(find.text('terminal'), findsOneWidget);
    });

    testWidgets('shows floating widget when image is added', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      container.read(floatingImagesProvider.notifier).addImage(
            FloatingImage(
              id: 'test-1',
              rawBytes: testPngBytes,
              name: 'test.png',
            ),
          );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingImageWidget), findsOneWidget);
      expect(find.text('test.png'), findsOneWidget);

      container.dispose();
    });

    testWidgets('hides floating widget when minimized', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      final notifier = container.read(floatingImagesProvider.notifier);
      notifier.addImage(
        FloatingImage(
          id: 'test-1',
          rawBytes: testPngBytes,
          name: 'test.png',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(FloatingImageWidget), findsOneWidget);

      notifier.toggleMinimize('test-1');
      await tester.pump();

      expect(find.byType(FloatingImageWidget), findsNothing);

      container.dispose();
    });

    testWidgets('removes floating widget when image is removed',
        (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      final notifier = container.read(floatingImagesProvider.notifier);
      notifier.addImage(
        FloatingImage(
          id: 'test-1',
          rawBytes: testPngBytes,
          name: 'test.png',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(FloatingImageWidget), findsOneWidget);

      notifier.removeImage('test-1');
      await tester.pump();

      expect(find.byType(FloatingImageWidget), findsNothing);

      container.dispose();
    });

    testWidgets('shows multiple floating widgets', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      final notifier = container.read(floatingImagesProvider.notifier);
      notifier.addImage(
        FloatingImage(
          id: 'test-1',
          rawBytes: testPngBytes,
          name: 'image1.png',
        ),
      );
      notifier.addImage(
        FloatingImage(
          id: 'test-2',
          rawBytes: testPngBytes,
          name: 'image2.png',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingImageWidget), findsNWidgets(2));
      expect(find.text('image1.png'), findsOneWidget);
      expect(find.text('image2.png'), findsOneWidget);

      container.dispose();
    });

    testWidgets('minimize button triggers toggleMinimize', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      final notifier = container.read(floatingImagesProvider.notifier);
      notifier.addImage(
        FloatingImage(
          id: 'test-1',
          rawBytes: testPngBytes,
          name: 'test.png',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingImageWidget), findsOneWidget);

      await tester.tap(find.byIcon(Icons.minimize));
      await tester.pump();

      expect(find.byType(FloatingImageWidget), findsNothing);

      container.dispose();
    });

    testWidgets('close button removes image', (tester) async {
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FloatingImageOverlay(
              child: const Scaffold(
                body: Center(child: Text('terminal')),
              ),
            ),
          ),
        ),
      );

      final notifier = container.read(floatingImagesProvider.notifier);
      notifier.addImage(
        FloatingImage(
          id: 'test-1',
          rawBytes: testPngBytes,
          name: 'test.png',
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.byType(FloatingImageWidget), findsNothing);
      expect(container.read(floatingImagesProvider), isEmpty);

      container.dispose();
    });
  });
}

Uint8List _createMinimalPng() {
  final signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final ihdr = _createChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]);
  final idatData = [0, 255, 0, 0];
  final compressed = _zlibCompress(idatData);
  final idat = _createChunk('IDAT', compressed);
  final iend = _createChunk('IEND', []);
  return Uint8List.fromList([...signature, ...ihdr, ...idat, ...iend]);
}

List<int> _createChunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = data.length;
  final crcData = [...typeBytes, ...data];
  final crc = _crc32(crcData);
  return [
    (length >> 24) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...typeBytes,
    ...data,
    (crc >> 24) & 0xFF,
    (crc >> 16) & 0xFF,
    (crc >> 8) & 0xFF,
    crc & 0xFF,
  ];
}

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      if (crc & 1 != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _zlibCompress(List<int> data) {
  return [
    0x78, 0x01, 0x01, 0x04, 0x00, 0xFB, 0xFF,
    ...data,
    0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x01, 0x00, 0x01,
  ];
}
