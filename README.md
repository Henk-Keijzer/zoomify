The Zoomify widget allows you to display gigapixel images without de need to 
download the whole image at once. The user can zoom in/out and pan around and
the necessary 256x256 tiles are downloaded on the fly.

Create a zoomified image using the 'Zoomify Free Converter.exe' for Windows (download from
https://download.cnet.com/zoomify-free/3000-10248_4-77422171.html).
Upload the folder containing the ImageProperties.xml and the TileGroup folders 
to your server and refer to that folder in the Zoomify widget.

## Features

Zoom in/out and pan using gestures, mouse wheel, or keyboard.
Zoom in/out and pan programmatically
Callback functions for onChange and onImageReady

## Getting started

Install the package using `flutter pub add zoomify` and import it in your dart app.

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
	  late ZoomifyState zoomifyState;
	  double currentScale = 1;

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
	  // Change zoom and pan programmatically. Instead of state.animateZoomAndPan, you can also use state.zoomAndPan
	  void zoomIn(factor) {
		// note: zoomcenter is set to the center of the screen
		dynamic state = zoomifyKey.currentState;
		state.animateZoomAndPan(scaleDelta: factor * currentScale, zoomCenter: Offset(windowWidth / 2, windowHeight / 2));
	  }

	  void zoomOut(factor) {
		// note zoomcenter is set to the top-left corner
		dynamic state = zoomifyKey.currentState;
		state.zoomAndPan(scaleDelta: -factor * currentScale, zoomCenter: Offset.zero);
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
		state.animateZoomAndPan(panOffset: Offset(-100, 0));
	  }

	  void panRight() {
		dynamic state = zoomifyKey.currentState;
		state.animateZoomAndPan(panOffset: Offset(100, 0));
	  }

	  void reset() {
		dynamic state = zoomifyKey.currentState;
		state.reset();
	  }
	}


## Additional information


