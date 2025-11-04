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
  late double _maxZoomLevel;
  late Size _size;
  ZoomifyController zoomifyController = ZoomifyController();

  //static const String folderUrl = 'https://kaartdekaag1933.zeilvaartwarmond.nl/kaartderkagerplassen-1933';
  //static const String photoTitle = 'Kaart der Kagerplassen, Uitgave 1933';
  static const String folderUrl = 'https://chaerte.zeilvaartwarmond.nl/Zonnestraal';
  static const String photoTitle = 'Zonnestraal, Hilversum';

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
              IconButton(onPressed: () => panTo(), icon: Icon(Icons.location_pin, color: Colors.white))
            ]),
            body: Zoomify(
                baseUrl: folderUrl,
                backgroundColor: Colors.black87,
                showGrid: false,
                showZoomButtons: true,
                showPanButtons: true,
                showResetButton: true,
                buttonPosition: Alignment.centerRight,
                buttonColor: Colors.white,
                onImageReady: (maxSize, maxZoom) => handleImageReady(maxSize, maxZoom),
                onChange: (zoomLevel, offset, size) => handleChange(zoomLevel, offset, size),
                onTap: (imageOffset, windowOffset) => handleTap(imageOffset, windowOffset),
                animationDuration: Duration(milliseconds: 500),
                animationCurve: Curves.easeOut,
                animationSync: false,
                interactive: true,
                fitImage: true,
                controller: zoomifyController)));
  }

  void handleImageReady(Size maxSize, int maxZoom) {
    debugPrint('max image size: (${maxSize.width}, ${maxSize.height}), max zoom level: $maxZoom');
    _maxZoomLevel = maxZoom.toDouble();
    _size = maxSize;
  }

  void handleChange(double zoom, Offset offset, Size size) {
    debugPrint('current zoom level: $zoom, offset: (${offset.dx}, ${offset.dy}), current image size: (${size.width}, ${size.height})');
  }

  void handleTap(Offset imageOffset, Offset windowOffset) {
    debugPrint('tap on image offset: (${imageOffset.dx}, ${imageOffset.dy}), window offset: (${windowOffset.dx}, ${windowOffset.dy})');
    zoomifyController.animateZoomAndPan(panTo: imageOffset, zoomLevel: _maxZoomLevel - 1);
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

  void panTo() {
    zoomifyController.zoomAndPan(zoomLevel: _maxZoomLevel, panTo: Offset(_size.width / 4, _size.height / 4));
  }
}
