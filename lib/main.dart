import 'dart:async';

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'pdf_render.dart';
import 'package:async/async.dart';
import "dart:io";
import 'package:fluttertoast/fluttertoast.dart';
import 'selectable_widget.dart';

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
    theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
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
        child: FloatingActionButton.extended(
          onPressed: () => _pressOpenBtn(context),
          icon: const Icon(Icons.add),
          label: const Text('打开PDF文件'),
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

class Scale {
  Scale(
      {this.basicScale = 1.0, pageScale = 1.0, required BuildContext context}) {
    _pageScale = ValueNotifier<double>(pageScale);
    _pageScale.addListener(() {
      _showToast();
      PdfTextBox.scale = value;
    });
    _fToast = FToast();
    _fToast.init(context);
  }

  // 基础放大比例(maxWidth = Screem Width)
  double basicScale;
  // 页面放大比例 120%, 200% 之类的
  set pageScale(double value) => _pageScale.value = value;
  double get pageScale => _pageScale.value;
  late ValueNotifier<double> _pageScale;
  double get value => basicScale * pageScale;

  late FToast _fToast;

  void _showToast() {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25.0), color: Colors.black54),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.aspect_ratio,
            color: Colors.white,
          ),
          const SizedBox(
            width: 24.0,
          ),
          Text(
            "${(pageScale * 100).toStringAsFixed(0)} %",
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
    _fToast.removeQueuedCustomToasts();
    _fToast.showToast(
        child: toast,
        gravity: ToastGravity.CENTER,
        toastDuration: const Duration(seconds: 1),
        fadeDuration: const Duration(milliseconds: 200));
  }
}

class ScrollControllerTestRouteState extends State<ScrollControllerTestRoute> {
  final ScrollController _controllerVertical = ScrollController();
  final ScrollController _controllerHorizontal = ScrollController();
  bool showToTopBtn = false; //是否显示“返回到顶部”按钮
  late String barTitle;
  late Scale scale;
  List<List<PdfTextBox>>? pdfTextBoxList;
  SimplePdfRender? _simplePdfRender;
  _CallBack? mouseNotification;
  List<ui.Size>? pageInfo;

  @override
  void initState() {
    // must contain
    super.initState();
    // initialize scale component
    scale = Scale(context: context);
    // get pdf name
    barTitle = widget.path!.split('\\').last.split('.').first; // get pdf name
    // initialize pdf render component
    if (widget.path == null) {
      throw Exception('Can not get path');
    }
    SimplePdfRender.open(widget.path!).then((value) {
      _simplePdfRender = value;
      _simplePdfRender!.getpageSize().first.then((value) => {
            setState(() {
              // get all pages size and max size
              pageInfo = value;

              if (pageInfo != null) {
                // make rendered page width the same as widget width
                scale.basicScale =
                    MediaQuery.of(context).size.width / pageInfo!.last.width;

                pdfTextBoxList = List<List<PdfTextBox>>.generate(
                    pageInfo!.length - 1, (index) => <PdfTextBox>[]);

                // _simplePdfRender!.getPdfTextBox(1, 1).first.then((value) => print(
                //     "----------------------${value.left.toString()}--${value.right.toString()}"));
              }
            })
          });
    });

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
                  scale.pageScale = scale.pageScale + 0.2;
                });
              },
              icon: const Icon(Icons.add)),
          IconButton(
              onPressed: scale.pageScale <= 0.21
                  ? null
                  : () {
                      setState(() {
                        if (scale.pageScale - 0.2 > 0.2) {
                          scale.pageScale = scale.pageScale - 0.2;
                        }
                      });
                    },
              icon: const Icon(Icons.remove)),
          IconButton(
              onPressed: () {
                setState(() {
                  scale.pageScale = 1.0;
                  scale.basicScale = scale.basicScale =
                      MediaQuery.of(context).size.width / pageInfo!.last.width;
                });
              },
              icon: const Icon(Icons.fit_screen)),
          PopupMenuButton(
              icon: const Icon(Icons.search),
              enabled: false,
              itemBuilder: (context) => [
                    PopupMenuItem(
                        child: TextFormField(
                      decoration: const InputDecoration(
                          hintText: "键入一个字词或页码", icon: Icon(Icons.search)),
                    ))
                  ]),
          PopupMenuButton(
              itemBuilder: (context) => [
                    PopupMenuItem(
                        child: IconButton(
                      onPressed: () => {
                        for (int i = 0; i < 40; i++)
                          {
                            _simplePdfRender!
                                .getPdfTextBox(0, i)
                                .first
                                .then((value) {
                              setState(() {
                                PdfTextBox.scale = scale.value;
                                pdfTextBoxList!.first.add(value);
                              });
                            })
                          }
                      },
                      icon: const Icon(Icons.abc),
                    ))
                  ]),
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
                              child: SelectionArea(
                                child: ListView.builder(
                                    itemCount:
                                        pageInfo!.length - 1, //last is max size
                                    controller: _controllerVertical,
                                    itemBuilder: (context, index) {
                                      return Center(
                                          child: Container(
                                        alignment: Alignment.topCenter,
                                        width: pageInfo![index].width *
                                            scale.value,
                                        child: SizedBox(
                                            width: pageInfo!.last.width *
                                                scale.value,
                                            height: pageInfo!.last.height *
                                                scale.value,
                                            child: Stack(children: [
                                              PdfPageStateful(
                                                simplePdfRender:
                                                    _simplePdfRender!,
                                                index: index,
                                                scale: scale.value,
                                              ),
                                              pdfTextBoxList == null
                                                  ? const Center()
                                                  : FittedBox(
                                                      child: SizedBox(
                                                        width: pageInfo![index]
                                                                .width *
                                                            scale.value,
                                                        height: pageInfo![index]
                                                                .height *
                                                            scale.value,
                                                        child:
                                                            CustomMultiChildLayout(
                                                          delegate:
                                                              MyMultiChildLayoutDelegate(
                                                                  pdfTextBoxList![
                                                                      index]),
                                                          children: <Widget>[
                                                            for (var box
                                                                in pdfTextBoxList![
                                                                    index])
                                                              LayoutId(
                                                                  id: box,
                                                                  child:
                                                                      MySelectableAdapter(
                                                                    child: SizedBox(
                                                                        height: box
                                                                            .height,
                                                                        width: box
                                                                            .width),
                                                                    widgetText:
                                                                        'aaa',
                                                                  ))
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                              pdfTextBoxList == null
                                                  ? const Center()
                                                  : CustomPaint(
                                                      painter: RectPainter(
                                                          pdfTextBoxList![
                                                              index]),
                                                      size: Size(
                                                          pageInfo![index]
                                                                  .width *
                                                              scale.value,
                                                          pageInfo![index]
                                                                  .height *
                                                              scale.value),
                                                    )
                                            ])),
                                      ));
                                    }),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  width:
                      Platform.isAndroid || Platform.isFuchsia || Platform.isIOS
                          ? 4
                          : 8,
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

class MyMultiChildLayoutDelegate extends MultiChildLayoutDelegate {
  MyMultiChildLayoutDelegate(this.boxs);

  List<PdfTextBox> boxs;

  @override
  void performLayout(ui.Size size) {
    for (var box in boxs) {
      print("${box.width.toString()}jjjjjjjjjjjjjjjj");
      positionChild(box, Offset(box.dx, box.dy));
      layoutChild(box, BoxConstraints.tight(Size(box.width, box.height)));
    }
  }

  @override
  bool shouldRelayout(covariant MultiChildLayoutDelegate oldDelegate) {
    return oldDelegate.hashCode != hashCode;
  }
}

class RectPainter extends CustomPainter {
  List<PdfTextBox> textBoxList;

  @override
  RectPainter(this.textBoxList);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    print("+++++++++++++++++++++++++++++++");

    for (var textBox in textBoxList) {
      final paint = Paint()
        ..color = const ui.Color.fromARGB(119, 255, 184, 77)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(textBox.dx, textBox.dy),
              width: textBox.width.roundToDouble(),
              height: textBox.height.roundToDouble()),
          paint);
      // Rect.fromLTRB(
      //     textBox.left, textBox.top, textBox.right, textBox.bottom),
      // paint);
    }
    // TODO: implement paint
  }

  @override
  bool shouldRepaint(covariant RectPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return listEquals(oldDelegate.textBoxList, textBoxList);
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
