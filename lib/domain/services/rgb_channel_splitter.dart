import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// An immutable 2D binary bit matrix representing a single optical channel.
class RgbBitMatrix extends Equatable {
  final int width;
  final int height;
  final Uint8List _data;

  RgbBitMatrix({
    required this.width,
    required this.height,
    Uint8List? data,
  })  : assert(width > 0, 'width must be strictly positive'),
        assert(height > 0, 'height must be strictly positive'),
        _data = data ?? Uint8List((width * height + 7) >> 3);

  /// Factory creating an empty bit matrix filled with zeros.
  factory RgbBitMatrix.empty(int width, int height) {
    return RgbBitMatrix(
      width: width,
      height: height,
      data: Uint8List((width * height + 7) >> 3),
    );
  }

  /// Factory creating a bit matrix from a list of boolean rows.
  factory RgbBitMatrix.fromBooleans(List<List<bool>> grid) {
    final height = grid.length;
    if (height == 0) {
      throw ArgumentError('Grid cannot be empty');
    }
    final width = grid[0].length;
    final matrix = RgbBitMatrix.empty(width, height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (grid[y][x]) {
          matrix.set(x, y, true);
        }
      }
    }
    return matrix;
  }

  /// Gets the boolean state of the module at ([x], [y]).
  bool get(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width x $height)');
    }
    final index = y * width + x;
    final byteIndex = index >> 3;
    final bitOffset = index & 7;
    return (_data[byteIndex] & (1 << bitOffset)) != 0;
  }

  /// Sets the boolean state of the module at ([x], [y]).
  void set(int x, int y, bool value) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width x $height)');
    }
    final index = y * width + x;
    final byteIndex = index >> 3;
    final bitOffset = index & 7;
    if (value) {
      _data[byteIndex] |= (1 << bitOffset);
    } else {
      _data[byteIndex] &= ~(1 << bitOffset);
    }
  }

  /// Raw packed bit data buffer.
  Uint8List get data => _data;

  @override
  List<Object?> get props => [width, height, _data];
}

/// A 2D matrix where each cell holds a 3-bit multiplexed RGB color code (0..7).
///
/// Bit layout per cell:
/// - Bit 0: Blue channel (0 or 1)
/// - Bit 1: Green channel (0 or 1)
/// - Bit 2: Red channel (0 or 1)
class RgbMultiplexedColorMatrix extends Equatable {
  final int width;
  final int height;
  final Uint8List _cells;

  RgbMultiplexedColorMatrix({
    required this.width,
    required this.height,
    Uint8List? cells,
  })  : assert(width > 0, 'width must be strictly positive'),
        assert(height > 0, 'height must be strictly positive'),
        _cells = cells ?? Uint8List(width * height);

  /// Gets the 3-bit color code at ([x], [y]).
  int getColorCode(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width x $height)');
    }
    return _cells[y * width + x];
  }

  /// Sets the 3-bit color code at ([x], [y]).
  void setColorCode(int x, int y, int code) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Coordinates ($x, $y) out of bounds ($width x $height)');
    }
    _cells[y * width + x] = code & 0x07;
  }

  /// Raw cells buffer containing 3-bit color codes (values 0..7).
  Uint8List get cells => _cells;

  @override
  List<Object?> get props => [width, height, _cells];
}

/// A container holding the 3 split optical channel bit matrices.
class RgbSplitChannels extends Equatable {
  final RgbBitMatrix red;
  final RgbBitMatrix green;
  final RgbBitMatrix blue;

  const RgbSplitChannels({
    required this.red,
    required this.green,
    required this.blue,
  });

  @override
  List<Object?> get props => [red, green, blue];
}

/// Service providing RGB optical channel multiplexing (3x throughput transmission)
/// and receiver-side color de-multiplexing and threshold splitting.
class OpticalRgbMultiplexer {
  /// Multiplexes 3 single-channel bit matrices into a composite 3-channel [RgbMultiplexedColorMatrix].
  static RgbMultiplexedColorMatrix multiplex({
    required RgbBitMatrix red,
    required RgbBitMatrix green,
    required RgbBitMatrix blue,
  }) {
    if (red.width != green.width ||
        red.width != blue.width ||
        red.height != green.height ||
        red.height != blue.height) {
      throw ArgumentError(
        'Channel dimensions must match exactly: '
        'Red (${red.width}x${red.height}), '
        'Green (${green.width}x${green.height}), '
        'Blue (${blue.width}x${blue.height})',
      );
    }

    final width = red.width;
    final height = red.height;
    final colorMatrix = RgbMultiplexedColorMatrix(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final r = red.get(x, y) ? 4 : 0;
        final g = green.get(x, y) ? 2 : 0;
        final b = blue.get(x, y) ? 1 : 0;
        colorMatrix.setColorCode(x, y, r | g | b);
      }
    }

    return colorMatrix;
  }

  /// Splits an [RgbMultiplexedColorMatrix] back into its 3 constituent single-channel matrices.
  static RgbSplitChannels splitColorMatrix(
      RgbMultiplexedColorMatrix multiplexed) {
    final width = multiplexed.width;
    final height = multiplexed.height;

    final red = RgbBitMatrix.empty(width, height);
    final green = RgbBitMatrix.empty(width, height);
    final blue = RgbBitMatrix.empty(width, height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final code = multiplexed.getColorCode(x, y);
        if ((code & 4) != 0) red.set(x, y, true);
        if ((code & 2) != 0) green.set(x, y, true);
        if ((code & 1) != 0) blue.set(x, y, true);
      }
    }

    return RgbSplitChannels(red: red, green: green, blue: blue);
  }

  /// Splits a raw camera pixel buffer (RGB, RGBA, or BGRA) into 3 optical channels
  /// using an adaptive thresholding barrier.
  static RgbSplitChannels splitPixelBuffer({
    required Uint8List pixels,
    required int width,
    required int height,
    required int bytesPerPixel,
    int redOffset = 0,
    int greenOffset = 1,
    int blueOffset = 2,
    int threshold = 128,
  }) {
    if (pixels.length < width * height * bytesPerPixel) {
      throw ArgumentError(
        'Pixel buffer length (${pixels.length}) smaller than required (${width * height * bytesPerPixel})',
      );
    }

    final red = RgbBitMatrix.empty(width, height);
    final green = RgbBitMatrix.empty(width, height);
    final blue = RgbBitMatrix.empty(width, height);

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width * bytesPerPixel;
      for (int x = 0; x < width; x++) {
        final pixelOffset = rowOffset + x * bytesPerPixel;
        final rVal = pixels[pixelOffset + redOffset];
        final gVal = pixels[pixelOffset + greenOffset];
        final bVal = pixels[pixelOffset + blueOffset];

        if (rVal >= threshold) red.set(x, y, true);
        if (gVal >= threshold) green.set(x, y, true);
        if (bVal >= threshold) blue.set(x, y, true);
      }
    }

    return RgbSplitChannels(red: red, green: green, blue: blue);
  }

  /// Converts an [RgbMultiplexedColorMatrix] to a 32-bit RGBA pixel byte array.
  static Uint8List toRgbaPixels(
    RgbMultiplexedColorMatrix matrix, {
    int activeAlpha = 255,
  }) {
    final width = matrix.width;
    final height = matrix.height;
    final buffer = Uint8List(width * height * 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final code = matrix.getColorCode(x, y);
        final offset = (y * width + x) * 4;

        buffer[offset] = (code & 4) != 0 ? 255 : 0; // R
        buffer[offset + 1] = (code & 2) != 0 ? 255 : 0; // G
        buffer[offset + 2] = (code & 1) != 0 ? 255 : 0; // B
        buffer[offset + 3] = activeAlpha; // A
      }
    }

    return buffer;
  }
}

