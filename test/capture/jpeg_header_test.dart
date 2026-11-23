import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/capture/jpeg_header.dart';

void main() {
  group('JPEG Header Dimension Extraction (Rule 5)', () {
    test('extracts width and height from valid JPEG SOF0 header', () {
      // Minimal synthetic JPEG with SOF0 marker (1600x1200)
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, // SOF0
        0x00, 0x0B, // Length = 11 bytes
        0x08, // Precision = 8
        0x04, 0xB0, // Height = 1200 (0x04B0)
        0x06, 0x40, // Width = 1600 (0x0640)
        0x03, 0x01, 0x11, 0x00, // Components
        0xFF, 0xD9, // EOI
      ]);

      final dim = readJpegDimensions(bytes);
      expect(dim, isNotNull);
      expect(dim!.width, equals(1600));
      expect(dim.height, equals(1200));
    });

    test('returns null for non-JPEG bytes', () {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(readJpegDimensions(pngBytes), isNull);
    });

    test('returns null for empty or truncated bytes', () {
      expect(readJpegDimensions(Uint8List(0)), isNull);
      expect(readJpegDimensions(Uint8List.fromList([0xFF, 0xD8])), isNull);
    });
  });
}
