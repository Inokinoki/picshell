import 'dart:convert';
import 'dart:typed_data';

/// Decodes Kitty graphics-protocol APC payloads (action `a=T`) into image
/// bytes for the floating-image pipeline.
///
/// The escape parser hands us the payload captured after `ESC _` — which
/// starts with the `G` command byte, e.g. `Ga=T,f=100,s=80,v=60;t=d...`. We:
///  1. split off the leading `G`,
///  2. split the remainder on the first `;` into control params (`k=v,k=v`)
///     and the base64 data,
///  3. reassemble chunked transfers (subsequent chunks carry only `m` +
///     payload, so a single accumulator suffices — transfers are not
///     interleaved),
///  4. for f=100 (PNG) base64-decode and emit the raw PNG bytes.
///
/// Raw RGB (f=24) / RGBA (f=32) need a PNG encoder and are dropped for now
/// (flagged via [unsupportedFormat]).
class KittyGraphicsHandler {
  KittyGraphicsHandler({
    required this.onImage,
    this.onUnsupportedFormat,
  });

  /// Receives a decoded image: (bytes, imageId-or-null, widthPx, heightPx).
  final void Function(Uint8List bytes, int? imageId, int? width, int? height)
      onImage;

  /// Called when a transfer uses an unsupported format (e.g. f=24/32) so the
  /// caller can log it. The transfer is otherwise dropped.
  final void Function(String format)? onUnsupportedFormat;

  // Pending multi-chunk transfer.
  _Pending? _pending;

  /// [payload] is the full APC content after `ESC _` (begins with `G`).
  void handle(String payload) {
    if (payload.isEmpty) return;

    final semi = payload.indexOf(';');
    final paramsStr = semi >= 0 ? payload.substring(0, semi) : payload;
    final dataPart = semi >= 0 ? payload.substring(semi + 1) : '';

    final params =
        _parseParams(paramsStr.startsWith('G') ? paramsStr.substring(1) : paramsStr);
    final more = params['m'] == '1';

    if (more) {
      _pending ??= _Pending(
        imageId: int.tryParse(params['i'] ?? ''),
        width: int.tryParse(params['s'] ?? ''),
        height: int.tryParse(params['v'] ?? ''),
        format: params['f'] ?? '100',
      );
      _pending!.buffer.write(dataPart);
      return;
    }

    // m==0 or absent: final (or single) chunk.
    final pending = _pending;
    if (pending != null) {
      pending.buffer.write(dataPart);
      _pending = null;
      _emit(pending);
    } else {
      _emit(_Pending(
        imageId: int.tryParse(params['i'] ?? ''),
        width: int.tryParse(params['s'] ?? ''),
        height: int.tryParse(params['v'] ?? ''),
        format: params['f'] ?? '100',
      )..buffer.write(dataPart));
    }
  }

  void _emit(_Pending p) {
    if (p.format != '100') {
      onUnsupportedFormat?.call(p.format);
      return;
    }
    final b64 = p.buffer.toString();
    if (b64.isEmpty) return;
    Uint8List bytes;
    try {
      bytes = base64.decode(b64);
    } catch (_) {
      return; // malformed base64 — drop
    }
    onImage(bytes, p.imageId, p.width, p.height);
  }

  /// Parses `k=v,k=v` into a map. Entries without `=` are skipped.
  static Map<String, String> _parseParams(String s) {
    final out = <String, String>{};
    if (s.isEmpty) return out;
    for (final part in s.split(',')) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        out[part.substring(0, eq)] = part.substring(eq + 1);
      }
    }
    return out;
  }
}

class _Pending {
  final int? imageId;
  final int? width;
  final int? height;
  final String format;
  final StringBuffer buffer = StringBuffer();

  _Pending({this.imageId, this.width, this.height, this.format = '100'});
}
