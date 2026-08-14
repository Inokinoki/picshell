import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// Minimal PNG encoder for RGBA buffers produced by the graphics decoders
/// (Sixel, raw Kitty). Self-contained (no image library) — builds PNG chunks
/// by hand and compresses IDAT with [ZLibEncoder] (zlib/DEFLATE + Adler-32,
/// exactly what PNG requires).
///
/// Uses `dart:io`, so this file (and thus Sixel/raw-pixel decoding) is
/// native-only. picshell targets desktop/mobile and does not build for web;
/// the iTerm2/Kitty PNG paths above don't touch this encoder.

/// Encodes an RGBA8888 [rgba] buffer ([width] × [height]) to PNG bytes.
/// Pixels with alpha 0 are preserved as-is (transparent).
Uint8List pngEncode(Uint8List rgba, int width, int height) {
  final stride = 1 + width * 4;
  // Each scanline is prefixed with a filter-type byte (0 = None).
  final raw = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    raw[y * stride] = 0;
    final src = y * width * 4;
    raw.setRange(y * stride + 1, y * stride + 1 + width * 4, rgba, src);
  }

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]); // signature

  final ihdr = BytesBuilder()
    ..add(_uint32(width))
    ..add(_uint32(height))
    ..addByte(8) // bit depth
    ..addByte(6) // colour type: truecolour with alpha (RGBA)
    ..addByte(0) // compression: deflate
    ..addByte(0) // filter: adaptive
    ..addByte(0); // interlace: none
  out.add(_chunk('IHDR', ihdr.toBytes()));

  final idat = ZLibEncoder().convert(raw);
  out.add(_chunk('IDAT', idat));

  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final body = BytesBuilder()
    ..add(type.codeUnits)
    ..add(data);
  final bodyBytes = body.toBytes();
  final out = BytesBuilder()
    ..add(_uint32(data.length))
    ..add(bodyBytes)
    ..add(_uint32(_crc32(bodyBytes)));
  return out.toBytes();
}

Uint8List _uint32(int value) {
  return Uint8List(4)
    ..[0] = (value >> 24) & 0xff
    ..[1] = (value >> 16) & 0xff
    ..[2] = (value >> 8) & 0xff
    ..[3] = value & 0xff;
}

/// CRC-32 (PNG polynomial 0xEDB88320), over the chunk type + data.
int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
