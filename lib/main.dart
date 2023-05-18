import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'pdf_render.dart';
import 'package:async/async.dart';

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
    if (this.mounted) {
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
    final cancel = await CancelableOperation.fromFuture(FetchPdf(),
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
      child: _isLoading ? CircularProgressIndicator() : _image!,
    );
  }
}

void main(List<String> args) async {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PdfReader',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: Home(),
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
          onPressed: () => _pressHomeBtn(context),
          child: Text('打开文件'),
        ),
      ),
    );
  }

  _pressHomeBtn(BuildContext context) async {
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

class ScrollControllerTestRouteState extends State<ScrollControllerTestRoute> {
  ScrollController _controller = ScrollController();
  bool showToTopBtn = false; //是否显示“返回到顶部”按钮
  double scale = 2;
  SimplePdfRender? _simplePdfRender;
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
            setState(
              () => pageInfo = value,
            )
          });
    });
    // pdfRender.loadDocumentFromPath(widget.path!);
    //监听滚动事件，打印滚动位置
    _controller.addListener(() {
      //print(_controller.offset); //打印滚动位置
      if (_controller.offset < 1000 && showToTopBtn) {
        setState(() {
          showToTopBtn = false;
        });
      } else if (_controller.offset >= 1000 && showToTopBtn == false) {
        setState(() {
          showToTopBtn = true;
        });
      }
    });
  }

  @override
  void dispose() {
    //为了避免内存泄露，需要调用_controller.dispose
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("滚动控制")),
      body: Scrollbar(
          controller: _controller,
          child: NotificationListener(
            onNotification: (ScrollNotification notification) {
              switch (notification.runtimeType) {
                case ScrollStartNotification:
                  //print('开始滚动');
                  break;
                case ScrollUpdateNotification:
                  //print('正在滚动');
                  break;
                case ScrollEndNotification:
                  //print('结束滚动');
                  break;
              }
              return true;
            },
            child: _simplePdfRender == null //检查代理是否初始化
                ? Center()
                : ListView.builder(
                    itemCount: pageInfo!.length,
                    controller: _controller,
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
                                width: pageInfo![index].width * scale,
                                height: pageInfo![index].height * scale,
                                child: PdfPageStateful(
                                  simplePdfRender: _simplePdfRender!,
                                  index: index,
                                  scale: 1,
                                ),
                              ),
                            )),
                      ));
                    }),
          )),
      floatingActionButton: !showToTopBtn
          ? null
          : FloatingActionButton(
              child: Icon(Icons.arrow_upward),
              onPressed: () {
                //返回到顶部时执行动画
                _controller.animateTo(
                  .0,
                  duration: Duration(milliseconds: 200),
                  curve: Curves.ease,
                );
              }),
    );
  }
}

class ScrollStatus extends StatefulWidget {
  @override
  _ScrollStatusState createState() => _ScrollStatusState();
}

class _ScrollStatusState extends State<ScrollStatus> {
  String message = "";

  _onStartScroll(ScrollMetrics metrics) {
    setState(() {
      message = "Scroll Start";
    });
  }

  _onUpdateScroll(ScrollMetrics metrics) {
    setState(() {
      message = "Scroll Update";
    });
  }

  _onEndScroll(ScrollMetrics metrics) {
    setState(() {
      message = "Scroll End";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Scroll Status"),
      ),
      body: Column(
        children: <Widget>[
          Container(
            height: 50.0,
            color: Colors.green,
            child: Center(
              child: Text(message),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollNotification) {
                if (scrollNotification is ScrollStartNotification) {
                  _onStartScroll(scrollNotification.metrics);
                } else if (scrollNotification is ScrollUpdateNotification) {
                  _onUpdateScroll(scrollNotification.metrics);
                } else if (scrollNotification is ScrollEndNotification) {
                  _onEndScroll(scrollNotification.metrics);
                }
                return true;
              },
              child: ListView.builder(
                itemCount: 30,
                itemBuilder: (context, index) {
                  return ListTile(title: Text("Index : $index"));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
