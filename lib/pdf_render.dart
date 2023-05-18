import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widget;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'package:path/path.dart' as path;
import 'package:pdfium_bindings/pdfium_bindings.dart';
import 'package:buffer_image/buffer_image.dart';
import 'rgba_image.dart';

enum _Codes { init, image, ack, pageInfo }

class _Command {
  const _Command(this.code, {this.arg0, this.arg1});
  final _Codes code;
  final Object? arg0;
  final Object? arg1;
}

class SimplePdfRender {
  SimplePdfRender._(this._isolate, this._path);

  final Isolate _isolate;
  final String _path;
  late final SendPort _sendPort;

  final Queue<Completer<void>> _completers = Queue<Completer<void>>();

  final Queue<StreamController<widget.Image>> _resultStream =
      Queue<StreamController<widget.Image>>();
  late StreamController<List<ui.Size>> _resultPageInfo;

  static Future<SimplePdfRender> open(String path) async {
    final ReceivePort receivePort = ReceivePort();
    final Isolate isolate =
        await Isolate.spawn(_SimplePdfRenderServer._run, receivePort.sendPort);
    final SimplePdfRender result = SimplePdfRender._(isolate, path);
    Completer<void> completer = Completer<void>();
    result._completers.addFirst(completer);
    receivePort.listen((Object? message) {
      result._handleCommand(message as _Command);
    });
    await completer.future;
    return result;
  }

  void _handleCommand(_Command command) {
    //print("handleCommand  ${command.code}");
    switch (command.code) {
      case _Codes.init:
        _sendPort = command.arg0 as SendPort;
        RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
        _sendPort
            .send(_Command(_Codes.init, arg0: _path, arg1: rootIsolateToken));
        break;
      case _Codes.ack:
        _completers.removeLast().complete();
        break;
      case _Codes.image:
        print("queue length:${_resultStream.length}");
        _resultStream.last.add(command.arg0 as widget.Image);
        _resultStream.removeLast().close();
        break;
      case _Codes.pageInfo:
        _resultPageInfo
          ..add(command.arg0 as List<ui.Size>)
          ..close();
        break;
      default:
    }
  }

  Stream<widget.Image> getImage(int page, double scale) {
    //print("start get image");
    StreamController<widget.Image> resultStream =
        StreamController<widget.Image>();
    _resultStream.addFirst(resultStream);
    _sendPort.send(_Command(_Codes.image, arg0: page, arg1: scale));
    return resultStream.stream;
  }

  Stream<List<ui.Size>> getPageInfo() {
    _resultPageInfo = StreamController<List<ui.Size>>();
    _sendPort.send(_Command(_Codes.pageInfo));
    return _resultPageInfo.stream;
  }
}

class _SimplePdfRenderServer {
  _SimplePdfRenderServer._(this._sendPort);
  late final SendPort _sendPort;
  late final PdfRender _pdfRender;
  late final String _path;

  static void _run(SendPort sendPort) {
    ReceivePort receivePort = ReceivePort();
    sendPort.send(_Command(_Codes.init, arg0: receivePort.sendPort));
    final _SimplePdfRenderServer server = _SimplePdfRenderServer._(sendPort);
    receivePort.listen((Object? message) {
      final _Command command = message as _Command;
      server._handleCommand(command);
    });
  }

  Future<void> _handleCommand(_Command command) async {
    switch (command.code) {
      case _Codes.init:
        _path = command.arg0 as String;
        RootIsolateToken rootIsolateToken = command.arg1 as RootIsolateToken;
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
        _pdfRender = await PdfRender();
        _pdfRender.loadDocumentFromPath(_path);
        _sendPort.send(const _Command(_Codes.ack));
        break;
      case _Codes.image:
        var page = command.arg0 as int;
        var scale = command.arg1 as double;
        var start = DateTime.now();
        var image = _pdfRender.RenderPageAsImage(page, scale: scale);
        var end = DateTime.now();
        var costs = end.difference(start);
        print("send image ${page},costs ${costs.toString()}");
        _sendPort.send(_Command(_Codes.image, arg0: image));
      case _Codes.pageInfo:
        var pageInfo = _pdfRender.getPageInfo();
        _sendPort.send(_Command(_Codes.pageInfo, arg0: pageInfo));
      default:
    }
  }
}

/// Wrapper class to abstract the PDFium logic
class PdfRender {
  /// Bindings to PDFium
  late PDFiumBindings pdfium;

  /// PDFium configuration
  late Pointer<FPDF_LIBRARY_CONFIG> config;
  final Allocator allocator;
  Pointer<fpdf_document_t__>? _document;
  Pointer<fpdf_page_t__>? _page;
  Pointer<Uint8>? buffer;
  Pointer<fpdf_bitmap_t__>? bitmap;

  Map<int, Pointer<fpdf_page_t__>?> _pageCache = {};
  Map<Pointer<fpdf_page_t__>, double> _pageWidthCache = {};
  Map<Pointer<fpdf_page_t__>, double> _pageHeightCache = {};
  Map<Pointer<fpdf_page_t__>, Int8List> _pagePngCache = {};

  /// Default constructor to use the class
  PdfRender({String? libraryPath, this.allocator = calloc}) {
    //for windows
    var libPath = path.join(Directory.current.path, 'pdfium.dll');

    if (Platform.isMacOS) {
      libPath = path.join(Directory.current.path, 'libpdfium.dylib');
    } else if (Platform.isLinux || Platform.isAndroid) {
      libPath = path.join(Directory.current.path, 'libpdfium.so');
    }
    if (libraryPath != null) {
      libPath = libraryPath;
    }
    late DynamicLibrary dylib;
    if (Platform.isIOS) {
      DynamicLibrary.process();
    } else {
      dylib = DynamicLibrary.open(libPath);
    }
    pdfium = PDFiumBindings(dylib);

    config = allocator<FPDF_LIBRARY_CONFIG>();
    config.ref.version = 2;
    config.ref.m_pUserFontPaths = nullptr;
    config.ref.m_pIsolate = nullptr;
    config.ref.m_v8EmbedderSlot = 0;
    pdfium.FPDF_InitLibraryWithConfig(config);
    //print('pdfium init');
  }

  /// Loads a document from [path], and if necessary, a [password] can be
  /// specified.
  ///
  /// Throws an [PdfiumException] if no document is loaded.
  /// Returns a instance of [PdfRender]
  PdfRender loadDocumentFromPath(String path, {String? password}) {
    final filePathP = stringToNativeInt8(path);
    _document = pdfium.FPDF_LoadDocument(
      filePathP,
      password != null ? stringToNativeInt8(password) : nullptr,
    );
    if (_document == nullptr) {
      final err = pdfium.FPDF_GetLastError();
      throw PdfiumException.fromErrorCode(err);
    }
    // for (var i = 0; i < getpageInfo(); i++) {
    //   loadPage(i);
    //   getPageHeight();
    //   getPageWidth();
    // }
    return this;
  }

  /// Loads a document from [bytes], and if necessary, a [password] can be
  /// specified.
  ///
  /// Throws an [PdfiumException] if the document is null.
  /// Returns a instance of [PdfRender]
  PdfRender loadDocumentFromBytes(Uint8List bytes, {String? password}) {
    // Allocate a pointer large enough.
    final frameData = allocator<Uint8>(bytes.length);
    // Create a list that uses our pointer and copy in the image data.
    final pointerList = frameData.asTypedList(bytes.length);
    pointerList.setAll(0, bytes);

    _document = pdfium.FPDF_LoadMemDocument64(
      frameData.cast<Void>(),
      bytes.length,
      password != null ? stringToNativeInt8(password) : nullptr,
    );

    if (_document == nullptr) {
      final err = pdfium.FPDF_GetLastError();
      throw PdfiumException.fromErrorCode(err);
    }
    return this;
  }

  /// Loads a page from a document loaded
  ///
  /// Throws an [PdfiumException] if the no document is loaded, and a
  /// [PageException] if the page being attempted to load does not exist.
  /// Returns a instance of [PdfRender]
  PdfRender loadPage(int index) {
    if (_document == nullptr) {
      throw PdfiumException(message: 'Document not load');
    }
    if (_pageCache[index] == null) {
      _pageCache[index] = pdfium.FPDF_LoadPage(_document!, index);
      _page = pdfium.FPDF_LoadPage(_document!, index);
      if (_page == nullptr) {
        final err = pdfium.getLastErrorMessage();
        throw PageException(message: err);
      }
    }
    _page = _pageCache[index];
    return this;
  }

  Pointer<fpdf_page_t__> getPage(int index) {
    if (_document == nullptr) {
      throw PdfiumException(message: 'Document not load');
    }
    if (_pageCache[index] == null) {
      _pageCache[index] = pdfium.FPDF_LoadPage(_document!, index);
      _page = pdfium.FPDF_LoadPage(_document!, index);
      if (_page == nullptr) {
        final err = pdfium.getLastErrorMessage();
        throw PageException(message: err);
      }
    }
    return _pageCache[index]!;
  }

  List<ui.Size> getPageInfo() {
    int count = getPageCount();
    List<ui.Size> pageInfo = [];
    for (var i = 0; i < count; i++) {
      final page = getPage(i);
      pageInfo.add(ui.Size(
          pdfium.FPDF_GetPageWidthF(page), pdfium.FPDF_GetPageHeightF(page)));
    }
    getPage(0);
    return pageInfo;
  }

  /// Returns the number of pages of the loaded document.
  ///
  /// Throws an [PdfiumException] if the no document is loaded
  int getPageCount() {
    if (_document == nullptr) {
      throw PdfiumException(message: 'Document not load');
    }
    return pdfium.FPDF_GetPageCount(_document!);
  }

  /// Returns the width of the loaded page.
  ///
  /// Throws an [PdfiumException] if no page is loaded
  double getPageWidth() {
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    if (_pageWidthCache[_page] == null) {
      _pageWidthCache[_page!] = pdfium.FPDF_GetPageWidth(_page!);
    }
    return _pageWidthCache[_page!]!;
  }

  /// Returns the height of the loaded page.
  ///
  /// Throws an [PdfiumException] if no page is loaded
  double getPageHeight() {
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    if (_pageHeightCache[_page] == null) {
      _pageHeightCache[_page!] = pdfium.FPDF_GetPageHeight(_page!);
    }
    return _pageHeightCache[_page!]!;
  }

  /// Create empty bitmap and render page onto it
  /// The bitmap always uses 4 bytes per pixel. The first byte is always
  /// double word aligned.
  /// The byte order is BGRx (the last byte unused if no alpha channel) or
  /// BGRA. flags FPDF_ANNOT | FPDF_LCD_TEXT
  Uint8List renderPageAsBytes(
    int width,
    int height, {
    int backgroundColor = 268435455,
    int rotate = 0,
    int flags = 0,
  }) {
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = width;
    final h = height;
    const startX = 0;
    final sizeX = w;
    const startY = 0;
    final sizeY = h;

    // Create empty bitmap and render page onto it
    // The bitmap always uses 4 bytes per pixel. The first byte is always
    // double word aligned.
    // The byte order is BGRx (the last byte unused if no alpha channel) or
    // BGRA. flags FPDF_ANNOT | FPDF_LCD_TEXT

    bitmap = pdfium.FPDFBitmap_Create(w, h, 0);
    pdfium.FPDFBitmap_FillRect(bitmap!, 0, 0, w, h, backgroundColor);
    pdfium.FPDF_RenderPageBitmap(
      bitmap!,
      _page!,
      startX,
      startY,
      sizeX,
      sizeY,
      rotate,
      flags,
    );
    //  The pointer to the first byte of the bitmap buffer The data is in BGRA format
    buffer = pdfium.FPDFBitmap_GetBuffer(bitmap!);
    //stride = width * 4 bytes per pixel BGRA
    //var stride = pdfium.FPDFBitmap_GetStride(bitmap);
    ////print('stride $stride');
    final list = buffer!.asTypedList(w * h * 4);

    return list;
  }

  /// Saves the loaded page as png image
  ///
  /// Throws an [PdfiumException] if no page is loaded.
  /// Returns a instance of [PdfRender]
  PdfRender savePageAsPng(
    String outPath, {
    int? width,
    int? height,
    int backgroundColor = 268435455,
    double scale = 1,
    int rotate = 0,
    int flags = 0,
    bool flush = false,
    int pngLevel = 6,
  }) {
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = ((width ?? getPageWidth()) * scale).round();
    final h = ((height ?? getPageHeight()) * scale).round();

    final bytes = renderPageAsBytes(
      w,
      h,
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    );

    // save bitmap as PNG.
    File(outPath)
        .writeAsBytesSync(img.encodePng(image, level: pngLevel), flush: flush);
    return this;
  }

  /// Saves the loaded page as jpg image
  ///
  /// Throws an [PdfiumException] if no page is loaded.
  /// Returns a instance of [PdfRender]
  PdfRender savePageAsJpg(
    String outPath, {
    int? width,
    int? height,
    int backgroundColor = 268435455,
    double scale = 1,
    int rotate = 0,
    int flags = 0,
    bool flush = false,
    int qualityJpg = 100,
  }) {
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = ((width ?? getPageWidth()) * scale).round();
    final h = ((height ?? getPageHeight()) * scale).round();

    final bytes = renderPageAsBytes(
      w,
      h,
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    );

    // save bitmap as PNG.
    File(outPath).writeAsBytesSync(img.encodeJpg(image, quality: qualityJpg),
        flush: flush);
    return this;
  }

  /// Closes the page if it was open. Returns a instance of [PdfRender]
  PdfRender closePage() {
    if (_page != null && _page != nullptr) {
      pdfium.FPDF_ClosePage(_page!);

      if (bitmap != null && bitmap != nullptr) {
        pdfium.FPDFBitmap_Destroy(bitmap!);
      }
    }
    return this;
  }

  /// Closes the document if it was open. Returns a instance of [PdfRender]
  PdfRender closeDocument() {
    if (_document != null && _document != nullptr) {
      pdfium.FPDF_CloseDocument(_document!);
    }
    return this;
  }

  Uint8List RenderPageAsPng({
    int? width,
    int? height,
    int backgroundColor = 268435455,
    double scale = 1,
    int rotate = 0,
    int flags = 0,
    bool flush = false,
    int pngLevel = 6,
  }) {
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = ((width ?? getPageWidth()) * scale).round();
    final h = ((height ?? getPageHeight()) * scale).round();

    final bytes = renderPageAsBytes(
      w,
      h,
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    );
    return img.encodeBmp(image);
  }

  Uint8List RenderPageAsPngCompute(
    int page, {
    int? width,
    int? height,
    int backgroundColor = 268435455,
    double scale = 1,
    int rotate = 0,
    int flags = 0,
    bool flush = false,
    int pngLevel = 6,
  }) {
    //print('png render');
    final __page = getPage(page);
    if (__page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = ((width ?? getPageWidth()) * scale).round();
    final h = ((height ?? getPageHeight()) * scale).round();

    final bytes = renderPageAsBytes(
      w,
      h,
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    );
    ////print(image.toString());
    return img.encodeBmp(image);
  }

  widget.Image RenderPageAsImage(
    int page, {
    int? width,
    int? height,
    int backgroundColor = 268435455,
    double scale = 1,
    int rotate = 0,
    int flags = 0,
    bool flush = false,
    int pngLevel = 6,
  }) {
    //print('png render');
    _page = getPage(page);
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = (width ?? getPageWidth()) * scale;
    final h = (height ?? getPageHeight()) * scale;
    print('w:${w},h:${h}');
    var start = DateTime.now();
    final bytes = renderPageAsBytes(
      w.round(),
      h.round(),
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );
    var costs = DateTime.now().difference(start);
    print("-----costs ${costs.toString()}");

    var bmp = Rgba4444ToBmp(bytes, w.round(), h.round());

    costs = DateTime.now().difference(start);
    print("-----costs ${costs.toString()}");
    ////print(image.toString());
    return widget.Image.memory(
      bmp,
      width: double.infinity,
      height: double.infinity,
      fit: widget.BoxFit.fill,
    );
  }

  /// Destroys and releases the memory allocated for the library when is not
  /// longer used
  void dispose() {
    // closePage();
    // closeDocument();
    pdfium.FPDF_DestroyLibrary();
    allocator.free(config);
  }

  widget.Image RenderPageAsPtr(
    int page, {
    int? width,
    int? height,
    int backgroundColor = 268435455,
    double scale = 1,
    int rotate = 0,
    int flags = 0,
    bool flush = false,
    int pngLevel = 6,
  }) {
    //print('png render');
    _page = getPage(page);
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int 268435455
    final w = ((width ?? getPageWidth()) * scale).round();
    final h = ((height ?? getPageHeight()) * scale).round();
    print('w:${w},h:${h}');
    final bytes = renderPageAsBytes(
      w,
      h,
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    );
    ////print(image.toString());
    return widget.Image.memory(
      img.encodeBmp(image),
      fit: widget.BoxFit.fill,
      width: getPageWidth(),
      height: getPageHeight(),
    );
  }
}
