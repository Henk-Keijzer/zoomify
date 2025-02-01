import 'package:flutter/material.dart';
import 'package:zoomify/zoomify.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            appBar: AppBar(toolbarHeight: 30, title: Text('Zoomify Image')),
            body: Zoomify(
                baseUrl: 'https://chaerte.zeilvaartwarmond.nl/P2012368',
                backgroundColor: Colors.black38,
                showGrid: true,
                showZoomButtons: true,
                zoomButtonPosition: Alignment.bottomLeft,
                zoomButtonColor: Colors.red)));
  }
}
