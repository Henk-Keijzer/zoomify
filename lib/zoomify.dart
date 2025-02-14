library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_network_image/flutter_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;

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

  /// callback function onChange, returns the scale of the image shown and the offset of the top-left corner related to the top-left
  /// corner of the visible image area
  final Function(double scale, Offset offset)? onChange;

  /// callback function when image is ready. returns max image width and height and the number of zoomlevels
  final Function(int imageWidth, int imageHeight, int zoomLevels)? onImageReady;

  /// animation duration
  final Duration animationDuration;

  /// animation curve
  final Curve animationCurve;

  const Zoomify(
      {super.key,
      required this.baseUrl,
      this.backgroundColor = Colors.black12,
      this.showZoomButtons = false,
      this.zoomButtonPosition = Alignment.bottomRight,
      this.zoomButtonColor = Colors.white,
      this.showGrid = false,
      this.onChange,
      this.onImageReady,
      this.animationDuration = const Duration(milliseconds: 500),
      this.animationCurve = Curves.easeOut});

  @override
  ZoomifyState createState() => ZoomifyState();
}

class ZoomifyState extends State<Zoomify> with SingleTickerProviderStateMixin {
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
  bool _windowReady = false;
  int _imageWidth = 0;
  int _imageHeight = 0;
  double _scaleStart = 1;
  Offset _panStart = Offset.zero;
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;
  late Animation _animation;
  Offset _panOffset = Offset.zero;
  Offset _zoomCenter = Offset.zero;
  double _scale = 0;
  Tween<Offset> _panTween = Tween<Offset>(begin: Offset.zero, end: Offset.zero);
  Tween<double> _scaleTween = Tween<double>(begin: 0, end: 0);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: widget.animationDuration, vsync: this);
    _animation = CurvedAnimation(parent: _animationController, curve: widget.animationCurve)..addListener(() => _updateAnimation());
    _loadImageProperties();
  }

  @override
  void didUpdateWidget(Zoomify oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.animationDuration != widget.animationDuration ||
        oldWidget.animationCurve != widget.animationCurve) {
      _animationController.duration = widget.animationDuration;
      _animation = CurvedAnimation(parent: _animationController, curve: widget.animationCurve)..addListener(() => _updateAnimation());
      _tileSize = 256;
      _zoomLevel = -1;
      _scaleFactor = 1.0;
      _horOffset = 0;
      _verOffset = 0;
      _zoomRowCols = [];
      _tileGroupMapping = {};
      _imageDataReady = false;
      _windowReady = false;
      _imageWidth = 0;
      _imageHeight = 0;
      _scaleStart = 1;
      _loadImageProperties();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    super.dispose();
    _animationController.dispose();
  }

  void animateZoomAndPan({double scaleDelta = 0.0, Offset zoomCenter = Offset.zero, Offset panOffset = Offset.zero}) {
    _animatePanAndZoom(panOffset: panOffset, zoomCenter: zoomCenter, scaleDelta: scaleDelta);
  }

  void zoomAndPan({double scaleDelta = 0.0, Offset zoomCenter = Offset.zero, Offset panOffset = Offset.zero}) {
    _panAndZoom(panOffset: panOffset, zoomCenter: zoomCenter, scaleDelta: scaleDelta);
  }

  void reset() {
    setState(() => _setInitialImageData());
  }

  Future<void> _loadImageProperties() async {
    // first get the essentials from the ImageProperties.xml
    final response = await http.get(Uri.parse(path.join(widget.baseUrl, 'ImageProperties.xml')));
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
      _zoomLevel = _zoomRowCols.length - 1;
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
      widget.onImageReady?.call(_imageWidth, _imageHeight, _zoomRowCols.length);
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
      if (_imageDataReady && !_windowReady) _setInitialImageData();
      if (_windowReady &&
          _zoomRowCols[_zoomLevel]['width'] * _scaleFactor <= _windowWidth &&
          _zoomRowCols[_zoomLevel]['height'] * _scaleFactor <= _windowHeight) {
        _setInitialImageData();
      }
      return Container(
          color: widget.backgroundColor,
          child: Stack(children: [
            Listener(
                // listen to mousewheel scrolls
                onPointerSignal: (pointerSignal) => setState(() {
                      if (pointerSignal is PointerScrollEvent) {
                        _panAndZoom(zoomCenter: pointerSignal.position, scaleDelta: -pointerSignal.scrollDelta.dy / 500);
                      }
                    }),
                child: KeyboardListener(
                    focusNode: _focusNode,
                    onKeyEvent: (event) => _handleKeyEvent(event),
                    child: GestureDetector(
                        onScaleUpdate: (scaleDetails) => setState(() => _handleGestures(scaleDetails)),
                        onScaleStart: (_) => _scaleStart = 1,
                        onScaleEnd: (_) => _scaleStart = 1,
                        onDoubleTapDown: (tapDetails) => _animatePanAndZoom(zoomCenter: tapDetails.localPosition, scaleDelta: 0.2),
                        child: _buildZoomifyImage()))),
            if (widget.showZoomButtons)
              Container(
                  alignment: widget.zoomButtonPosition,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: () => _animatePanAndZoom(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), scaleDelta: 0.2),
                        icon: Icon(Icons.add_box, color: widget.zoomButtonColor)),
                    IconButton(
                        onPressed: () => _animatePanAndZoom(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), scaleDelta: -0.2),
                        icon: Icon(Icons.indeterminate_check_box, color: widget.zoomButtonColor))
                  ]))
          ]));
    });
  }

  Widget _buildZoomifyImage() {
    if (_imageDataReady && _windowReady) {
      _zoomLevel = _zoomLevel.clamp(0, _zoomRowCols.length - 1);
      _scaleFactor = _scaleFactor.clamp(0.5, 1.0);
      final rows = _zoomRowCols[_zoomLevel]['rows'];
      final cols = _zoomRowCols[_zoomLevel]['cols'];
      final width = _zoomRowCols[_zoomLevel]['width'];
      final height = _zoomRowCols[_zoomLevel]['height'];
      // create a list of visible colums
      final startX = _horOffset < -(_tileSize * _scaleFactor) ? (-_horOffset ~/ (_tileSize * _scaleFactor)) : 0;
      final endX = min(cols as int, (1 + (_windowWidth - _horOffset) ~/ (_tileSize * _scaleFactor)));
      final List<int> visibleCols = List.generate(endX - startX, (index) => (index + startX).toInt());
      // and a list of visible rows
      final startY = _verOffset < -_tileSize * _scaleFactor ? (-_verOffset ~/ (_tileSize * _scaleFactor)) : 0;
      final endY = min(rows as int, (1 + (_windowHeight - _verOffset) ~/ (_tileSize * _scaleFactor)));
      final List<int> visibleRows = List.generate(endY - startY, (index) => (index + startY).toInt());
      // calculate the offset of the first visible tile
      final Offset visibleOffset = Offset(
          _horOffset < 0 ? (_horOffset % (_tileSize * _scaleFactor)) - _tileSize * _scaleFactor : _horOffset,
          _verOffset < 0 ? (_verOffset % (_tileSize * _scaleFactor)) - _tileSize * _scaleFactor : _verOffset);
      // how to get the tile url
      String getTileUrl(int zoom, int col, int row) {
        var tileGroup = _tileGroupMapping['$zoom-$col-$row.jpg'];
        return path.join(widget.baseUrl, 'TileGroup$tileGroup', '$zoom-$col-$row.jpg');
      }

      // fill the available space with tiles
      return SizedBox(
          width: _windowWidth,
          height: _windowHeight,
          child: Stack(
            children: List.generate(visibleRows.length * visibleCols.length, (index) {
              final row = index ~/ visibleCols.length;
              final col = (index % visibleCols.length).toInt();
              final tileUrl = getTileUrl(_zoomLevel, visibleCols[col], visibleRows[row]);
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

    double calculateScaleFactor(double width1, double height1, double width2, double height2) {
      double scaleFactorWidth = width2 / width1;
      double scaleFactorHeight = height2 / height1;
      return scaleFactorWidth < scaleFactorHeight ? scaleFactorWidth : scaleFactorHeight;
    }

    _scaleFactor = calculateScaleFactor(
        _zoomRowCols[_zoomLevel]['width'].toDouble(), _zoomRowCols[_zoomLevel]['height'].toDouble(), _windowWidth, _windowHeight);
    _scaleFactor = _scaleFactor > 1 ? 1 : _scaleFactor;
    _horOffset = (_windowWidth - _zoomRowCols[_zoomLevel]['width'] * _scaleFactor) / 2;
    _verOffset = (_windowHeight - _zoomRowCols[_zoomLevel]['height'] * _scaleFactor) / 2;
    _windowReady = true;
    widget.onChange?.call((_zoomRowCols[_zoomLevel]['width'] * _scaleFactor) / _imageWidth, Offset(_horOffset, _verOffset));
  }

  void _handleKeyEvent(event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      switch (event.logicalKey.keyLabel) {
        case 'Arrow Right' || 'R':
          _animatePanAndZoom(panOffset: Offset(100, 0));
        case 'Arrow Left' || 'L':
          _animatePanAndZoom(panOffset: Offset(-100, 0));
        case 'Arrow Up' || 'U':
          _animatePanAndZoom(panOffset: Offset(0, -100));
        case 'Arrow Down' || 'D':
          _animatePanAndZoom(panOffset: Offset(0, 100));
        case 'Escape' || 'H':
          setState(() => _setInitialImageData());
        case '+' || '=':
          _animatePanAndZoom(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), scaleDelta: 0.2);
        case '-' || '_':
          _animatePanAndZoom(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), scaleDelta: -0.2);
      }
    }
  }

  // set new pan and zoom values
  void _panAndZoom({panOffset = Offset.zero, zoomCenter = Offset.zero, scaleDelta = 0.0}) {
    _panOffset = panOffset;
    _zoomCenter = zoomCenter;
    _scale = scaleDelta;
    _pan();
    _zoom();
    if (!_animationController.isAnimating) {
      widget.onChange?.call((_zoomRowCols[_zoomLevel]['width'] * _scaleFactor) / _imageWidth, Offset(_horOffset, _verOffset));
    }
    setState(() {});
  }

  // translate gestures to pan and zoom values
  void _handleGestures(scaleDetails) {
    _animationController.reset(); // stop any animation that might be running
    _panAndZoom(
        panOffset: Offset(scaleDetails.focalPointDelta.dx * 2, scaleDetails.focalPointDelta.dy * 2),
        zoomCenter: scaleDetails.localFocalPoint,
        scaleDelta: (scaleDetails.scale - _scaleStart));
    _scaleStart = scaleDetails.scale;
  }

  // set initial pan and zoom values for pan/zoom animation and start the animation
  void _animatePanAndZoom({panOffset = Offset.zero, zoomCenter = Offset.zero, scaleDelta = 0.0}) {
    _animationController.reset(); // just in case we were already animating
    _panTween = Tween<Offset>(begin: Offset.zero, end: panOffset);
    _scaleTween = Tween<double>(begin: 0, end: scaleDelta);
    _zoomCenter = zoomCenter;
    _panStart = Offset.zero;
    _scaleStart = 0;
    widget.onChange?.call((_zoomRowCols[_zoomLevel]['width'] * _scaleFactor) / _imageWidth, Offset(_horOffset, _verOffset));
    _animationController.forward();
  }

  void _updateAnimation() {
    if (_animation.isCompleted) {
      _animationController.reset();
      return;
    }
    if (_animation.isAnimating) {
      _panAndZoom(
          panOffset: _panTween.transform(_animation.value) - _panStart,
          zoomCenter: _zoomCenter,
          scaleDelta: _scaleTween.transform(_animation.value) - _scaleStart);
      _scaleStart = _scaleTween.transform(_animation.value);
      _panStart = _panTween.transform(_animation.value);
      setState(() {});
    }
  }

  void _pan() {
    // Handle horizontal and/or vertical displacements
    _horOffset += _panOffset.dx;
    _verOffset += _panOffset.dy;
    var imgWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
    var imgHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;

    _horOffset = _horOffset.clamp(
      _windowWidth - imgWidth > 0 ? 0 : _windowWidth - imgWidth,
      _windowWidth - imgWidth > 0 ? _windowWidth - imgWidth : 0,
    );

    _verOffset = _verOffset.clamp(
      _windowHeight - imgHeight > 0 ? 0 : _windowHeight - imgHeight,
      _windowHeight - imgHeight > 0 ? _windowHeight - imgHeight : 0,
    );
  }

  void _zoom() {
    var oldWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
    var oldHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;
    _scaleFactor += _scale;

    if (_scaleFactor > 1.0) {
      if (_zoomLevel < _zoomRowCols.length - 1) {
        _zoomLevel++;
        _scaleFactor /= 2;
      } else {
        _scaleFactor = 1.0;
      }
    } else if (_scale < 0 && oldWidth <= _windowWidth && oldHeight <= _windowHeight) {
      _animationController.reset();
      _setInitialImageData();
      return;
    } else if (_scaleFactor < 0.5) {
      if (_zoomLevel > 0) {
        _zoomLevel--;
        _scaleFactor *= 2;
      } else {
        _scaleFactor = 0.5;
      }
    }

    var newWidth = _zoomRowCols[_zoomLevel]['width'] * _scaleFactor;
    var newHeight = _zoomRowCols[_zoomLevel]['height'] * _scaleFactor;

    _horOffset =
        newWidth > _windowWidth ? ((_horOffset - _zoomCenter.dx) * newWidth / oldWidth) + _zoomCenter.dx : (_windowWidth - newWidth) / 2;

    _verOffset = newHeight > _windowHeight
        ? ((_verOffset - _zoomCenter.dy) * newHeight / oldHeight) + _zoomCenter.dy
        : (_windowHeight - newHeight) / 2;
  }
}
