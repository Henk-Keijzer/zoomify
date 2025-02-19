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

//------------------------------------------------------------------------------------------------------------------------------------------

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

  /// callback function onChange, returns the zoomlevel of the image and the offset of the top-left corner related to the top-left
  /// corner of the visible image area
  final Function(double zoomLevel, Offset offset, Size currentImageSize)? onChange;

  /// callback function when image is ready. returns max image width and height and the number of zoomlevels
  final Function(Size maxImageSize, int zoomLevels)? onImageReady;

  /// callback function for a single tap, returns the offset from
  final Function(Offset tapOffset)? onTap;

  /// animation duration
  final Duration animationDuration;

  /// animation curve
  final Curve animationCurve;

  /// sync, onChange callback function will be triggered each animation frame, if false (default) the onChange callback function will be
  /// only be triggered at the end of the animation
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
      this.onTap,
      this.animationDuration = const Duration(milliseconds: 500),
      this.animationCurve = Curves.easeOut,
      this.animationSync = false,
      this.controller});

  @override
  ZoomifyState createState() => ZoomifyState();
}

//------------------------------------------------------------------------------------------------------------------------------------------
//
// variables used in ZoomifyState and in ZoomifyController
//
double _zoomLevel = 0;
double _horOffset = 0;
double _verOffset = 0;
double _imageWidth = 0;
double _imageHeight = 0;

//------------------------------------------------------------------------------------------------------------------------------------------
//
// ZoomifyState
//
class ZoomifyState extends State<Zoomify> with SingleTickerProviderStateMixin {
  double _windowWidth = 0;
  double _windowHeight = 0;
  int _tileSize = 256;
  double _maxZoomLevel = 0;
  List<Map<String, dynamic>> _zoomRowCols = [];
  Map<String, int> _tileGroupMapping = {};
  bool _imageDataReady = false;
  bool _imageReady = false;
  Offset _zoomCenter = Offset.zero;
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;
  late Animation _animation;
  Tween<Offset> _panTween = Tween<Offset>(begin: Offset.zero, end: Offset.zero);
  Offset _panStart = Offset.zero;
  Tween<double> _zoomTween = Tween<double>(begin: 0, end: 0);
  double _scaleStart = 1;

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
    if (oldWidget.baseUrl != widget.baseUrl) _loadImageProperties();
    if (oldWidget.animationDuration != widget.animationDuration) _animationController.duration = widget.animationDuration;
    if (oldWidget.animationCurve != widget.animationCurve) {
      _animation = CurvedAnimation(parent: _animationController, curve: widget.animationCurve);
    }
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    _animationController.dispose();
  }

  void _controllerFunctions() {
    switch (widget.controller!._setType) {
      case 'reset':
        setState(() => _setInitialImageData());
      case 'zoomAndPan':
        _zoomAndPan(
            zoomLevel: widget.controller!._myZoomLevel,
            zoomCenter: widget.controller!._myZoomCenter,
            panOffset: widget.controller!._myPanOffset);
      case 'animateZoomAndPan':
        _animateZoomAndPan(
            zoomLevel: widget.controller!._myZoomLevel,
            zoomCenter: widget.controller!._myZoomCenter,
            panOffset: widget.controller!._myPanOffset);
      default:
    }
  }

  Future<void> _loadImageProperties() async {
    _zoomRowCols = [];
    _tileGroupMapping = {};
    _imageDataReady = false;
    _imageReady = false;
    // first get the essentials from the ImageProperties.xml
    final response = await http.get(Uri.parse(path.join(widget.baseUrl, 'ImageProperties.xml')));
    if (response.statusCode == 200) {
      final attributes = XmlDocument.parse(response.body).getElement("IMAGE_PROPERTIES")?.attributes ?? [];
      for (final attribute in attributes) {
        switch (attribute.name.toString()) {
          case 'WIDTH':
            _imageWidth = double.parse(attribute.value);
          case 'HEIGHT':
            _imageHeight = double.parse(attribute.value);
          case 'TILESIZE':
            _tileSize = int.parse(attribute.value);
        }
      }
      // now make a list (_zoomRowCols) with the number of rows, number of colums, image widths and image heights per zoomlevel (in reverse
      // order, i.e
      // zoomlevel 0 is the smallest image, fitting in a single tile: 0-0-0.jpg)
      var calcWidth = _imageWidth;
      var calcHeight = _imageHeight;
      var tiles = 2; // any value > 1
      while (tiles > 1) {
        var rows = (calcHeight / _tileSize).ceil();
        var cols = (calcWidth / _tileSize).ceil();
        _zoomRowCols.insert(0, {'rows': rows, 'cols': cols, 'width': calcWidth, 'height': calcHeight});
        calcWidth = (calcWidth / 2).floor().toDouble();
        calcHeight = (calcHeight / 2).floor().toDouble();
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
      widget.onImageReady?.call(Size(_imageWidth, _imageHeight), _zoomRowCols.length);
      setState(() {});
    } else {
      throw Exception('Failed to load image properties');
    }
  }

  @override
  Widget build(BuildContext context) {
    FocusScope.of(context).requestFocus(_focusNode); // for keyboard entry
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      // use LayoutBuilder to get the current window size
      _windowWidth = constraints.maxWidth;
      _windowHeight = constraints.maxHeight;
      if (_imageDataReady && !_imageReady) {
        // imagedata is ready but the image itself is not properly scaled yet
        _setInitialImageData(); //
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
                        onTapUp: (tapDetails) => widget.onTap
                            ?.call((tapDetails.localPosition - Offset(_horOffset, _verOffset)) * _zoomRowCols.last['width'] / _imageWidth),
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
    if (!_imageDataReady || !_imageReady) return SizedBox.shrink();

    // convert _zoomLevel to baseZoomLevel and scale
    int baseZoomLevel = _zoomLevel.ceil() - 1;
    double scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
    //
    // increase the size of the image in case it is smaller than the available space
    if (_zoomRowCols[baseZoomLevel]['width'] * scale < _windowWidth && _zoomRowCols[baseZoomLevel]['height'] * scale < _windowHeight) {
      _setInitialImageData();
      baseZoomLevel = _zoomLevel.ceil() - 1;
      scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
    }
    // move the image to the right and to the bottom if there is empty space there
    var oldOffset = Offset(_horOffset, _verOffset);
    _horOffset = _horOffset
        .clamp(
          _windowWidth - _imageWidth > 0 ? 0 : _windowWidth - _imageWidth,
          _windowWidth - _imageWidth > 0 ? _windowWidth - _imageWidth : 0,
        )
        .roundToDouble();
    _verOffset = _verOffset
        .clamp(
          _windowHeight - _imageHeight > 0 ? 0 : _windowHeight - _imageHeight,
          _windowHeight - _imageHeight > 0 ? _windowHeight - _imageHeight : 0,
        )
        .roundToDouble();
    if (oldOffset != Offset(_horOffset, _verOffset)) {
      // if we had to move the image, the zoomCenter must also move and we have to call the onChange callback function ater the build
      _callOnChangeAfterBuild();
    }
    //
    // create some readability variables
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

    // fill the available space with tiles
    return SizedBox(
        width: _windowWidth.toDouble(),
        height: _windowHeight.toDouble(),
        child: Stack(
          children: List.generate(visibleRows.length * visibleCols.length, (index) {
            final row = index ~/ visibleCols.length;
            final col = (index % visibleCols.length).toInt();
            return Positioned(
                left: visibleOffset.dx + col * _tileSize * scale,
                top: visibleOffset.dy + row * _tileSize * scale,
                child: Container(
                    alignment: Alignment.topLeft,
                    width: (visibleCols[col] == cols - 1 ? (width % _tileSize) * scale : _tileSize * scale) + (widget.showGrid ? 1 : 0),
                    height: (visibleRows[row] == rows - 1 ? (height % _tileSize) * scale : _tileSize * scale) + (widget.showGrid ? 1 : 0),
                    decoration: widget.showGrid ? BoxDecoration(border: Border.all(width: 0.5, color: Colors.black)) : null,
                    child: Image(
                        gaplessPlayback: true,
                        image: NetworkImageProvider(
                            path.join(
                                widget.baseUrl,
                                'TileGroup${_tileGroupMapping['$baseZoomLevel-${visibleCols[col]}-${visibleRows[row]}.jpg']}',
                                '$baseZoomLevel-${visibleCols[col]}-${visibleRows[row]}.jpg'),
                            retryWhen: (Attempt attempt) => attempt.counter < 10))));
          }),
        ));
  }

  Future<void> _callOnChangeAfterBuild() async {
    await Future.delayed(Duration.zero);
    widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
  }

  void _setInitialImageData() {
    double calculateScale(double width1, double height1, double width2, double height2) {
      double scaleWidth = width2 / width1;
      double scaleHeight = height2 / height1;
      return scaleWidth < scaleHeight ? scaleWidth : scaleHeight;
    }

    // first find the baseZoomLevel one above the available size, so to fit the total picture, then we scale down
    var zoom = 0;
    while (zoom < _zoomRowCols.length && _zoomRowCols[zoom]['width'] < _windowWidth && _zoomRowCols[zoom]['height'] < _windowHeight) {
      zoom++;
    }
    var baseZoomLevel = (zoom < _zoomRowCols.length) ? zoom : _zoomRowCols.length - 1;

    var scale = calculateScale(
        _zoomRowCols[baseZoomLevel]['width'].toDouble(), _zoomRowCols[baseZoomLevel]['height'].toDouble(), _windowWidth, _windowHeight);
    _zoomLevel = baseZoomLevel + 1 + (log(scale) / log(2));
    _horOffset = ((_windowWidth - _zoomRowCols[baseZoomLevel]['width'] * scale) / 2);
    _verOffset = ((_windowHeight - _zoomRowCols[baseZoomLevel]['height'] * scale) / 2);
    _imageWidth = (_zoomRowCols[baseZoomLevel]['width'] * scale).round().toDouble();
    _imageHeight = (_zoomRowCols[baseZoomLevel]['height'] * scale).round().toDouble();
    _imageReady = true;
    // sometimes this routine is called during the build process. We call the onChange callback function after the build is ready,
    // because otherwise the onChange function cannot call setState
    _callOnChangeAfterBuild();
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
    _animationController.reset(); // stop any animation that may be running
    _zoomAndPan(
        panOffset: Offset(scaleDetails.focalPointDelta.dx, scaleDetails.focalPointDelta.dy),
        zoomCenter: scaleDetails.localFocalPoint,
        zoomLevel: _zoomLevel + (scaleDetails.scale - _scaleStart));
    _scaleStart = scaleDetails.scale;
  }

  // set new pan and zoom values without animation
  void _zoomAndPan({panOffset = Offset.zero, zoomCenter = const Offset(-1, -1), zoomLevel = -1}) {
    _zoom(zoomLevel == -1 ? _zoomLevel : zoomLevel, zoomCenter.dx == -1 ? _zoomCenter : zoomCenter);
    _pan(panOffset);
    setState(() {});
    widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
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
      widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
    } else if (_animation.isAnimating) {
      _zoom(_zoomTween.transform(_animation.value), _zoomCenter);
      _pan(_panTween.transform(_animation.value) - _panStart);
      _panStart = _panTween.transform(_animation.value);
      if (widget.animationSync) {
        widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
      }
    }
    setState(() {});
  }

  void _pan(panOffset) {
    _horOffset += (panOffset.dx as double).roundToDouble();
    _verOffset += (panOffset.dy as double).roundToDouble();
  }

  void _zoom(zoomLevel, zoomCenter) {
    if (zoomLevel == _zoomLevel) return;
    _zoomLevel = zoomLevel.clamp(0, _maxZoomLevel).toDouble();
    int baseZoomLevel = _zoomLevel.ceil() - 1;
    double scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();

    var newWidth = (_zoomRowCols[baseZoomLevel]['width'] * scale).round();
    var newHeight = (_zoomRowCols[baseZoomLevel]['height'] * scale).round();

    _horOffset = (newWidth > _windowWidth
            ? (((_horOffset - zoomCenter.dx) * newWidth / _imageWidth) + zoomCenter.dx)
            : ((_windowWidth - newWidth) / 2))
        .roundToDouble();

    _verOffset = (newHeight > _windowHeight
            ? (((_verOffset - zoomCenter.dy) * newHeight / _imageHeight) + zoomCenter.dy)
            : ((_windowHeight - newHeight) / 2))
        .roundToDouble();

    _imageWidth = newWidth.roundToDouble();
    _imageHeight = newHeight.roundToDouble();
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------
//
// The ZoomifyController closs
//
class ZoomifyController extends ChangeNotifier {
  ZoomifyController();

  double _myZoomLevel = -1;
  Offset _myZoomCenter = Offset(-1, -1);
  Offset _myPanOffset = Offset.zero;

  String _setType = '';

  zoomAndPan({double zoomLevel = -1, Offset zoomCenter = const Offset(-1, -1), Offset panOffset = const Offset(0, 0)}) {
    _myZoomLevel = zoomLevel;
    _myZoomCenter = zoomCenter;
    _myPanOffset = panOffset;
    _setType = 'zoomAndPan';
    notifyListeners();
  }

  animateZoomAndPan({double zoomLevel = -1, Offset zoomCenter = const Offset(-1, -1), Offset panOffset = const Offset(0, 0)}) {
    _myZoomLevel = zoomLevel;
    _myZoomCenter = zoomCenter;
    _myPanOffset = panOffset;
    _setType = 'animateZoomAndPan';
    notifyListeners();
  }

  reset() {
    _setType = 'reset';
    notifyListeners();
  }

  double getZoomLevel() => _zoomLevel;
  Offset getOffset() => Offset(_horOffset, _verOffset);
  Size getCurrentImageSize() => Size(_imageWidth, _imageHeight);
}
