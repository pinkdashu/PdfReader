import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'PdfRender.dart';
import 'package:async/async.dart';

// var pdfRender = new PdfRender();

// // void multiThread() {
// //   print('multiThread start');

// //   ReceivePort r1 = ReceivePort();
// //   SendPort p1 = r1.sendPort;

// //   Isolate.spawn(newThread, message);
// // }

// // void newThread(Map ) {
// //   print('newThread start');

// // }

// void _isolateMain(Map receive) async {
//   RootIsolateToken rootIsolateToken = receive['rootIsolateToken'];
//   ReceivePort r2 = ReceivePort();
//   SendPort p2 = r2.sendPort;
//   SendPort p1 = receive['sendPort'];
//   String path = receive['path'];
//   BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
//   PdfRender pdfRender = PdfRender();
//   pdfRender.loadDocumentFromPath(path);

//   //pdfRender.savePageAsPng('outPath.png');
//   p1.send(p2);
//   r2.listen((message) {
//     if (message is SendPort) {
//       print('双向通信成功');
//     }
//     if (message is int) {}
//     pdfRender.getPage(message as int);
//     pdfRender.RenderPageAsPng();
//   });
// }

// class IsolateConnector {
//   late ReceivePort r1;
//   late SendPort p2;

//   void startIsolate({String path = '1417.pdf'}) async {
//     r1 = ReceivePort();
//     RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
//     Map send = {
//       'rootIsolateToken': rootIsolateToken,
//       'sendPort': r1.sendPort,
//       'path': path
//     };
//     Isolate.spawn(_isolateMain, send);
//   }
//   Future<Image> getImage(int index)
//   {

//     r1.listen((message) {
//       if (message is SendPort) {
//         print('双向通信成功');
//         p2 = message;
//       }
//       if (message is Image) {
//         print('pdf Render succeed');
//         return
//       }
//     });

//   }
// }

// Future sendToReceive(SendPort port, msg) {
//   ReceivePort response = ReceivePort();
//   port.send([msg, response.sendPort]);
//   return response.first;
// }

// class PdfPage extends StatelessWidget {
//   const PdfPage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     // pdfRender.loadPage(index);
//     // TODO: implement build
//     return Image(
//       width: pdfRender.getPageWidth(),
//       height: pdfRender.getPageHeight(),
//       image: Image.memory(pdfRender.RenderPageAsPng(scale: 1)).image,
//       fit: BoxFit.fill,
//     );
//   }
// }

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
    //_image = await Image.memory(pdfRender.RenderPageAsPng());
    //await Future.delayed(const Duration(seconds: 1));
    //print('render succeed');
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
    return Container(
      child: Center(
        child: _isLoading ? CircularProgressIndicator() : _image!,
      ),
    );
  }
}

void main(List<String> args) async {
  runApp(MaterialApp(
    title: 'lazyLoading',
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
  SimplePdfRender? _simplePdfRender;
  List<Size>? pageInfo;
  @override
  void initState() {
    super.initState();
    // pdfRender = new PdfRender();
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
    // pdfRender.dispose();
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
                    //itemExtent: 50.0, //列表项高度固定时，显式指定高度是一个好习惯(性能消耗小)
                    controller: _controller,
                    itemBuilder: (context, index) {
                      // pdfRender.loadPage(index);
                      // print(pdfRender.getPageWidth().toString());
                      return Container(
                        alignment: Alignment.topCenter,
                        width: pageInfo![index].width,
                        height: pageInfo![index].height,
                        child: PdfPageStateful(
                          simplePdfRender: _simplePdfRender!,
                          index: index,
                          scale: 2,
                        ),
                      );
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

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MaterialScrollBehavior().copyWith(dragDevices: {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown
      }),
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: ScrollStatus(),
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
