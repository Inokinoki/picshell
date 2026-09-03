import 'dart:typed_data';

/// A decoded Sixel image: an RGBA8888 buffer plus pixel dimensions.
class SixelImage {
  final Uint8List rgba;
  final int width;
  final int height;
  SixelImage(this.rgba, this.width, this.height);
}

class _Color {
  final int r, g, b;
  const _Color(this.r, this.g, this.b);
  static const white = _Color(255, 255, 255);
}

/// Decodes Sixel graphics data (the body of a `DCS q ... ST` sequence) into an
/// RGBA buffer.
///
/// The data is a mix of:
///  - raster declarations `"<params>` (consumed; sizing is derived from the
///    drawn extent for robustness),
///  - colour-register declarations `#n;Pu;Px;Py;Pz` (HLS, Pu=1) or
///    `#n:Pu:Px:Py:Pz` (RGB, Pu=2),
///  - colour-register selection `#n`,
///  - sixel data chars `?`–`~` (each encodes 6 vertical pixels, bit0 = top),
///  - `!nC` (repeat char C for n columns), `$` (carriage return), `-` (advance
///    one 6-row band).
///
/// Two passes: measure the drawn extent, then rasterise into an allocated
/// buffer. Undrawn pixels are transparent.
class SixelDecoder {
  /// Cap on a single `!N` repeat and on total decoded pixels, to bound work on
  /// untrusted remote output (a `!999999999~` would otherwise spin the CPU in
  /// the measure pass and OOM on allocation).
  static const maxRepeat = 4096;
  static const maxPixels = 1 << 23; // 8 Mpx ≈ 32 MiB RGBA

  /// Highest colour-register number stored, per the DEC spec (2^16 - 1).
  /// Definitions with a higher register number are skipped so a hostile
  /// `#999999999;...` stream can't grow the palette map without bound.
  static const maxRegister = 65535;

  SixelImage? decode(String data) {
    // One palette shared by both passes (measure + rasterise) — definitions
    // are parsed once instead of twice.
    final palette = <int, _Color>{};
    var maxX = 0;
    var maxBand = 0; // number of 6-row bands touched
    _walk(data, palette, (x, y, r, g, b) {
      if (x + 1 > maxX) maxX = x + 1;
      final band = y ~/ 6 + 1;
      if (band > maxBand) maxBand = band;
    });
    if (maxX == 0 || maxBand == 0) return null;

    final width = maxX;
    final height = maxBand * 6;
    // Refuse pathological sizes before allocating ~4 bytes/pixel.
    if (width > maxPixels || height > maxPixels || width * height > maxPixels) {
      return null;
    }
    final rgba = Uint8List(width * height * 4); // zeros = fully transparent
    _walk(data, palette, (x, y, r, g, b) {
      final idx = (y * width + x) * 4;
      rgba[idx] = r;
      rgba[idx + 1] = g;
      rgba[idx + 2] = b;
      rgba[idx + 3] = 255;
    });
    return SixelImage(rgba, width, height);
  }

  void _walk(
    String data,
    Map<int, _Color> palette,
    void Function(int x, int y, int r, int g, int b) onPixel,
  ) {
    var currentReg = 0;
    var x = 0;
    var y = 0;
    final units = data.codeUnits;
    var i = 0;

    void drawSixel(int sixelChar, int count) {
      final bits = (sixelChar - 0x3f) & 0x3f;
      final color = palette[currentReg] ?? _Color.white;
      for (var n = 0; n < count; n++) {
        for (var bit = 0; bit < 6; bit++) {
          if ((bits & (1 << bit)) != 0) {
            onPixel(x + n, y + bit, color.r, color.g, color.b);
          }
        }
      }
    }

    while (i < units.length) {
      final ch = units[i];
      if (ch == 0x22) {
        // Raster declaration "P1;P2;P3;P4 — consume its parameter bytes.
        i++;
        while (i < units.length &&
            (units[i] >= 0x30 && units[i] <= 0x3f)) {
          i++;
        }
        continue;
      }
      if (ch == 0x23) {
        // Colour register: selection (#n) and/or definition (#n;Pu;Px;Py;Pz).
        i++;
        final regBuf = StringBuffer();
        while (i < units.length && units[i] >= 0x30 && units[i] <= 0x39) {
          regBuf.writeCharCode(units[i]);
          i++;
        }
        final reg = regBuf.isEmpty ? currentReg : int.tryParse(regBuf.toString()) ?? currentReg;
        if (i < units.length &&
            (units[i] == 0x3b || units[i] == 0x3a)) {
          final sep = units[i];
          i++;
          final comps = _readNumbers(units, i, sep, 4);
          i = comps.$2;
          final color = _colorFromDef(comps.$1);
          if (color != null && reg <= maxRegister) palette[reg] = color;
        }
        currentReg = reg;
        continue;
      }
      if (ch == 0x21) {
        // Repeat: !nC
        i++;
        final nBuf = StringBuffer();
        while (i < units.length && units[i] >= 0x30 && units[i] <= 0x39) {
          nBuf.writeCharCode(units[i]);
          i++;
        }
        final n = (nBuf.isEmpty ? 1 : int.tryParse(nBuf.toString()) ?? 1)
            .clamp(1, maxRepeat); // bound !N (DoS hardening)
        if (i >= units.length) break;
        drawSixel(units[i], n);
        i++;
        x += n;
        continue;
      }
      if (ch == 0x24) {
        // Carriage return (same band).
        x = 0;
        i++;
        continue;
      }
      if (ch == 0x2d) {
        // New line — next 6-row band.
        y += 6;
        x = 0;
        i++;
        continue;
      }
      if (ch >= 0x3f && ch <= 0x7e) {
        drawSixel(ch, 1);
        x += 1;
        i++;
        continue;
      }
      // Whitespace / stray byte — ignore.
      i++;
    }
  }

  /// Reads up to [count] integers separated by [sep], starting at [start].
  /// Returns (values, nextIndex).
  (List<int>, int) _readNumbers(
    List<int> units,
    int start,
    int sep,
    int count,
  ) {
    final values = <int>[];
    var i = start;
    for (var c = 0; c < count && i < units.length; c++) {
      final buf = StringBuffer();
      while (i < units.length && units[i] >= 0x30 && units[i] <= 0x39) {
        buf.writeCharCode(units[i]);
        i++;
      }
      values.add(buf.isEmpty ? 0 : int.tryParse(buf.toString()) ?? 0);
      if (c < count - 1 && i < units.length && units[i] == sep) {
        i++;
      } else {
        break;
      }
    }
    return (values, i);
  }

  /// Parses a colour definition `[Pu, Px, Py, Pz]`.
  /// Pu=1 → HLS (hue 0-360, L 0-100, S 0-100); Pu=2/other → RGB (0-100 each).
  _Color? _colorFromDef(List<int> comps) {
    if (comps.length < 4) return null;
    final pu = comps[0];
    final a = comps[1].toDouble();
    final b = comps[2].toDouble();
    final c = comps[3].toDouble();
    if (pu == 1) {
      return _hlsToRgb(a, b, c);
    }
    return _Color(
      (a * 2.55).round().clamp(0, 255),
      (b * 2.55).round().clamp(0, 255),
      (c * 2.55).round().clamp(0, 255),
    );
  }

  _Color _hlsToRgb(double h, double l, double s) {
    // h: 0-360, l/s: 0-100 (percent).
    final ll = l / 100;
    final ss = s / 100;
    final c = (1 - (2 * ll - 1).abs()) * ss;
    final hp = h / 60;
    final x = c * (1 - (hp % 2 - 1).abs());
    double r1, g1, b1;
    if (hp < 1) {
      r1 = c; g1 = x; b1 = 0;
    } else if (hp < 2) {
      r1 = x; g1 = c; b1 = 0;
    } else if (hp < 3) {
      r1 = 0; g1 = c; b1 = x;
    } else if (hp < 4) {
      r1 = 0; g1 = x; b1 = c;
    } else if (hp < 5) {
      r1 = x; g1 = 0; b1 = c;
    } else {
      r1 = c; g1 = 0; b1 = x;
    }
    final m = ll - c / 2;
    return _Color(
      ((r1 + m) * 255).round().clamp(0, 255),
      ((g1 + m) * 255).round().clamp(0, 255),
      ((b1 + m) * 255).round().clamp(0, 255),
    );
  }
}
