import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/models/floating_image.dart';
import 'package:picshell/providers/floating_image_provider.dart';

void main() {
  group('FloatingImagesNotifier count limit (maxImages)', () {
    test('evicts oldest non-minimized beyond maxImages', () {
      final container = ProviderContainer();
      final notifier = container.read(floatingImagesProvider.notifier);

      for (int i = 0; i < maxImages + 1; i++) {
        notifier.addImage(FloatingImage(
          id: 'img-$i',
          rawBytes: Uint8List(10),
          name: 'a$i.png',
        ));
      }

      final images = container.read(floatingImagesProvider);
      expect(images.length, maxImages);
      // The very first (oldest) image should be gone.
      expect(images.any((img) => img.id == 'img-0'), isFalse);
      // The newest should still be there.
      expect(images.any((img) => img.id == 'img-$maxImages'), isTrue);

      container.dispose();
    });

    test('keeps minimized images even when count limit reached', () {
      final container = ProviderContainer();
      final notifier = container.read(floatingImagesProvider.notifier);

      // Fill with minimized images.
      for (int i = 0; i < maxImages; i++) {
        notifier.addImage(FloatingImage(
          id: 'img-$i',
          rawBytes: Uint8List(10),
          name: 'm$i.png',
        ));
        notifier.toggleMinimize('img-$i');
      }
      // Now add one more — only this one is non-minimized, so it gets evicted.
      notifier.addImage(FloatingImage(
        id: 'extra',
        rawBytes: Uint8List(10),
        name: 'extra.png',
      ));

      final images = container.read(floatingImagesProvider);
      expect(images.length, maxImages);
      // All minimized survive.
      expect(images.every((img) => img.minimized), isTrue);
      // The extra non-minimized one was evicted.
      expect(images.any((img) => img.id == 'extra'), isFalse);

      container.dispose();
    });
  });

  group('FloatingImagesNotifier byte limit (maxTotalBytes)', () {
    test('evicts oldest when total bytes exceeds cap', () {
      final container = ProviderContainer();
      final notifier = container.read(floatingImagesProvider.notifier);

      // Each image is ~1/3 of the cap, so three of them cross the limit.
      final big = Uint8List(maxTotalBytes ~/ 2 + 1);
      notifier.addImage(FloatingImage(
        id: 'big-1', rawBytes: big, name: 'b1.png',
      ));
      notifier.addImage(FloatingImage(
        id: 'big-2', rawBytes: big, name: 'b2.png',
      ));

      final images = container.read(floatingImagesProvider);
      // Two halves each > 50% => only the newest survives.
      expect(images.length, 1);
      expect(images.first.id, 'big-2');

      container.dispose();
    });
  });
}
