/// Pure domain compression profiles.
/// Invariant: No Flutter, Drift, or platform imports.
enum CompressionProfile {
  low(maxDimension: 1280, quality: 65),
  standard(maxDimension: 1600, quality: 75),
  high(maxDimension: 2048, quality: 85);

  const CompressionProfile({
    required this.maxDimension,
    required this.quality,
  });

  final int maxDimension;
  final int quality;

  static const int thumbnailMaxDimension = 320;
  static const int thumbnailQuality = 70;

  static CompressionProfile fromString(String? value) {
    return switch (value?.toLowerCase()) {
      'low' => CompressionProfile.low,
      'high' => CompressionProfile.high,
      _ => CompressionProfile.standard,
    };
  }
}

/// Target image dimensions after scaling preserving aspect ratio.
class TargetDimensions {
  const TargetDimensions({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetDimensions &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => width.hashCode ^ height.hashCode;

  @override
  String toString() => '${width}x$height';
}

/// Computes scaled dimensions fitting within [maxLongEdge] while preserving aspect ratio.
/// If the image is already smaller than [maxLongEdge] on both sides, returns original dimensions.
TargetDimensions computeTargetDimensions({
  required int originalWidth,
  required int originalHeight,
  required int maxLongEdge,
}) {
  if (originalWidth <= 0 || originalHeight <= 0) {
    return TargetDimensions(
      width: maxLongEdge,
      height: maxLongEdge,
    );
  }

  final longestEdge = originalWidth > originalHeight ? originalWidth : originalHeight;
  if (longestEdge <= maxLongEdge) {
    return TargetDimensions(width: originalWidth, height: originalHeight);
  }

  final scale = maxLongEdge / longestEdge;
  final newWidth = (originalWidth * scale).round();
  final newHeight = (originalHeight * scale).round();

  return TargetDimensions(
    width: newWidth > 0 ? newWidth : 1,
    height: newHeight > 0 ? newHeight : 1,
  );
}
