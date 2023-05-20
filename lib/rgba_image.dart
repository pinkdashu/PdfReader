import 'dart:typed_data';

Uint8List Rgba4444ToBmp(Uint8List Rgba, int width, int height) {
  var header = BMP332Header(width, height);
  var bmp = header.appendBitmap(Rgba);
  return bmp;
}

class BMP332Header {
  final int
      _width; // NOTE: width must be multiple of 4 as no account is made for bitmap padding
  final int _height;

  late Uint8List _bmp;
  late int _totalHeaderSize;

  BMP332Header(this._width, this._height) {
    int baseHeaderSize = 54;
    _totalHeaderSize = baseHeaderSize; // base + color map, color map = 0
    int fileLength = _totalHeaderSize + _width * _height * 4; // header + bitmap
    _bmp = Uint8List(fileLength);
    ByteData bd = _bmp.buffer.asByteData();
    bd.setUint8(0, 0x42);
    bd.setUint8(1, 0x4d);
    bd.setUint32(2, fileLength, Endian.little); // file length
    bd.setUint32(10, _totalHeaderSize, Endian.little); // start of the bitmap
    bd.setUint32(14, 40, Endian.little); // info header size
    bd.setUint32(18, _width, Endian.little);
    bd.setUint32(22, -_height, Endian.little);
    bd.setUint16(26, 1, Endian.little); // planes
    bd.setUint32(28, 32, Endian.little); // bpp
    bd.setUint32(30, 0, Endian.little); // compression
    bd.setUint32(34, _width * _height, Endian.little); // bitmap size
  }

  /// Insert the provided bitmap after the header and return the whole BMP
  Uint8List appendBitmap(Uint8List bitmap) {
    int size = _width * _height * 4;
    print(size.toString());
    print(bitmap.length.toString());
    assert(bitmap.length == size);
    _bmp.setRange(_totalHeaderSize, _totalHeaderSize + size, bitmap);
    return _bmp;
  }
}
