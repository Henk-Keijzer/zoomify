The Zoomify widget allows you to display Zoomify and Deep Zoom Image (DZI) gigapixel 
images without the need to download the whole image at once. The user can zoom in/out 
and pan around and the necessary 256x256 tiles are downloaded on the fly.

Create a Zoomify image using the 'Zoomify Free Converter.exe' for Windows (download from
https://download.cnet.com/zoomify-free/3000-10248_4-77422171.html), or MacOS (download from 
https://download.cnet.com/zoomify-free/3000-10248_4-77422654.html).
Upload the folder containing the ImageProperties.xml and the TileGroup folders 
to your server and refer to that folder in the Zoomify widget.

Create a DZI image using the Zoomara app from the Microsoft Store or use any of the scripts
listed on https://openseadragon.github.io/examples/creating-zooming-images/
Note that the folder in which the tiles are created must contain a folder named 'image_files' and 
a file called 'image.xyz', where xyz is either 'xml' or 'dzi' for an xml formatted description
of the image, 'json' or 'jsonp' for a json formatted description. For further details see
https://openseadragon.github.io/examples/tilesource-dzi/

## Features

Zoom in/out and pan using gestures, mouse wheel, or keyboard.
Callback functions for onImageReady, onChange an onTap. 
Controller functions for programmatically zooming, panning and reset.

## Getting started

Install the package using `flutter pub add zoomify` and import it in your flutter dart app.

## Usage

Minimum example: 

	import 'package:flutter/material.dart';
	import 'package:zoomify/zoomify.dart';

	void main() => runApp(MyApp());

	class MyApp extends StatefulWidget {
	  const MyApp({super.key});

	  @override
	  MyAppState createState() => MyAppState();
	}

	class MyAppState extends State<MyApp> with WidgetsBindingObserver {
	  static const String folderUrl = '<your folder url here>';
	  static const photoTitle = '<your title here>';

	  @override
	  Widget build(BuildContext context) {
		return MaterialApp(
			home: Scaffold(
				appBar: AppBar(backgroundColor: Colors.black, title: Text(photoTitle, style: TextStyle(color: Colors.white))),
				body: Zoomify(baseUrl: folderUrl)));
	  }
	}

See Git for an example with all possible options, including callbacks and controller functions.

## Additional information

Suggestions for improvement are welcome.
