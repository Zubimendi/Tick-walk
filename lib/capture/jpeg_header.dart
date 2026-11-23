import 'dart:typed_data';

/// Pure domain helper to extract dimensions from JPEG image bytes without full image decoding.
/// Complies with Rule 5: Never decode full-resolution images in Dart.
class JpegDimensions {
  const JpegDimensions({required this.width, required this.height});

  final int width;
  final int height;

  @override
  String toString() => '${width}x$height';
}

/// Reads image dimensions from JPEG bytes by parsing JPEG SOF (Start of Frame) markers.
/// Returns null if not a valid JPEG or SOF marker is not found.
JpegDimensions? readJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4) return null;

  // Check SOI (Start of Image) marker 0xFFD8
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  var offset = 2;
  final length = bytes.length;

  while (offset < length - 8) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }

    final marker = bytes[offset + 1];

    // Standalone markers without length: SOI (0xD8), EOI (0xD9), RST0-RST7 (0xD0-0xD7)
    if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }

    // Read marker payload length (big-endian 16-bit, includes the 2 length bytes)
    if (offset + 4 > length) break;
    final markerLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (markerLength < 2) break;

    // Check for SOF markers:
    // 0xC0: SOF0 (Baseline DCT)
    // 0xC1: SOF1 (Extended Sequential DCT)
    // 0xC2: SOF2 (Progressive DCT)
    // 0xC3: SOF3 (Lossless)
    if ((marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF)) {
      if (offset + 9 > length) break;
      // Byte offset + 4 is data precision (bits/sample, usually 8)
      final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
      final width = (bytes[offset + 7] << 8) | bytes[offset + 8];

      if (width > 0 && height > 0) {
        return JpegDimensions(width: width, height: height);
      }
    }

    offset += 2 + markerLength;
  }

  return null;
}
