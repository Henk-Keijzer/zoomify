library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_network_image/flutter_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:xml/xml.dart';

class Zoomify extends StatefulWidget {
  /// the url of the folder containing the zoomified image. i.e https://www.example.com/imagefolder
  final String baseUrl;

  /// the background color of the image.
  final Color backgroundColor;

  /// show zoombuttons
  final bool showZoomButtons;

  /// zoombutton position
  final Alignment zoomButtonPosition;

  /// zoombutton color
  final Color zoomButtonColor;

  /// shows the tilegrid, default false
  final bool showGrid;

  const Zoomify(
      {super.key,
      required this.baseUrl,
      this.backgroundColor = Colors.black12,
      this.showZoomButtons = false,
      this.zoomButtonPosition = Alignment.bottomRight,
      this.zoomButtonColor = Colors.white,
      this.showGrid = false});

  @override
  ZoomifyState createState() => ZoomifyState();
}

class ZoomifyState extends State<Zoomify> {
  double _windowWidth = 0;
  double _windowHeight = 0;
  int _tileSize = 256;
  int _zoomLevel = -1;
  double _scaleFactor = 1.0;
  double _horOffset = 0;
  double _verOffset = 0;
  List<Map<String, dynamic>> _zoomRowCols = [];
  Map<String, int> _tileGroupMapping = {};
  bool _imageDataReady = false;
  int _imageWidth = 0;
  int _imageHeight = 0;
  double _scaleStart = 1;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadImageProperties();
  }

  @override
  void didUpdateWidget(Zoomify oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) {
      _tileSize = 256;
      _zoomLevel = -1;
      _scaleFactor = 1.0;
      _horOffset = 0;
      _verOffset = 0;
      _zoomRowCols = [];
      _tileGroupMapping = {};
      _imageDataReady = false;
      _imageWidth = 0;
      _imageHeight = 0;
      _scaleStart = 1;
      _loadImageProperties();
    }
  }

  Future<void> _loadImageProperties() async {
    // first get the essentials from the ImageProperties.xml
    final response = await http.get(Uri.parse('${widget.baseUrl}/ImageProperties.xml'));
    if (response.statusCode == 200) {
      final attributes = XmlDocument.parse(response.body).getElement("IMAGE_PROPERTIES")?.attributes ?? [];
      for (final attribute in attributes) {
        switch (attribute.name.toString()) {
          case 'WIDTH':
            _imageWidth = int.parse(attribute.value);
          case 'HEIGHT':
            _imageHeight = int.parse(attribute.value);
          case 'TILESIZE':
            _tileSize = int.parse(attribute.value);
        }
      }
      // now make a list with the number of rows, number of colums, image widths and image heights per zoomlevel (in reverse order, i.e
      // zoomlevel 0 is the smallest image, fitting in a single tile: 0-0-0.jpg)
      var calcWidth = _imageWidth;
      var calcHeight = _imageHeight;
      var tiles = 2; // any value > 1
      while (tiles > 1) {
        var rows = (calcHeight / _tileSize).ceil();
        var cols = (calcWidth / _tileSize).ceil();
        _zoomRowCols.insert(0, {'rows': rows, 'cols': cols, 'width': calcWidth, 'height': calcHeight});
        calcWidth = (calcWidth / 2).floor();
        calcHeight = (calcHeight / 2).floor();
        tiles = rows * cols;
      }
      // finally make a Map with the filename as string and as value the tilegroup number
      tiles = 0;
      var tileGroupNumber = -1;
      for (var z = 0; z < _zoomRowCols.length; z++) {
        for (var r = 0; r < _zoomRowCols[z]['rows']; r++) {
          for (var c = 0; c < _zoomRowCols[z]['cols']; c++) {
            if (tiles++ % _tileSize == 0) tileGroupNumber++;
            _tileGroupMapping.addAll({'$z-$c-$r.jpg': tileGroupNumber});
          }
        }
      }
      _imageDataReady = true;
      setState(() {});
    } else {
      throw Exception('Failed to load image properties');
    }
  }

  @override
  Widget build(BuildContext context) {
    FocusScope.of(context).requestFocus(_focusNode);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      _windowWidth = constraints.maxWidth;
      _windowHeight = constraints.maxHeight;
      if (_imageDataReady && _zoomLevel == -1) _setInitialImageData();
      return Container(
          color: widget.backgroundColor,
          child: Stack(children: [
            Listener(
                // listen to mousewheel scrolls
                onPointerSignal: (pointerSignal) => setState(() => _scrollZoomPan(pointerSignal)),
                child: KeyboardListener(
                    focusNode: _focusNode,
                    onKeyEvent: (event) => setState(() => _handleKeyEvent(event)),
                    child: GestureDetector(
                        onScaleUpdate: (scaleDetails) => setState(() => _handleGestures(scaleDetails)),
                        onScaleStart: (_) => _scaleStart = 1,
                        onScaleEnd: (_) => _scaleStart = 1,
                        onDoubleTap: () => setState(() => _scrollZoomPan(
                            PointerScrollEvent(position: Offset(_windowWidth / 2, _windowHeight / 2), scrollDelta: Offset(0.0, -51.0)))),
                        child: _zoomifyImage()))),
            if (widget.showZoomButtons)
              Container(
                  alignment: widget.zoomButtonPosition,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: () => setState(() => _scrollZoomPan(
                            PointerScrollEvent(position: Offset(_windowWidth / 2, _windowHeight / 2), scrollDelta: Offset(0.0, -51.0)))),
                        icon: Icon(Icons.add_box, color: widget.zoomButtonColor)),
                    IconButton(
                        onPressed: () => setState(() => _scrollZoomPan(
                            PointerScrollEvent(position: Offset(_windowWidth / 2, _windowHeight / 2), scrollDelta: Offset(0.0, 51.0)))),
                        icon: Icon(Icons.indeterminate_check_box, color: widget.zoomButtonColor))
                  ]))
          ]));
    });
  }

  Widget _zoomifyImage() {
    if (_imageDataReady && _zoomLevel > -1) {
      _zoomLevel = _zoomLevel.clamp(0, _zoomRowCols.length - 1);
      _scaleFactor = _scaleFactor.clamp(0.5, 1.0);
      final rows = _zoomRowCols[_zoomLevel]['rows'];
      final cols = _zoomRowCols[_zoomLevel]['cols'];
      final width = _zoomRowCols[_zoomLevel]['width'];
      final height = _zoomRowCols[_zoomLevel]['height'];
      // create a list of visible colums
      var start = _horOffset < -(_tileSize * _scaleFactor) ? (-_horOffset ~/ (_tileSize * _scaleFactor)) : 0;
      var end = min(cols as int, (1 + (_windowWidth - _horOffset) ~/ (_tileSize * _scaleFactor)));
      final List<int> visibleCols = List.generate(end - start, (index) => (index + start).toInt());
      // and a list of visible rows
      start = _verOffset < -_tileSize * _scaleFactor ? (-_verOffset ~/ (_tileSize * _scaleFactor)) : 0;
      end = min(rows as int, (1 + (_windowHeight - _verOffset) ~/ (_tileSize * _scaleFactor)));
      final List<int> visibleRows = List.generate(end - start, (index) => (index + start).toInt());
      // calculate the offset of the first visible tile
      final Offset visibleOffset = Offset(
          _horOffset < 0 ? (_horOffset % (_tileSize * _scaleFactor)) - _tileSize * _scaleFactor : _horOffset,
          _verOffset < 0 ? (_verOffset % (_tileSize * _scaleFactor)) - _tileSize * _scaleFactor : _verOffset);
      // fill the available space with tiles
      return SizedBox(
          width: _windowWidth,
          height: _windowHeight,
          child: Stack(
            children: List.generate(visibleRows.length * visibleCols.length, (index) {
              final row = index ~/ visibleCols.length;
              final col = (index % visibleCols.length).toInt();
              final tileUrl = _getTileUrl(_zoomLevel, visibleCols[col], visibleRows[row]);
              return Positioned(
                  left: visibleOffset.dx + col * _tileSize.toDouble() * _scaleFactor,
                  top: visibleOffset.dy + row * _tileSize.toDouble() * _scaleFactor,
                  child: Container(
                      alignment: Alignment.topLeft,
                      width: (col == cols - 1 ? (width % _tileSize) * _scaleFactor : _tileSize * _scaleFactor) + (widget.showGrid ? 1 : 0),
                      height:
                          (row == rows - 1 ? (height % _tileSize) * _scaleFactor : _tileSize * _scaleFactor) + (widget.showGrid ? 1 : 0),
                      decoration: widget.showGrid ? BoxDecoration(border: Border.all(width: 0.5, color: Colors.black)) : null,
                      child: Image(
                          gaplessPlayback: true,
                          image: NetworkImageProvider(tileUrl, retryWhen: (Attempt attempt) => attempt.counter < 10))));
            }),
          ));
    } else {
      return SizedBox.shrink();
    }
  }

  void _setInitialImageData() {
    // set the initial zoomLevel, scaleFactor and offsets based on the maximum space we have received from our parent widget
    // set the zoomLevel one above the available size, so to fit the total picture we scale down
    var zoom = 0;
    while (zoom < _zoomRowCols.length && _zoomRowCols[zoom]['width'] < _windowWidth && _zoomRowCols[zoom]['height'] < _windowHeight) {
      zoom++;
    }
    _zoomLevel = (zoom < _zoomRowCols.length) ? zoom : _zoomRowCols.length - 1;
    _scaleFactor = _calculateScaleFactor(
        _zoomRowCols[_zoomLevel]['width'].toDouble(), _zoomRowCols[_zoomLevel]['height'].toDouble(), _windowWidth, _windowHeight);
    _scaleFactor = _scaleFactor > 1 ? 1 : _scaleFactor;
    _horOffset = (_windowWidth - _zoomRowCols[_zoomLevel]['width'] * _scaleFactor) / 2;
    _verOffset = (_windowHeight - _zoomRowCols[_zoomLevel]['height'] * _scaleFactor) / 2;
  }

  double _calculateScaleFactor(double width1, double height1, double width2, double height2) {
    double scaleFactorWidth = width2 / width1;
    double scaleFactorHeight = height2 / height1;
    return scaleFactorWidth < scaleFactorHeight ? scaleFactorWidth : scaleFactorHeight;
  }

  void _handleKeyEvent(event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      switch (event.logicalKey.keyLabel) {
        case 'Arrow Right' || 'R':
          _pan(ScaleUpdateDetails(focalPointDelta: Offset(-15, 0)));
        case 'Arrow Left' || 'L':
          _pan(ScaleUpdateDetails(focalPointDelta: Offset(15, 0)));
        case 'Arrow Up' || 'U':
          _pan(ScaleUpdateDetails(focalPointDelta: Offset(0, 15)));
        case 'Arrow Down' || 'D':
          _pan(ScaleUpdateDetails(focalPointDelta: Offset(0, -15)));
        case 'Escape':
          _setInitialImageData();
        case 'H':
          _setInitialImageData();
        case '+' || '=':
          _scrollZoomPan(PointerScrollEvent(position: Offset(_windowWidth / 2, _windowHeight / 2), scrollDelta: Offset(0.0, 51.0)));
        case '-' || '_':
          _scrollZoomPan(PointerScrollEvent(position: Offset(_windowWidth / 2, _windowHeight / 2), scrollDelta: Offset(0.0, -51.0)));
      }
    }
  }

  void _handleGestures(ScaleUpdateDetails scaleDetails) {
    if (scaleDetails.scale > 1) {
      if (_scaleStart < 1) _scaleStart = 1;
      _zoomIn(scaleDetails);
    } else if (scaleDetails.scale < 1) {
      if (_scaleStart > 1) _scaleStart = 1;
      _zoomOut(scaleDetails);
    }
    _pan(scaleDetails);
  }

  void _scrollZoomPan(pointerSignal) {
    _scaleStart = 1;
    if (pointerSignal.scrollDelta.dy > 0) {
      _zoomOut(ScaleUpdateDetails(focalPoint: pointerSignal.position, scale: pointerSignal.scrollDelta.dy > 50 ? 0.7 : 0.9));
    } else {
      _zoomIn(ScaleUpdateDetails(focalPoint: pointerSignal.position, scale: pointerSignal.scrollDelta.dy < -50 ? 1.3 : 1.1));
    }
    _pan(ScaleUpdateDetails(focalPointDelta: Offset.zero));
  }

  void _pan(scaleDetails) {
    // handle horizontal and/or vertical displacements
    _horOffset += scaleDetails.focalPointDelta.dx;
    _verOffset += scaleDetails.focalPointDelta.dy;
    var imgWidth = (_zoomRowCols[_zoomLevel]['width'] * _scaleFactor).floor();
    var imgHeight = (_zoomRowCols[_zoomLevel]['height'] * _scaleFactor).floor();
    double newHorOffset = _horOffset;
    double newVerOffset = _verOffset;
    if (imgWidth > _windowWidth) {
      if (_horOffset > 0) newHorOffset = 0;
      if (_horOffset < (_windowWidth - imgWidth)) {
        newHorOffset = (_windowWidth - imgWidth);
      }
    } else {
      if (_horOffset < 0) newHorOffset = 0;
      if (_horOffset > (_windowWidth - imgWidth)) {
        newHorOffset = (_windowWidth - imgWidth);
      }
    }
    if (imgHeight > _windowHeight) {
      if (_verOffset > 0) newVerOffset = 0;
      if (_verOffset < (_windowHeight - imgHeight)) {
        newVerOffset = (_windowHeight - imgHeight);
      }
    } else {
      if (_verOffset < 0) newVerOffset = 0;
      if (_verOffset > (_windowHeight - imgHeight)) {
        newVerOffset = (_windowHeight - imgHeight);
      }
    }
    _horOffset = newHorOffset;
    _verOffset = newVerOffset;
  }

  void _zoomOut(scaleDetails) {
    // do not zoom out beyond our windowsize for one of the dimensions
    var oldWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
    var oldHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;
    if (oldWidth > _windowWidth || oldHeight > _windowHeight) {
      _scaleFactor = _scaleFactor - ((_scaleStart - scaleDetails.scale) / 2);
      if (_scaleFactor < 0.5) {
        if (_zoomLevel > 0) {
          _zoomLevel--;
          _scaleFactor = _scaleFactor * 2;
        } else {
          _scaleFactor = 0.5;
        }
      }
      _scaleStart = scaleDetails.scale;
      var newWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
      var newHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;
      _horOffset = -((-_horOffset + scaleDetails.focalPoint.dx) * newWidth / oldWidth) + scaleDetails.focalPoint.dx;
      _verOffset = -((-_verOffset + scaleDetails.focalPoint.dy) * newHeight / oldHeight) + scaleDetails.focalPoint.dy;
    }
  }

  void _zoomIn(scaleDetails) {
    var oldWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
    var oldHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;
    if (_scaleFactor <= 1 && _zoomLevel <= _zoomRowCols.length - 1) {
      _scaleFactor = _scaleFactor + (scaleDetails.scale - _scaleStart) / 2;
      if (_scaleFactor > 1.0) {
        if (_zoomLevel < _zoomRowCols.length - 1) {
          _zoomLevel++;
          _scaleFactor = _scaleFactor / 2;
        } else {
          _scaleFactor = 1;
        }
      }
      _scaleStart = scaleDetails.scale;
      var newWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
      var newHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;
      _horOffset = -((-_horOffset + scaleDetails.focalPoint.dx) * newWidth / oldWidth) + scaleDetails.focalPoint.dx;
      _verOffset = -((-_verOffset + scaleDetails.focalPoint.dy) * newHeight / oldHeight) + scaleDetails.focalPoint.dy;
    }
  }

  String _getTileUrl(int zoom, int col, int row) {
    var tileGroup = _tileGroupMapping['$zoom-$col-$row.jpg'];
    return '${widget.baseUrl}/TileGroup$tileGroup/$zoom-$col-$row.jpg';
  }
}
