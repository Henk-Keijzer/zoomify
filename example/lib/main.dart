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
  ZoomifyController zoomifyController = ZoomifyController();

//  static const String folderUrl = 'https://kaartdekaag1933.zeilvaartwarmond.nl/kaartderkagerplassen-1933';
//  static const photoTitle = 'Kaart der Kagerplassen, Uitgave 1933';
  static const String folderUrl = 'https://chaerte.zeilvaartwarmond.nl/Warmond_J_Douw_1667';
  static const photoTitle = 'Chaerte vande vrye Heerlickheydt Warmondt, Johannes Douw, 1667';

  GlobalKey zoomifyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    windowWidth = MediaQuery.of(context).size.width;
    windowHeight = MediaQuery.of(context).size.height;
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            appBar: AppBar(backgroundColor: Colors.black87, title: Text(photoTitle, style: TextStyle(color: Colors.white)), actions: [
              IconButton(onPressed: () => zoomInOut(0.5), icon: Icon(Icons.add_box, color: Colors.white)),
              IconButton(onPressed: () => zoomInOut(-0.5), icon: Icon(Icons.indeterminate_check_box, color: Colors.white)),
              IconButton(onPressed: () => panUp(), icon: Icon(Icons.arrow_upward, color: Colors.white)),
              IconButton(onPressed: () => panDown(), icon: Icon(Icons.arrow_downward, color: Colors.white)),
              IconButton(onPressed: () => panLeft(), icon: Icon(Icons.arrow_back, color: Colors.white)),
              IconButton(onPressed: () => panRight(), icon: Icon(Icons.arrow_forward, color: Colors.white)),
              IconButton(onPressed: () => reset(), icon: Icon(Icons.fullscreen_exit, color: Colors.white)),
            ]),
            body: Zoomify(
                key: zoomifyKey,
                baseUrl: folderUrl,
                backgroundColor: Colors.black87,
                showGrid: false,
                showZoomButtons: true,
                zoomButtonPosition: Alignment.centerRight,
                zoomButtonColor: Colors.white,
                onChange: (zoomLevel, offset, size) => handleChange(zoomLevel, offset, size),
                onImageReady: (size, maxZoom) => handleImageReady(size, maxZoom),
                onTap: (tapOffset) => handleTap(tapOffset),
                animationDuration: Duration(milliseconds: 500),
                animationCurve: Curves.easeOut,
                animationSync: false,
                controller: zoomifyController)));
  }

  void handleImageReady(Size size, int maxZoom) {
    debugPrint('max image size: $size, max zoom level: $maxZoom');
  }

  void handleChange(double zoom, Offset offset, Size size) {
    debugPrint('current zoom level: $zoom, offset: $offset, current image size: $size');
  }

  void handleTap(Offset tapOffset) {
    debugPrint('tap offset: $tapOffset');
  }

  //
  // Change zoom and pan programmatically. Instead of animateZoomAndPan, you can also use zoomAndPan for non-animated
  // zooming and panning. Set the optional parameter sync to true to trigger the onChange callback function each animation frame.
  // In principle you can combine pan info (panOffset) and zoom info (zoomLevel and zoomCenter) in one call
  //

  void zoomInOut(zoomLevelDelta) {
    zoomifyController.animateZoomAndPan(
        zoomLevel: zoomifyController.getZoomLevel() + zoomLevelDelta, zoomCenter: Offset(windowWidth / 2, windowHeight / 2));
  }

  void panUp() {
    zoomifyController.animateZoomAndPan(panOffset: Offset(0, -100));
  }

  void panDown() {
    zoomifyController.animateZoomAndPan(panOffset: Offset(0, 100));
  }

  void panLeft() {
    zoomifyController.animateZoomAndPan(panOffset: Offset(-100, 0));
  }

  void panRight() {
    zoomifyController.animateZoomAndPan(panOffset: Offset(100, 0));
  }

  void reset() {
    zoomifyController.reset();
  }
}
