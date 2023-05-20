import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'pdf_render.dart';
import 'package:async/async.dart';
import "dart:io";

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
  bool _isLoading = true;
  Image? _image;
  Future<void> FetchPdf() async {
    print("start fetch");
    _image =
        await widget.simplePdfRender.getImage(widget.index, widget.scale).first;
    print(_image.toString());
    if (mounted) {
      setState(() {
        print(_image.toString());
        _isLoading = false;
      });
    }
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
      child: _isLoading ? const CircularProgressIndicator() : _image!,
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
  String barTitle = "Loading";
  double scale = 1;
  SimplePdfRender? _simplePdfRender;
  _CallBack? mouseNotification;
  List<Size>? pageInfo;
  @override
  void initState() {
    super.initState();
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
                scale =
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
      appBar: AppBar(title: Text(barTitle)),
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
                          width:
                              pageInfo!.last.width * scale, //last is max size
                          child: NotificationListener(
                            onNotification: (Notification notification) {
                              if (_callBack != null) {
                                print("listener:${notification.toString()}");
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
                                      width: pageInfo![index].width * scale,
                                      child: AspectRatio(
                                          aspectRatio: pageInfo![index].width /
                                              pageInfo![index].height,
                                          child: FittedBox(
                                            child: SizedBox(
                                              width: pageInfo![index].width *
                                                  scale,
                                              height: pageInfo![index].height *
                                                  scale,
                                              child: PdfPageStateful(
                                                simplePdfRender:
                                                    _simplePdfRender!,
                                                index: index,
                                                scale: scale,
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
