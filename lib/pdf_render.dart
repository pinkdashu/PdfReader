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
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:pdfium_bindings/pdfium_bindings.dart';
import 'rgba_image.dart';
import 'package:charset/charset.dart';

enum _Codes {
  init,
  image,
  ack,
  pageSize,
  imagePtr,
  pageTextBox,
  pageTextBoxs,
  cancelRender
}

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
  final Queue<StreamController<Map>> _resultStreamPtr =
      Queue<StreamController<Map>>();
  final Queue<StreamController<PdfTextBox>> _resultPdfTextBox =
      Queue<StreamController<PdfTextBox>>();
  final Queue<StreamController<List<PdfTextBox>>> _resultPdfTextBoxs =
      Queue<StreamController<List<PdfTextBox>>>();

  late StreamController<List<ui.Size>> _resultPageSize;

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
    print("handleCommand  ${command.code}");
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
        // print("queue length:${_resultStream.length}");
        _resultStream.last.add(command.arg0 as widget.Image);
        _resultStream.removeLast().close();
        break;
      case _Codes.imagePtr:
        print("queue length:${_resultStreamPtr.length}");
        _resultStreamPtr.last.add(command.arg0 as Map);
        _resultStreamPtr.removeLast().close();
        getImagePtrCommandMap.remove(getImagePtrCommandQueue.removeLast());
        if (getImagePtrCommandQueue.isNotEmpty) {
          _sendPort.send(getImagePtrCommandQueue.last);
        }
        break;
      case _Codes.pageSize:
        _resultPageSize
          ..add(command.arg0 as List<ui.Size>)
          ..close();
        break;
      case _Codes.pageTextBox:
        _resultPdfTextBox
          ..last.add(command.arg0 as PdfTextBox)
          ..removeLast().close();
        break;
      case _Codes.pageTextBoxs:
        _resultPdfTextBoxs
          ..last.add(command.arg0 as List<PdfTextBox>)
          ..removeLast().close();
        break;
      case _Codes.cancelRender:
        break;
      default:
    }
  }

  Stream<widget.Image> getImage(int page, double scale) {
    //print("start get image");
    StreamController<widget.Image> resultStream =
        StreamController<widget.Image>();
    _resultStream.addFirst(resultStream); // queue
    _sendPort.send(_Command(_Codes.image, arg0: page, arg1: scale));
    return resultStream.stream;
  }

  Queue<_Command> getImagePtrCommandQueue = Queue<_Command>();
  Map<int, _Command> getImagePtrCommandMap = {};
  Map<_Command, StreamController<Map>> resultStreamPtrMap = {};
  Stream<Map> getImagePtr(int page, double scale) {
    print("start get Ptr");
    StreamController<Map> resultStreamPtr = StreamController<Map>();
    _resultStreamPtr.addFirst(resultStreamPtr); // queue
    var command = _Command(_Codes.imagePtr, arg0: page, arg1: scale);
    getImagePtrCommandQueue.addFirst(command);
    getImagePtrCommandMap[page] = command;
    resultStreamPtrMap[command] = resultStreamPtr;
    if (getImagePtrCommandQueue.length == 1) {
      _sendPort.send(getImagePtrCommandQueue.first);
    } else if (getImagePtrCommandQueue.length > 5) {}
    return resultStreamPtr.stream;
  }

  Future<Widget?> getImagebyPtr(int page, double scale) async {
    var addr = await getImagePtr(page, scale).first;
    if (addr.isEmpty) {
      print("zzzzzzzzzzzzzzz");
      return null;
    }
    var imagePtr = Pointer<Uint8>.fromAddress(addr['address']);
    var image = imagePtr.asTypedList(addr['width'] * addr['height'] * 4);
    var bmp = Rgba4444ToBmp(image, addr['width'] as int, addr['height'] as int);
    return Image.memory(
      bmp, width: double.infinity,
      height: double.infinity,
      gaplessPlayback:
          true, // prevent image flash while changing https://stackoverflow.com/questions/60125831/white-flash-when-image-is-repainted-flutter
      fit: widget.BoxFit.fill,
    );
  }

  Stream<List<ui.Size>> getpageSize() {
    _resultPageSize = StreamController<List<ui.Size>>();
    _sendPort.send(const _Command(_Codes.pageSize));
    return _resultPageSize.stream;
  }

  Stream<PdfTextBox> getPdfTextBox(int page, int index) {
    StreamController<PdfTextBox> resultPdfTextBox =
        StreamController<PdfTextBox>();
    _resultPdfTextBox.addFirst(resultPdfTextBox); // queue
    _sendPort.send(_Command(_Codes.pageTextBox, arg0: page, arg1: index));
    return resultPdfTextBox.stream;
  }

  Stream<List<PdfTextBox>> getPdfTextBoxs(int page, List<int> index) {
    StreamController<List<PdfTextBox>> resultPdfTextBoxs =
        StreamController<List<PdfTextBox>>();
    _resultPdfTextBoxs.addFirst(resultPdfTextBoxs); // queue
    _sendPort.send(_Command(_Codes.pageTextBoxs, arg0: page, arg1: index));
    return resultPdfTextBoxs.stream;
  }

  void cancelPdfRender(int page, double scale) {
    if (getImagePtrCommandQueue.contains(getImagePtrCommandMap[page])) {
      print('vvvvvvvvvv');
      resultStreamPtrMap[getImagePtrCommandMap[page]]!
        ..add({})
        ..close();
      _resultStreamPtr.remove(resultStreamPtrMap[getImagePtrCommandMap[page]]);
      getImagePtrCommandQueue.remove(getImagePtrCommandMap[page]);
    }
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
      print("listened");
      server._handleCommand(command).timeout(Duration.zero);
    });
  }

  Future<void> _handleCommand(_Command command) async {
    switch (command.code) {
      case _Codes.init:
        _path = command.arg0 as String;
        RootIsolateToken rootIsolateToken = command.arg1 as RootIsolateToken;
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
        _pdfRender = PdfRender();
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
        print("send image $page,costs ${costs.toString()}");
        _sendPort.send(_Command(_Codes.image, arg0: image));

      case _Codes.imagePtr:
        var page = command.arg0 as int;
        var scale = command.arg1 as double;
        var start = DateTime.now();
        Map image = _pdfRender.RenderPageAsPtr(page, scale: scale);
        var end = DateTime.now();
        var costs = end.difference(start);
        print("send image $page,costs ${costs.toString()}");
        _sendPort.send(_Command(_Codes.imagePtr, arg0: image));

      case _Codes.pageSize:
        var pageSize = _pdfRender.getPageSize();
        _sendPort.send(_Command(_Codes.pageSize, arg0: pageSize));

      case _Codes.pageTextBox:
        var page = command.arg0 as int;
        var index = command.arg1 as int;
        var textBox = _pdfRender.getPdfTextBox(page, index);
        // print(textBox.toString());
        _sendPort.send(_Command(_Codes.pageTextBox, arg0: textBox));

      case _Codes.pageTextBoxs:
        var page = command.arg0 as int;
        var index = command.arg1 as List<int>;

        var textBoxs = _pdfRender.getPdfTextBoxs(page, index);
        // print(textBoxs.toString());
        _sendPort.send(_Command(_Codes.pageTextBoxs, arg0: textBoxs));
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

  final Map<int, Pointer<fpdf_page_t__>?> _pageCache = {};
  final Map<Pointer<fpdf_page_t__>, double> _pageWidthCache = {};
  final Map<Pointer<fpdf_page_t__>, double> _pageHeightCache = {};
  final Map<Pointer<fpdf_page_t__>, Int8List> _pagePngCache = {};

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

  Pointer<FS_SIZEF> size = malloc.allocate<FS_SIZEF>(sizeOf<FS_SIZEF>());

  List<ui.Size> getPageSize() {
    int count = getPageCount();
    List<ui.Size> pageSize = [];
    var start = DateTime.now();
    double maxWidth = 0, maxHeight = 0;

    for (var i = 0; i < count; i++) {
      pdfium.FPDF_GetPageSizeByIndexF(_document!, i, size);
      if (maxWidth < size[0].width) {
        maxWidth = size[0].width;
      }
      if (maxHeight < size[0].height) {
        maxHeight = size[0].height;
      }
      pageSize.add(ui.Size(size[0].width, size[0].height));
    }
    pageSize.add(ui.Size(maxWidth, maxHeight));
    // print("get page costs ${DateTime.now().difference(start)}");
    return pageSize;
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
    buffer = pdfium.FPDFBitmap_GetBuffer(bitmap!).cast();
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
    final _page = getPage(page);
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
    print('w:$w,h:$h');
    var start = DateTime.now();
    final bytes = renderPageAsBytes(
      w.round(),
      h.round(),
      backgroundColor: backgroundColor,
      rotate: rotate,
      flags: flags,
    );
    var costs = DateTime.now().difference(start);
    // print("-----costs ${costs.toString()}");

    var bmp = Rgba4444ToBmp(bytes, w.round(), h.round());

    costs = DateTime.now().difference(start);
    // print("-----costs ${costs.toString()}");
    ////print(image.toString());
    return widget.Image.memory(
      bmp,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback:
          true, // prevent image flash while changing https://stackoverflow.com/questions/60125831/white-flash-when-image-is-repainted-flutter
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

  Map RenderPageAsPtr(
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
    if (_page == nullptr) {
      throw PdfiumException(message: 'Page not load');
    }
    // var backgroundStr = "FFFFFFFF"; // as int
    _page = getPage(page);
    final w = ((width ?? getPageWidth()) * scale).round();
    final h = ((width ?? getPageWidth()) * scale).round();
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
    buffer = pdfium.FPDFBitmap_GetBuffer(bitmap!).cast();
    Map pagePtr = {};
    pagePtr['address'] = buffer!.address;
    pagePtr['width'] = w;
    pagePtr['height'] = h;
    return pagePtr;
  }

  //Pointer<FS_SIZEF> size = malloc.allocate<FS_SIZEF>(sizeOf<FS_SIZEF>());
  late Pointer<Double> left, right, bottom, top;
  late Pointer<UnsignedShort> text;
  // fpdf_text
  PdfTextBox getPdfTextBox(int page, int index) {
    left = allocator<Double>();
    right = allocator<Double>();
    bottom = allocator<Double>();
    top = allocator<Double>();
    text = allocator<UnsignedShort>();
    var _page = getPage(page);
    var textPage = pdfium.FPDFText_LoadPage(_page);
    var height = pdfium.FPDF_GetPageHeight(_page);
    pdfium.FPDFText_GetCharBox(textPage, index, left, right, bottom, top);

    return PdfTextBox(left[0], right[0], height - bottom[0],
        height - top[0]); // convert page coordinate
  }

  List<PdfTextBox> getPdfTextBoxs(int page, List<int> index) {
    left = allocator<Double>();
    right = allocator<Double>();
    bottom = allocator<Double>();
    top = allocator<Double>();

    var _page = getPage(page);
    var textPage = pdfium.FPDFText_LoadPage(_page);
    var height = pdfium.FPDF_GetPageHeight(_page);
    var count = pdfium.FPDFText_CountChars(textPage);
    text = allocator<UnsignedShort>(count * 2);

    pdfium.FPDFText_GetText(textPage, 0, count, text);
    var textList = String.fromCharCodes(text.cast<Uint16>().asTypedList(count));
    print("==============================${textList}");

    List<PdfTextBox> pdfTextBox = [];
    if (index.isEmpty) {
      for (var i = 0; i < count; i++) {
        pdfium.FPDFText_GetCharBox(textPage, i, left, right, bottom, top);
        pdfTextBox.add(PdfTextBox(
            left[0], right[0], height - bottom[0], height - top[0],
            text: textList[i])); // convert page coordinate
      }
    } else {
      for (var i in index) {
        pdfium.FPDFText_GetCharBox(textPage, i, left, right, bottom, top);
        pdfTextBox.add(PdfTextBox(left[0], right[0], height - bottom[0],
            height - top[0])); // convert page coordinate
      }
    }

    return pdfTextBox;
  }
}

class PdfTextBox {
  @override
  String toString() {
    return "PdfTextBox[text:$text,left:$left,rigth:$right,bottom:$bottom,top:$top,width:$width,height:$height]";
  }

  PdfTextBox(this._left, this._right, this._bottom, this._top,
      {this.text = ''});
  static double scale = 1;
  String text;
  double _left, _right, _bottom, _top;
  double get left => _left * scale;
  double get right => _right * scale;
  double get bottom => _bottom * scale;
  double get top => _top * scale;
  double get height => (_bottom - _top) * scale;
  double get width => (_right - _left) * scale;
  double get dx => (left + right) / 2;
  double get dy => (top + bottom) / 2;
}
