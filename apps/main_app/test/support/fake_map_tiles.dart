import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// A 1x1 fully transparent PNG for tests, assembled at runtime.
///
/// A hand-written byte literal is easy to get subtly wrong — one stale CRC
/// or adler word decodes as "invalid image data", which Flutter reports as
/// an unhandled error and fails every map widget test. Building the file
/// with real checksums and a real zlib stream keeps that from ever being
/// the reason a map test goes red.
final Uint8List kTransparentTilePng = _buildTransparentPng();

Uint8List _buildTransparentPng() {
  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // signature

  final ihdr =
      BytesBuilder()
        ..add(_be32(1)) // width
        ..add(_be32(1)) // height
        ..add(const [8, 6, 0, 0, 0]); // 8-bit RGBA, no interlace
  out.add(_chunk('IHDR', ihdr.takeBytes()));

  // A single scanline: filter byte 0, then one fully transparent pixel.
  final scanline = Uint8List.fromList(const [0, 0, 0, 0, 0]);
  out.add(_chunk('IDAT', Uint8List.fromList(zlib.encode(scanline))));

  out.add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

/// A PNG chunk: length, type, data, then the CRC over type + data.
Uint8List _chunk(String type, Uint8List data) {
  final typeAndData = Uint8List.fromList([...type.codeUnits, ...data]);
  return Uint8List.fromList([
    ..._be32(data.length),
    ...typeAndData,
    ..._be32(_crc32(typeAndData)),
  ]);
}

List<int> _be32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Tile provider that never touches the network: every tile is a
/// transparent in-memory PNG, so widget tests exercise the map without
/// live OpenStreetMap fetches.
class FakeTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(kTransparentTilePng);
}
