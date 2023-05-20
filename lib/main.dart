import 'dart:async';
import 'dart:ui' as ui;
import 'package:buffer_image/buffer_image.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfium_bindings/pdfium_bindings.dart';
import 'pdf_render.dart';
import 'package:async/async.dart';
import "dart:io";
import 'dart:ffi';
import 'rgba_image.dart';

class PdfPageStateful extends StatefulWidget {
  late SimplePdfRender simplePdfRender;
  late int index;
  late double scale;
  PdfPageStateful(
      {super.key,
      required this.simplePdfRender,
      required this.index,
      this.scale = 1});

  @override
  createState() => PdfPageStatefulState();
}

class PdfPageStatefulState extends State<PdfPageStateful> {
  Image? _image;
  Image? _cacheImage;
  Future<void> FetchPdf() async {
    print("start fetch");
    //_image =
    //    await widget.simplePdfRender.getImage(widget.index, widget.scale).first;
    _image = await widget.simplePdfRender
        .getImagebyPtr(widget.index, widget.scale * 1.5); // more clearly
    print(_image.toString());
    if (mounted) {
      setState(() {
        _cacheImage = _image;
        print(_image.toString());
      });
    }
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    FetchPdf();
  }

  @override
  void dispose() {
    // TODO: implement dispose

    if (CancelableOperation.fromFuture(FetchPdf()).isCanceled) {
      print('page Disposed');
    }
    super.dispose();
  }

  @override
  void deactivate() async {
    // TODO: implement deactivate
    print('page deactive');
    final cancel = CancelableOperation.fromFuture(FetchPdf(),
        onCancel: () => 'Future has been canceled');
    cancel.cancel();
    if (cancel.isCanceled) {
      print('page Disposed');
    }
    super.deactivate();
  }

  @override
  void initState() {
    super.initState();
    print("page create");
    FetchPdf();
  }

  @override
  Widget build(BuildContext context) {
    print('BUILD');
    return Center(
      child: _cacheImage == null
          ? const CircularProgressIndicator()
          : _cacheImage!,
    );
  }
}

void main(List<String> args) async {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PdfReader',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: const Home(),
  ));
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Center(
        child: TextButton(
          onPressed: () => _pressOpenBtn(context),
          child: const Text('Open Pdf'),
        ),
      ),
    );
  }

  _pressOpenBtn(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform
        .pickFiles(allowedExtensions: ['pdf'], type: FileType.custom);
    if (result != null) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => ScrollControllerTestRoute(
                path: result.paths.first!,
              )));
    }
  }
}

class ScrollControllerTestRoute extends StatefulWidget {
  String? path;

  ScrollControllerTestRoute({super.key, this.path});

  @override
  ScrollControllerTestRouteState createState() {
    return ScrollControllerTestRouteState();
  }
}

typedef _CallBack = void Function(Notification notification);

class ScrollControllerTestRouteState extends State<ScrollControllerTestRoute> {
  final ScrollController _controllerVertical = ScrollController();
  final ScrollController _controllerHorizontal = ScrollController();
  bool showToTopBtn = false; //是否显示“返回到顶部”按钮
  late String barTitle;
  double basicScale = 1.0; //基础放大比例(maxWidth = Screem Width)
  ValueNotifier<double> scale = ValueNotifier(1.0)
    ..addListener(() {}); // 页面放大比例 120%, 200% 之类的

  SimplePdfRender? _simplePdfRender;
  _CallBack? mouseNotification;
  List<ui.Size>? pageInfo;
  @override
  void initState() {
    super.initState();
    barTitle = widget.path!.split('\\').last.split('.').first; // get pdf name
    if (widget.path == null) {
      throw Exception('Can not get path');
    }

    SimplePdfRender.open(widget.path!).then((value) {
      _simplePdfRender = value;
      _simplePdfRender!.getPageInfo().first.then((value) => {
            setState(() {
              // get all pages size and max size
              pageInfo = value;
              if (pageInfo != null) {
                // make rendered page width the same as widget width
                basicScale =
                    MediaQuery.of(context).size.width / pageInfo!.last.width;
              }
            })
          });
    });
    // pdfRender.loadDocumentFromPath(widget.path!);
    //监听滚动事件，打印滚动位置
    _controllerVertical.addListener(() {
      //print(_controller.offset); //打印滚动位置
      if (_controllerVertical.offset < 1000 && showToTopBtn) {
        setState(() {
          showToTopBtn = false;
        });
      } else if (_controllerVertical.offset >= 1000 && showToTopBtn == false) {
        setState(() {
          showToTopBtn = true;
        });
      }
    });
  }

  @override
  void dispose() {
    //为了避免内存泄露，需要调用_controller.dispose
    _controllerVertical.dispose();
    _controllerHorizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(barTitle),
        actions: [
          IconButton(
              onPressed: () {
                setState(() {
                  scale.value = scale.value + 0.2;
                });
              },
              icon: Icon(Icons.add)),
          IconButton(
              onPressed: () {
                setState(() {
                  if (scale.value - 0.2 > 0.2) {
                    scale.value = scale.value - 0.2;
                  }
                });
              },
              icon: Icon(Icons.remove)),
          IconButton(
              onPressed: () {
                setState(() {
                  scale.value = 1.0;
                  basicScale = basicScale =
                      MediaQuery.of(context).size.width / pageInfo!.last.width;
                });
              },
              icon: Icon(Icons.fit_screen))
        ],
      ),
      body: _simplePdfRender == null //检查代理是否初始化
          ? null
          : Stack(
              children: [
                Scrollbar(
                  controller: _controllerHorizontal,
                  thumbVisibility: true,
                  child: Center(
                    child: SingleChildScrollView(
                      controller: _controllerHorizontal,
                      scrollDirection: Axis.horizontal,
                      child: Center(
                        child: SizedBox(
                          width: pageInfo!.last.width *
                              basicScale *
                              scale.value, //last is max size
                          child: NotificationListener(
                            onNotification: (Notification notification) {
                              if (_callBack != null) {
                                //print("listener:${notification.toString()}");
                                _callBack!(notification);
                              }
                              return false;
                            },
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: ListView.builder(
                                  itemCount:
                                      pageInfo!.length - 1, //last is max size
                                  controller: _controllerVertical,
                                  itemBuilder: (context, index) {
                                    return Center(
                                        child: Container(
                                      alignment: Alignment.topCenter,
                                      width: pageInfo![index].width *
                                          basicScale *
                                          scale.value,
                                      child: AspectRatio(
                                          aspectRatio: pageInfo![index].width /
                                              pageInfo![index].height,
                                          child: FittedBox(
                                            child: SizedBox(
                                              width: pageInfo![index].width *
                                                  basicScale *
                                                  scale.value,
                                              height: pageInfo![index].height *
                                                  basicScale *
                                                  scale.value,
                                              child: PdfPageStateful(
                                                simplePdfRender:
                                                    _simplePdfRender!,
                                                index: index,
                                                scale: basicScale * scale.value,
                                              ),
                                            ),
                                          )),
                                    ));
                                  }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  width: 8,
                  top: 0,
                  bottom: 0,
                  // https://github.com/flutter/flutter/issues/25652
                  // Scrollbar resizing and jumping
                  // hard to fix
                  child: Scrollbar(
                    thumbVisibility: true,
                    controller: _controllerVertical,
                    child: NotificationSender(
                      child: const Center(),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: !showToTopBtn
          ? null
          : FloatingActionButton(
              child: const Icon(Icons.arrow_upward),
              onPressed: () {
                //返回到顶部时执行动画
                _controllerVertical.animateTo(
                  .0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.ease,
                );
              }),
    );
  }
}

//
// cheat ScrollBar. send other widget's child's notification
//
_CallBack? _callBack;

class NotificationSender extends StatefulWidget {
  Widget child;
  NotificationSender({
    super.key,
    required this.child,
  });
  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return NotificationSenderState();
  }
}

class NotificationSenderState extends State<NotificationSender> {
  NotificationSenderState();
  @override
  void initState() {
    _callBack = (notification) {
      notification.dispatch(context);
    };
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
