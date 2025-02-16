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
  final Function(double zoomLevel, Offset offset)? onChange;

  /// callback function when image is ready. returns max image width and height and the number of zoomlevels
  final Function(int imageWidth, int imageHeight, int zoomLevels)? onImageReady;

  /// animation duration
  final Duration animationDuration;

  /// animation curve
  final Curve animationCurve;

  /// sync, onChange callback function will be triggered each animation frame
  final bool animationSync;

  /// the controller to use
  final ZoomifyController? controller;

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
      this.animationCurve = Curves.easeOut,
      this.animationSync = false,
      this.controller});

  @override
  ZoomifyState createState() => ZoomifyState();
}

class ZoomifyState extends State<Zoomify> with SingleTickerProviderStateMixin {
  int _windowWidth = 0;
  int _windowHeight = 0;
  int _tileSize = 256;
  double _maxZoomLevel = 0;
  double _zoomLevel = 0;
  int _horOffset = 0;
  int _verOffset = 0;
  List<Map<String, dynamic>> _zoomRowCols = [];
  Map<String, int> _tileGroupMapping = {};
  bool _imageDataReady = false;
  bool _imageReady = false;
  int _imageWidth = 0;
  int _imageHeight = 0;
  double _scaleStart = 1;
  Offset _panStart = Offset.zero;
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;
  late Animation _animation;
  Offset _zoomCenter = Offset.zero;
  Tween<Offset> _panTween = Tween<Offset>(begin: Offset.zero, end: Offset.zero);
  Tween<double> _zoomTween = Tween<double>(begin: 0, end: 0);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(() => _controllerFunctions());
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
      _zoomLevel = 0;
      _horOffset = 0;
      _verOffset = 0;
      _zoomRowCols = [];
      _tileGroupMapping = {};
      _imageDataReady = false;
      _imageReady = false;
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

  void _controllerFunctions() {
    if (widget.controller!.res) {
      setState(() => _setInitialImageData());
      return;
    } else if (widget.controller!.anim) {
      _animateZoomAndPan(
          zoomLevel: widget.controller!.zoomLevel, zoomCenter: widget.controller!.zoomCenter, panOffset: widget.controller!.panOffset);
    } else {
      _zoomAndPan(
          zoomLevel: widget.controller!.zoomLevel, zoomCenter: widget.controller!.zoomCenter, panOffset: widget.controller!.panOffset);
    }
  }

  @Deprecated('Use animateZoomAndPan using the controller instead')
  void animateZoomAndPan({double zoomLevel = -1, Offset zoomCenter = const Offset(-1, -1), Offset panOffset = Offset.zero}) {
    _animateZoomAndPan(
        panOffset: panOffset,
        zoomCenter: zoomCenter == const Offset(-1, -1) ? Offset(_windowWidth / 2, _windowHeight / 2) : zoomCenter,
        zoomLevel: zoomLevel == -1 ? _zoomLevel : zoomLevel);
  }

  @Deprecated('Use zoomAndPan using the controller instead')
  void zoomAndPan({double zoomLevel = -1, Offset zoomCenter = const Offset(-1, -1), Offset panOffset = Offset.zero}) {
    _zoomAndPan(
        panOffset: panOffset,
        zoomCenter: zoomCenter == const Offset(-1, -1) ? Offset(_windowWidth / 2, _windowHeight / 2) : zoomCenter,
        zoomLevel: zoomLevel == -1 ? _zoomLevel : zoomLevel);
  }

  @Deprecated('Use reset using the controller instead')
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
      _maxZoomLevel = _zoomRowCols.length.toDouble();
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
      _windowWidth = constraints.maxWidth.toInt();
      _windowHeight = constraints.maxHeight.toInt();
      if (_imageDataReady && !_imageReady) {
        _executeAfterBuild();
        _setInitialImageData(building: true);
      }
      return Container(
          color: widget.backgroundColor,
          child: Stack(children: [
            Listener(
                // listen to mousewheel scrolls
                onPointerSignal: (pointerSignal) => setState(() {
                      if (pointerSignal is PointerScrollEvent) {
                        _zoomAndPan(zoomCenter: pointerSignal.position, zoomLevel: _zoomLevel - pointerSignal.scrollDelta.dy / 500);
                      }
                    }),
                child: KeyboardListener(
                    focusNode: _focusNode,
                    onKeyEvent: (event) => _handleKeyEvent(event),
                    child: GestureDetector(
                        onScaleUpdate: (scaleDetails) => setState(() => _handleGestures(scaleDetails)),
                        onScaleStart: (_) => _scaleStart = 1,
                        onScaleEnd: (_) => _scaleStart = 1,
                        onDoubleTapDown: (tapDetails) =>
                            _animateZoomAndPan(zoomCenter: tapDetails.localPosition, zoomLevel: _zoomLevel + 0.5),
                        child: _buildZoomifyImage()))),
            if (widget.showZoomButtons)
              Container(
                  alignment: widget.zoomButtonPosition,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: () =>
                            _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel + 0.5),
                        icon: Icon(Icons.add_box, color: widget.zoomButtonColor)),
                    IconButton(
                        onPressed: () =>
                            _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel - 0.5),
                        icon: Icon(Icons.indeterminate_check_box, color: widget.zoomButtonColor))
                  ]))
          ]));
    });
  }

  Widget _buildZoomifyImage() {
    if (_imageDataReady && _imageReady) {
      int baseZoomLevel = _zoomLevel.floor();
      if (baseZoomLevel >= _zoomRowCols.length) baseZoomLevel = baseZoomLevel - 1;
      double scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
      if (_zoomRowCols[baseZoomLevel]['width'] * scale < _windowWidth && _zoomRowCols[baseZoomLevel]['height'] * scale < _windowHeight) {
        _setInitialImageData(building: true);
      }
      baseZoomLevel = _zoomLevel.clamp(0, _maxZoomLevel).floor();
      if (baseZoomLevel >= _zoomRowCols.length) baseZoomLevel = baseZoomLevel - 1;
      scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
      final rows = _zoomRowCols[baseZoomLevel]['rows'];
      final cols = _zoomRowCols[baseZoomLevel]['cols'];
      final width = _zoomRowCols[baseZoomLevel]['width'];
      final height = _zoomRowCols[baseZoomLevel]['height'];
      // create a list of visible colums
      final startX = _horOffset < -(_tileSize * scale) ? (-_horOffset ~/ (_tileSize * scale)) : 0;
      final endX = min(cols as int, (1 + (_windowWidth - _horOffset) ~/ (_tileSize * scale)));
      final List<int> visibleCols = List.generate(endX - startX, (index) => (index + startX).toInt());
      // and a list of visible rows
      final startY = _verOffset < -_tileSize * scale ? (-_verOffset ~/ (_tileSize * scale)) : 0;
      final endY = min(rows as int, (1 + (_windowHeight - _verOffset) ~/ (_tileSize * scale)));
      final List<int> visibleRows = List.generate(endY - startY, (index) => (index + startY).toInt());
      // calculate the offset of the first visible tile
      final Offset visibleOffset = Offset(_horOffset < 0 ? (_horOffset % (_tileSize * scale)) - _tileSize * scale : _horOffset.toDouble(),
          _verOffset < 0 ? (_verOffset % (_tileSize * scale)) - _tileSize * scale : _verOffset.toDouble());
      // how to get the tile url
      String getTileUrl(int zoom, int col, int row) {
        var tileGroup = _tileGroupMapping['$zoom-$col-$row.jpg'];
        return path.join(widget.baseUrl, 'TileGroup$tileGroup', '$zoom-$col-$row.jpg');
      }

      // fill the available space with tiles
      return SizedBox(
          width: _windowWidth.toDouble(),
          height: _windowHeight.toDouble(),
          child: Stack(
            children: List.generate(visibleRows.length * visibleCols.length, (index) {
              final row = index ~/ visibleCols.length;
              final col = (index % visibleCols.length).toInt();
              final tileUrl = getTileUrl(baseZoomLevel, visibleCols[col], visibleRows[row]);
              return Positioned(
                  left: visibleOffset.dx + col * _tileSize.toDouble() * scale,
                  top: visibleOffset.dy + row * _tileSize.toDouble() * scale,
                  child: Container(
                      alignment: Alignment.topLeft,
                      width: (col == cols - 1 ? (width % _tileSize) * scale : _tileSize * scale) + (widget.showGrid ? 1 : 0),
                      height: (row == rows - 1 ? (height % _tileSize) * scale : _tileSize * scale) + (widget.showGrid ? 1 : 0),
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

  Future<void> _executeAfterBuild() async {
    await Future.delayed(Duration.zero);
    // this code will get executed after the build method because of the way async functions are scheduled.
    // it ensures the onChange callback is allowed to call setState itself
    widget.onChange?.call(_zoomLevel, Offset(_horOffset.toDouble(), _verOffset.toDouble()));
  }

  void _setInitialImageData({building = false}) {
    // set the initial zoomLevel and vertical and horizontal offsets based on the maximum space we have received from our parent widget
    //
    // first find the baseZoomLevel one above the available size, so to fit the total picture, then we scale down
    var zoom = 0;
    while (zoom < _zoomRowCols.length && _zoomRowCols[zoom]['width'] < _windowWidth && _zoomRowCols[zoom]['height'] < _windowHeight) {
      zoom++;
    }
    var baseZoomLevel = (zoom < _zoomRowCols.length) ? zoom : _zoomRowCols.length - 1;

    double calculateScale(int width1, int height1, int width2, int height2) {
      double scaleWidth = width2 / width1;
      double scaleHeight = height2 / height1;
      return scaleWidth < scaleHeight ? scaleWidth : scaleHeight;
    }

    var scale = calculateScale(_zoomRowCols[baseZoomLevel]['width'], _zoomRowCols[baseZoomLevel]['height'], _windowWidth, _windowHeight);
    _zoomLevel = baseZoomLevel + 1 + (log(scale) / log(2)) - 0.0001;
    _horOffset = ((_windowWidth - _zoomRowCols[baseZoomLevel]['width'] * scale) / 2).round().toInt();
    _verOffset = ((_windowHeight - _zoomRowCols[baseZoomLevel]['height'] * scale) / 2).round().toInt();
    _imageWidth = (_zoomRowCols[baseZoomLevel]['width'].toInt() * scale).toInt();
    _imageHeight = (_zoomRowCols[baseZoomLevel]['height'].toInt() * scale).toInt();
    _imageReady = true;
    if (!building) widget.onChange?.call(_zoomLevel, Offset(_horOffset.toDouble(), _verOffset.toDouble()));
  }

  void _handleKeyEvent(event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      switch (event.logicalKey.keyLabel) {
        case 'Arrow Right' || 'R':
          _animateZoomAndPan(panOffset: Offset(100, 0), zoomLevel: _zoomLevel);
        case 'Arrow Left' || 'L':
          _animateZoomAndPan(panOffset: Offset(-100, 0), zoomLevel: _zoomLevel);
        case 'Arrow Up' || 'U':
          _animateZoomAndPan(panOffset: Offset(0, -100), zoomLevel: _zoomLevel);
        case 'Arrow Down' || 'D':
          _animateZoomAndPan(panOffset: Offset(0, 100), zoomLevel: _zoomLevel);
        case 'Escape' || 'H':
          setState(() => _setInitialImageData());
        case '+' || '=':
          _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel + 0.2);
        case '-' || '_':
          _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel - 0.2);
      }
    }
  }

  // translate gestures to pan and zoom values
  void _handleGestures(scaleDetails) {
    _animationController.reset(); // stop any animation that might be running
    _zoomAndPan(
        panOffset: Offset(scaleDetails.focalPointDelta.dx * 2, scaleDetails.focalPointDelta.dy * 2),
        zoomCenter: scaleDetails.localFocalPoint,
        zoomLevel: _zoomLevel + (scaleDetails.scale - _scaleStart));
    _scaleStart = scaleDetails.scale;
  }

  // set new pan and zoom values
  void _zoomAndPan({panOffset = Offset.zero, zoomCenter = const Offset(-1, -1), zoomLevel = -1}) {
    _zoom(zoomLevel == -1 ? _zoomLevel : zoomLevel, zoomCenter.dx == -1 ? _zoomCenter : zoomCenter);
    _pan(panOffset);
    setState(() {});
    widget.onChange?.call(_zoomLevel, Offset(_horOffset.toDouble(), _verOffset.toDouble()));
  }

  // set initial pan and zoom values for pan/zoom animation and start the animation
  void _animateZoomAndPan({panOffset = Offset.zero, zoomCenter = const Offset(-1, -1), zoomLevel = -1}) {
    _animationController.reset(); // just in case we were already animating
    _panTween = Tween<Offset>(begin: Offset.zero, end: panOffset);
    _zoomTween = Tween<double>(begin: _zoomLevel, end: zoomLevel == -1 ? _zoomLevel : zoomLevel);
    _zoomCenter = zoomCenter.dx == -1 ? _zoomCenter : zoomCenter;
    _panStart = Offset.zero;
    _animationController.forward();
  }

  void _updateAnimation() {
    if (_animation.isCompleted) {
      _animationController.reset();
      widget.onChange?.call(_zoomLevel, Offset(_horOffset.toDouble(), _verOffset.toDouble()));
    } else if (_animation.isAnimating) {
      _zoom(_zoomTween.transform(_animation.value), _zoomCenter);
      _pan(_panTween.transform(_animation.value) - _panStart);
      _panStart = _panTween.transform(_animation.value);
      if (widget.animationSync) {
        widget.onChange?.call(_zoomLevel, Offset(_horOffset.toDouble(), _verOffset.toDouble()));
      }
    }
    setState(() {});
  }

  void _pan(panOffset) {
    _horOffset += (panOffset.dx as double).round().toInt();
    _verOffset += (panOffset.dy as double).round().toInt();

    // ensure we do not move the image outside the window
    _horOffset = _horOffset.clamp(
      _windowWidth - _imageWidth > 0 ? 0 : _windowWidth - _imageWidth,
      _windowWidth - _imageWidth > 0 ? _windowWidth - _imageWidth : 0,
    );
    _verOffset = _verOffset.clamp(
      _windowHeight - _imageHeight > 0 ? 0 : _windowHeight - _imageHeight,
      _windowHeight - _imageHeight > 0 ? _windowHeight - _imageHeight : 0,
    );
  }

  void _zoom(zoomLevel, zoomCenter) {
    if (zoomLevel == _zoomLevel) return;
    double newZoomLevel = zoomLevel.clamp(0, _maxZoomLevel).toDouble();
    _zoomLevel = newZoomLevel;
    if (newZoomLevel == _maxZoomLevel) newZoomLevel = newZoomLevel - 1;
    int baseZoomLevel = newZoomLevel.floor();
    double scale = pow(2, newZoomLevel - newZoomLevel.ceil()).toDouble();

    var newWidth = (_zoomRowCols[baseZoomLevel]['width'] * scale).round();
    var newHeight = (_zoomRowCols[baseZoomLevel]['height'] * scale).round();

    _horOffset = newWidth > _windowWidth
        ? (((_horOffset - zoomCenter.dx) * newWidth / _imageWidth) + zoomCenter.dx).round().toInt()
        : ((_windowWidth - newWidth) / 2).round().toInt();

    _verOffset = newHeight > _windowHeight
        ? (((_verOffset - zoomCenter.dy) * newHeight / _imageHeight) + zoomCenter.dy).round().toInt()
        : ((_windowHeight - newHeight) / 2).round().toInt();

    _imageWidth = newWidth.round().toInt();
    _imageHeight = newHeight.round().toInt();
  }
}

class ZoomifyController extends ChangeNotifier {
  ZoomifyController();

  /// the new zoomlevel
  double zoomLevel = -1;

  /// the zoomCenter, i.e. the point around which the zoom is done
  Offset zoomCenter = Offset(-1, -1);

  /// the pan offset to be applied
  Offset panOffset = Offset.zero;

  bool anim = false;
  bool res = false;

  zoomAndPan({double zoomLevel = -1, Offset zoomCenter = const Offset(-1, -1), Offset panOffset = const Offset(0, 0)}) {
    this.zoomLevel = zoomLevel;
    this.zoomCenter = zoomCenter;
    this.panOffset = panOffset;
    anim = false;
    res = false;
    notifyListeners();
  }

  animateZoomAndPan({double zoomLevel = -1, Offset zoomCenter = const Offset(-1, -1), Offset panOffset = const Offset(0, 0)}) {
    this.zoomLevel = zoomLevel;
    this.zoomCenter = zoomCenter;
    this.panOffset = panOffset;
    anim = true;
    res = false;
    notifyListeners();
  }

  reset() {
    res = true;
    notifyListeners();
  }
}
