The Zoomify widget allows you to display gigapixel images without de need to 
download the whole image at once. The user can zoom in/out and pan around and
the necessary 256x256 tiles are downloaded on the fly.

Create a zoomified image using the 'Zoomify Free Converter.exe' for Windows (download from
https://download.cnet.com/zoomify-free/3000-10248_4-77422171.html).
Upload the folder containing the ImageProperties.xml and the TileGroup folders 
to your server and refer to that folder in the Zoomify widget.

## Features

Zoom in/out and pan using gestures, mouse wheel, or keyboard.
Callback functions for onImageReady, onChange an onTap. 
Controller functions for programmatically zooming, panning and reset.

## Getting started

Install the package using `flutter pub add zoomify` and import it in your flutter dart app.

## Usage

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
	  late double maxZoomLevel;
	  late Size maxImageSize;
      ZoomifyController zoomifyController = ZoomifyController();

	  static const String folderUrl = '<your folder url here>';
	  static const photoTitle = '<your title here>';

	  GlobalKey zoomifyKey = GlobalKey();

	  @override
	  Widget build(BuildContext context) {
		windowWidth = MediaQuery.of(context).size.width;
		windowHeight = MediaQuery.of(context).size.height;
		return MaterialApp(
			debugShowCheckedModeBanner: false,
			home: Scaffold(
				appBar: AppBar(backgroundColor: Colors.black, title: Text(photoTitle, style: TextStyle(color: Colors.white)), actions: [
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
					backgroundColor: Colors.black,
					showGrid: true,
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
		debugPrint('imageWidth: ${size.width}, imageHeight: ${size.height}, maxZoomLevel: $maxZoom');
	  }

	  void handleChange(double zoom, Offset offset, Size size) {
		debugPrint('zoomLevel: $zoom, horOffset: ${offset.dx}, '
			'verOffset: ${offset.dy}, imageWidth: ${size.width}, imageHeight: ${size.height}');
	  }

	  void handleTap(Offset tapOffset) {
		debugPrint('tapOffset: $tapOffset');
	  }

	  //
	  // Change zoom and pan programmatically. Instead of animateZoomAndPan, you can also use zoomAndPan for non-animated
	  // zooming and panning. Set the optional parameter sync to true to trigger the onChange callback function each animation frame.
	  // In principle you can combine pan info and zoom info in one call
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


## Additional information


