<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

The Zoomify widget allows you to display gigapixel images without de need to 
download the whole image at once. The user can zoom in/out and pan around and
the necessary 256x256 tiles are downloaded on the fly.

Create a zoomified image using the 'Zoomify Free Converter.exe' for Windows (download from
https://download.cnet.com/zoomify-free/3000-10248_4-77422171.html).
Upload the folder containing the ImageProperties.xml and the TileGroup folders 
to your server and refer to that folder in the Zoomify widget.

## Features

Zoom in/out and pan using gestures, mouse wheel, or keyboard.

## Getting started

Install the package using `flutter pub add zoomify` and import it in your dart app.

## Usage

    import 'package:flutter/material.dart';
    import 'package:flutter/zoomify.dart';
    
    void main() => runApp(MyApp());
    
    class MyApp extends StatelessWidget {
        const MyApp({super.key});

        static const String folderUrl = 'https://kaartdekaag1933.zeilvaartwarmond.nl/kaartderkagerplassen-1933';
        static const photoTitle = 'Kaart der Kagerplassen, Uitgave 1933';  

        @override
        Widget build(BuildContext context) {
            return MaterialApp(
                debugShowCheckedModeBanner: false,
                    home: Scaffold(
                        appBar: AppBar(
                            toolbarHeight: 30, 
                            backgroundColor: Colors.black, 
                            title: Text(photoTitle, style: TextStyle(color: Colors.white))),
                        body: Zoomify(
                            baseUrl: folderUrl,
                            backgroundColor: Colors.black,
                            showGrid: false,
                            showZoomButtons: true,
                            zoomButtonPosition: Alignment.bottomLeft,
                            zoomButtonColor: Colors.white)));
        }
    }


## Additional information


