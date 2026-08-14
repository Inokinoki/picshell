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

  /// Cap on the accumulated (base64) payload characters, to bound memory on
  /// untrusted input (a stream of m=1 chunks with no terminating m=0 would
  /// otherwise grow the accumulator forever). Chunks are base64-decoded as
  /// they arrive, so the decoded image needs roughly this many bytes at most.
  static const maxAccumulatedBytes = 16 * 1024 * 1024; // 16 MiB

  /// A pending transfer that sees no further chunks for this long is dropped
  /// (a lost m=0 must not pin its buffer forever). Checked lazily on the next
  /// payload — no timer is armed.
  static const pendingTimeout = Duration(seconds: 30);

  /// [payload] is the full APC content after `ESC _` (begins with `G`).
  void handle(String payload) {
    if (payload.isEmpty) return;

    final semi = payload.indexOf(';');
    final paramsStr = semi >= 0 ? payload.substring(0, semi) : payload;
    final dataPart = semi >= 0 ? payload.substring(semi + 1) : '';

    final params =
        _parseParams(paramsStr.startsWith('G') ? paramsStr.substring(1) : paramsStr);
    final more = params["m"] == "1";
    

    // Only transmit actions (`a=T`/`a=t`, or absent) carry an image payload.
    // Anything else (e.g. a hostile `a=d` delete chunk with a payload) must
    // not be emitted as a phantom image.
    final action = params['a'];
    final transmit = action == null || action == 'T' || action == 't';

    // A chunk carrying `a=` (a fresh transmit) while a transfer is already
    // pending means the previous transfer's m=0 was lost — drop the orphan so
    // it doesn't swallow this image into the wrong id/dimensions.
    if (params.containsKey('a') && _pending != null) {
      _pending = null;
    }
    if (!transmit) return;

    // Lazily expire an orphaned pending transfer.
    final pending = _pending;
    if (pending != null &&
        DateTime.now().difference(pending.startedAt) > pendingTimeout) {
      _pending = null;
    }

    if (more) {
      _pending ??= _Pending(
        imageId: int.tryParse(params['i'] ?? ''),
        width: int.tryParse(params['s'] ?? ''),
        height: int.tryParse(params['v'] ?? ''),
        format: params['f'] ?? '100',
      );
      if (!_appendChunk(_pending!, dataPart)) {
        _pending = null; // oversized / malformed — drop the transfer
      }
      return;
    }

    // m==0 or absent: final (or single) chunk.
    if (pending != null) {
      if (!_appendChunk(pending, dataPart)) {
        _pending = null;
        return;
      }
      _pending = null;
      _emit(pending);
    } else {
      final single = _Pending(
        imageId: int.tryParse(params['i'] ?? ''),
        width: int.tryParse(params['s'] ?? ''),
        height: int.tryParse(params['v'] ?? ''),
        format: params['f'] ?? '100',
      );
      if (!_appendChunk(single, dataPart)) return;
      _emit(single);
    }
  }

  /// Appends one chunk's base64 text to [p], decoding as we go (a partial
  /// base64 quantum at the chunk boundary is carried over). Returns false if
  /// the transfer is over the cap or the chunk is malformed base64.
  bool _appendChunk(_Pending p, String data) {
    if (data.isEmpty) return true;
    if (p.b64Chars + data.length > maxAccumulatedBytes) return false;
    p.b64Chars += data.length;
    final s = p.b64Remainder + data;
    p.b64Remainder = '';
    // Decode only whole 4-char groups; carry the tail to the next chunk.
    final rem = s.length % 4;
    var decodable = s;
    if (rem != 0) {
      decodable = s.substring(0, s.length - rem);
      p.b64Remainder = s.substring(s.length - rem);
    }
    if (decodable.isNotEmpty) {
      try {
        p.buffer.add(base64.decode(decodable));
      } catch (_) {
        return false; // malformed base64 — drop
      }
    }
    return true;
  }

  void _emit(_Pending p) {
    if (p.format != '100') {
      onUnsupportedFormat?.call(p.format);
      return;
    }
    if (p.b64Remainder.isNotEmpty) {
      try {
        p.buffer.add(base64.decode(p.b64Remainder));
      } catch (_) {
        return; // malformed base64 — drop
      }
      p.b64Remainder = '';
    }
    if (p.buffer.isEmpty) return;
    onImage(p.buffer.toBytes(), p.imageId, p.width, p.height);
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

  /// Decoded bytes so far (base64 is decoded per chunk as it arrives).
  final BytesBuilder buffer = BytesBuilder(copy: false);

  /// Base64 characters carried from the previous chunk (a partial 4-char
  /// quantum split across a chunk boundary).
  String b64Remainder = '';

  /// Total base64 characters seen, for cap enforcement.
  int b64Chars = 0;

  /// When this transfer started, for orphan expiry.
  final DateTime startedAt = DateTime.now();

  _Pending({this.imageId, this.width, this.height, this.format = '100'});
}
