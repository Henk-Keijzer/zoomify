import 'package:flutter/material.dart';
import 'package:zoomify/zoomify.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const String folderUrl =
      'https://kaartdekaag1933.zeilvaartwarmond.nl/kaartderkagerplassen-1933';
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
                zoomButtonPosition: Alignment.centerRight,
                zoomButtonColor: Colors.white)));
  }
}
