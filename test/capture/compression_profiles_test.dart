import 'package:flutter_test/flutter_test.dart';
import 'package:tickwalk/capture/compression_profiles.dart';

void main() {
  group('Compression Profiles (Pure Domain)', () {
    test('Profile definitions match specification', () {
      expect(CompressionProfile.low.maxDimension, equals(1280));
      expect(CompressionProfile.low.quality, equals(65));

      expect(CompressionProfile.standard.maxDimension, equals(1600));
      expect(CompressionProfile.standard.quality, equals(75));

      expect(CompressionProfile.high.maxDimension, equals(2048));
      expect(CompressionProfile.high.quality, equals(85));

      expect(CompressionProfile.thumbnailMaxDimension, equals(320));
      expect(CompressionProfile.thumbnailQuality, equals(70));
    });

    test('fromString safely resolves profiles', () {
      expect(CompressionProfile.fromString('low'), equals(CompressionProfile.low));
      expect(CompressionProfile.fromString('LOW'), equals(CompressionProfile.low));
      expect(CompressionProfile.fromString('high'), equals(CompressionProfile.high));
      expect(CompressionProfile.fromString('standard'), equals(CompressionProfile.standard));
      expect(CompressionProfile.fromString(null), equals(CompressionProfile.standard));
      expect(CompressionProfile.fromString('unknown'), equals(CompressionProfile.standard));
    });

    test('computeTargetDimensions scales landscape images correctly', () {
      // 4000x3000 -> longest edge scaled to 1600 -> 1600x1200
      final result = computeTargetDimensions(
        originalWidth: 4000,
        originalHeight: 3000,
        maxLongEdge: 1600,
      );
      expect(result.width, equals(1600));
      expect(result.height, equals(1200));
    });

    test('computeTargetDimensions scales portrait images correctly', () {
      // 3000x4000 -> longest edge scaled to 1600 -> 1200x1600
      final result = computeTargetDimensions(
        originalWidth: 3000,
        originalHeight: 4000,
        maxLongEdge: 1600,
      );
      expect(result.width, equals(1200));
      expect(result.height, equals(1600));
    });

    test('computeTargetDimensions preserves size when smaller than maxLongEdge', () {
      // 800x600 is smaller than 1600 -> remains 800x600
      final result = computeTargetDimensions(
        originalWidth: 800,
        originalHeight: 600,
        maxLongEdge: 1600,
      );
      expect(result.width, equals(800));
      expect(result.height, equals(600));
    });
  });
}
