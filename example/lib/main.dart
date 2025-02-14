import 'package:flutter/material.dart';
import 'package:zoomify/zoomify.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late double windowWidth;
  late double windowHeight;
  late ZoomifyState zoomifyState;
  double currentScale = 1;

//  static const String folderUrl = 'https://kaartdekaag1933.zeilvaartwarmond.nl/kaartderkagerplassen-1933';
  static const String folderUrl = 'https://chaerte.zeilvaartwarmond.nl/Warmond_J_Douw_1667';
//  static const photoTitle = 'Kaart der Kagerplassen, Uitgave 1933';
  static const photoTitle = 'Chaerte vande vrye Heerlickheydt Warmondt, Johannes Douw, 1667';

  GlobalKey zoomifyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    windowWidth = MediaQuery.of(context).size.width;
    windowHeight = MediaQuery.of(context).size.height;
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            appBar: AppBar(backgroundColor: Colors.black, title: Text(photoTitle, style: TextStyle(color: Colors.white)), actions: [
              IconButton(onPressed: () => zoomIn(2.0), icon: Icon(Icons.add_box, color: Colors.white)),
              IconButton(onPressed: () => zoomOut(0.5), icon: Icon(Icons.indeterminate_check_box, color: Colors.white)),
              IconButton(onPressed: () => panUp(), icon: Icon(Icons.arrow_upward, color: Colors.white)),
              IconButton(onPressed: () => panDown(), icon: Icon(Icons.arrow_downward, color: Colors.white)),
              IconButton(onPressed: () => panLeft(), icon: Icon(Icons.arrow_back, color: Colors.white)),
              IconButton(onPressed: () => panRight(), icon: Icon(Icons.arrow_forward, color: Colors.white)),
              IconButton(onPressed: () => reset(), icon: Icon(Icons.fullscreen_exit, color: Colors.white)),
            ]),
            body: Zoomify(
                key: zoomifyKey,
                baseUrl: folderUrl,
                backgroundColor: Colors.black,
                showGrid: false,
                showZoomButtons: true,
                zoomButtonPosition: Alignment.centerRight,
                zoomButtonColor: Colors.white,
                onChange: (scale, offset) => handleChange(scale, offset),
                onImageReady: (width, height, zoomLevels) => handleImageReady(width, height, zoomLevels),
                animationDuration: Duration(milliseconds: 500),
                animationCurve: Curves.easeOut)));
  }

  void handleImageReady(int width, int height, int zoomLevels) {
    debugPrint('imageWidth: $width, imageHeight: $height, zoomLevels: $zoomLevels');
  }

  void handleChange(double scale, Offset offset) {
    debugPrint('scale: $scale, horOffset: ${offset.dx}, verOffset: ${offset.dy}');
    currentScale = scale;
  }

  //
  // Change zoom and pan programmatically. Instead of animateZoomAndPan, you can also use zoomAndPan
  void zoomIn(factor) {
    // note: zoomcenter is set to the center of the screen
    dynamic state = zoomifyKey.currentState;
    state.animateZoomAndPan(scaleDelta: factor * currentScale, zoomCenter: Offset(windowWidth / 2, windowHeight / 2));
  }

  void zoomOut(factor) {
    // note zoomcenter is set to the top-left corner
    dynamic state = zoomifyKey.currentState;
    state.zoomAndPan(scaleDelta: -factor * currentScale, zoomCenter: Offset.zero); // animated zoom out
  }

  void panUp() {
    dynamic state = zoomifyKey.currentState;
    state.animateZoomAndPan(panOffset: Offset(0, -100));
  }

  void panDown() {
    dynamic state = zoomifyKey.currentState;
    state.animateZoomAndPan(panOffset: Offset(0, 100));
  }

  void panLeft() {
    dynamic state = zoomifyKey.currentState;
    state.zoomAndPan(panOffset: Offset(-100, 0));
  }

  void panRight() {
    dynamic state = zoomifyKey.currentState;
    state.zoomAndPan(panOffset: Offset(100, 0));
  }

  void reset() {
    dynamic state = zoomifyKey.currentState;
    state.reset();
  }
}
