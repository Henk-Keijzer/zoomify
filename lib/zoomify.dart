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

  /// show panbuttons
  final bool showPanButtons;

  /// show reset button
  final bool showResetButton;

  /// zoombutton position
  final Alignment buttonPosition;

  /// zoombutton color
  final Color buttonColor;

  /// shows the tilegrid, default false
  final bool showGrid;

  /// callback function onChange, returns the zoomlevel of the image and the offset of the top-left corner related to the top-left
  /// corner of the visible image area
  final Function(double zoomLevel, Offset offset, Size currentImageSize)? onChange;

  /// callback function when image is ready. returns max image width and height and the number of zoomlevels
  final Function(Size maxImageSize, int zoomLevels)? onImageReady;

  /// callback function for a single tap, returns the offset from the top-left corner of the original max size image
  final Function(Offset imageOffset, Offset windowOffset)? onTap;

  /// animation duration
  final Duration animationDuration;

  /// animation curve
  final Curve animationCurve;

  /// animationSync. If true, the onChange callback function will be triggered each animation frame, if false (default) the onChange
  /// callback function will only be triggered at the end of the animation. Usefull if you want to animate something else in your app
  /// in sync with the zoomify widget.
  final bool animationSync;

  /// enable interactive zooming and panning. If false you have to manipulate the image yourself through the controller
  final bool interactive;

  /// don't allow image to become smaller then the available space
  final bool fitImage;

  /// the controller to use if you need to programmatically pan or zoom the image
  final ZoomifyController? controller;

  const Zoomify(
      {super.key,
      required this.baseUrl,
      this.backgroundColor = Colors.black12,
      this.showZoomButtons = false,
      this.showPanButtons = false,
      this.showResetButton = false,
      this.buttonPosition = Alignment.bottomRight,
      this.buttonColor = Colors.white,
      this.showGrid = false,
      this.onChange,
      this.onImageReady,
      this.onTap,
      this.animationDuration = const Duration(milliseconds: 500),
      this.animationCurve = Curves.easeOut,
      this.animationSync = false,
      this.interactive = true,
      this.fitImage = true,
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
  Size _maxImageSize = Size.zero;
  double _maxZoomLevel = 0;
  List<Map<String, dynamic>> _zoomRowCols = [];
  Map<String, int> _tileGroupMapping = {};
  bool _imageDataReady = false;
  bool _imageReady = false;
  Offset _zoomCenter = Offset.infinite;
  Offset _panTo = Offset.infinite;
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
    widget.controller?.removeListener(() => _controllerFunctions());
    widget.controller?.dispose();
  }

  void _controllerFunctions() {
    switch (widget.controller!._controllerSetMethod) {
      case 'reset':
        setState(() => _setInitialImageData());
      case 'zoomAndPan':
        _zoomAndPan(
            zoomLevel: widget.controller!._controllerZoomLevel,
            zoomCenter: widget.controller!._controllerZoomCenter == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerZoomCenter.clamp(Offset.zero, Offset(_windowWidth, _windowHeight)),
            panOffset: widget.controller!._controllerPanOffset,
            panTo: widget.controller!._controllerPanTo == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerPanTo.clamp(Offset.zero, Offset(_maxImageSize.width, _maxImageSize.height)));
      case 'animateZoomAndPan':
        _animateZoomAndPan(
            zoomLevel: widget.controller!._controllerZoomLevel,
            zoomCenter: widget.controller!._controllerZoomCenter == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerZoomCenter.clamp(Offset.zero, Offset(_windowWidth, _windowHeight)),
            panOffset: widget.controller!._controllerPanOffset,
            panTo: widget.controller!._controllerPanTo == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerPanTo.clamp(Offset.zero, Offset(_maxImageSize.width, _maxImageSize.height)));
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
      _maxImageSize = Size(_imageWidth, _imageHeight);
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
        // imagedata is ready but the image itself is not properly scaled within the window yet
        _setInitialImageData(); //
      }
      return Container(
          color: widget.backgroundColor,
          child: !widget.interactive
              ? _buildZoomifyImage()
              : Stack(children: [
                  Listener(
                      // listen to mousewheel scrolls
                      onPointerSignal: (pointerSignal) => setState(() {
                            if (pointerSignal is PointerScrollEvent) {
                              _zoomAndPan(zoomLevel: _zoomLevel - pointerSignal.scrollDelta.dy / 500, zoomCenter: pointerSignal.position);
                            }
                          }),
                      child: KeyboardListener(
                          // listen to keyboard events
                          focusNode: _focusNode,
                          onKeyEvent: (event) => _handleKeyEvent(event),
                          child: GestureDetector(
                              // listen to touchscreen and mouse gestures
                              onScaleUpdate: (scaleDetails) => setState(() => _handleGestures(scaleDetails)),
                              onScaleStart: (_) => _scaleStart = 1,
                              onScaleEnd: (_) => _scaleStart = 1,
                              onTapUp: (tapDetails) => widget.onTap?.call(
                                  (tapDetails.localPosition - Offset(_horOffset, _verOffset)) * _maxImageSize.width / _imageWidth,
                                  tapDetails.localPosition),
                              onDoubleTapDown: (tapDetails) =>
                                  _animateZoomAndPan(zoomCenter: tapDetails.localPosition, zoomLevel: _zoomLevel + 0.5),
                              child: _buildZoomifyImage()))),
                  Container(
                      alignment: widget.buttonPosition,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.showZoomButtons)
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                onPressed: () => _animateZoomAndPan(
                                    zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel + 0.5),
                                icon: Icon(Icons.add_box, color: widget.buttonColor)),
                            IconButton(
                                onPressed: () => _animateZoomAndPan(
                                    zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel - 0.5),
                                icon: Icon(Icons.indeterminate_check_box, color: widget.buttonColor))
                          ]),
                        if (widget.showPanButtons)
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            if (widget.showZoomButtons) Icon(Icons.horizontal_rule_rounded, color: widget.buttonColor.withAlpha(127)),
                            IconButton(
                                onPressed: () => _animateZoomAndPan(panOffset: Offset(100, 0)),
                                icon: Icon(Icons.arrow_forward, color: widget.buttonColor)),
                            IconButton(
                                onPressed: () => _animateZoomAndPan(panOffset: Offset(-100, 0)),
                                icon: Icon(Icons.arrow_back, color: widget.buttonColor)),
                            IconButton(
                                onPressed: () => _animateZoomAndPan(panOffset: Offset(0, 100)),
                                icon: Icon(Icons.arrow_downward, color: widget.buttonColor)),
                            IconButton(
                                onPressed: () => _animateZoomAndPan(panOffset: Offset(0, -100)),
                                icon: Icon(Icons.arrow_upward, color: widget.buttonColor))
                          ]),
                        if (widget.showResetButton)
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            if (widget.showZoomButtons || widget.showPanButtons)
                              Icon(Icons.horizontal_rule_rounded, color: widget.buttonColor.withAlpha(127)),
                            IconButton(
                                onPressed: () => setState(() => _setInitialImageData()),
                                icon: Icon(Icons.fullscreen_exit, color: widget.buttonColor)),
                          ])
                      ])),
                ]));
    });
  }

  Widget _buildZoomifyImage() {
    if (!_imageDataReady || !_imageReady) return SizedBox.shrink();
    // convert _zoomLevel to baseZoomLevel and scale
    int baseZoomLevel = _zoomLevel.ceil() - 1;
    double scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
    if (widget.fitImage) {
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
        // if we had to move the image, we have to call the onChange callback function ater the build
        _callOnChangeAfterBuild();
      }
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

  // set _zoomlevel, _horOffset, _verOffset, _imageWidth, _imageHeight and _zoomcenter for the initial image and set _imageReady to true
  void _setInitialImageData() {
    // routine to calculate the scale of the image, fitting in the available space
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
    _zoomCenter = Offset(_windowWidth / 2, _windowHeight / 2);
    _imageReady = true;
    // sometimes this routine is called during the build process. We call the onChange callback function after the build is ready,
    // because otherwise the onChange function cannot call setState
    _callOnChangeAfterBuild();
  }

  //
  void _handleKeyEvent(event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      switch (event.logicalKey.keyLabel) {
        case 'Arrow Right' || 'R':
          _animateZoomAndPan(panOffset: Offset(100, 0));
        case 'Arrow Left' || 'L':
          _animateZoomAndPan(panOffset: Offset(-100, 0));
        case 'Arrow Up' || 'U':
          _animateZoomAndPan(panOffset: Offset(0, -100));
        case 'Arrow Down' || 'D':
          _animateZoomAndPan(panOffset: Offset(0, 100));
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
        zoomCenter: scaleDetails.localFocalPoint,
        zoomLevel: _zoomLevel + (scaleDetails.scale - _scaleStart),
        panOffset: Offset(scaleDetails.focalPointDelta.dx, scaleDetails.focalPointDelta.dy),
        panTo: Offset.infinite);
    _scaleStart = scaleDetails.scale;
  }

  // set new pan and zoom values without animation
  void _zoomAndPan({double zoomLevel = -1, zoomCenter = Offset.infinite, panOffset = Offset.zero, panTo = Offset.infinite}) {
    _zoom(zoomLevel < 0 ? _zoomLevel : zoomLevel, zoomCenter);
    _pan(panOffset);
    _panToAbs(panTo);
    setState(() {});
    widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
  }

  // set initial pan and zoom values for pan/zoom animation and start the animation
  void _animateZoomAndPan({double zoomLevel = -1, zoomCenter = Offset.infinite, panOffset = Offset.zero, panTo = Offset.infinite}) {
    _animationController.reset(); // just in case we were already animating
    _panTween = Tween<Offset>(begin: Offset.zero, end: panOffset);
    _zoomTween = Tween<double>(begin: _zoomLevel, end: zoomLevel < 0.0 ? _zoomLevel : zoomLevel);
    _zoomCenter = zoomCenter == Offset.infinite ? _zoomCenter : zoomCenter;
    _panStart = Offset.zero;
    _panTo = panTo; // just remember the panTo value for after the animation
    _animationController.forward();
  }

  void _updateAnimation() {
    if (_animation.isCompleted) {
      _animationController.reset();
      _panToAbs(_panTo); // sorry, no animation on the panTo, calculation too complex when zooming and panning to a specific point at the
      // same time
      _panTo = Offset.infinite;
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
    _horOffset = _horOffset.clamp(10 - _imageWidth, _windowWidth - 10);
    _verOffset += (panOffset.dy as double).roundToDouble();
    _verOffset = _verOffset.clamp(10 - _imageHeight, _windowHeight - 10);
  }

  void _panToAbs(panTo) {
    if (panTo == Offset.infinite) return;
    var dx = panTo.dx.clamp(0, _maxImageSize.width);
    var dy = panTo.dy.clamp(0, _maxImageSize.height);
    var scale = _imageWidth / _maxImageSize.width;
    _horOffset = (_windowWidth / 2) - (dx * scale);
    _verOffset = (_windowHeight / 2) - (dy * scale);
    _zoomCenter = Offset(_windowWidth / 2, _windowHeight / 2);
  }

  void _zoom(zoomLevel, zoomCenter) {
    _zoomCenter = zoomCenter == Offset.infinite ? _zoomCenter : zoomCenter;
    if (zoomLevel == _zoomLevel || zoomLevel < 0) return;
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

extension on Offset {
  clamp(Offset zero, Offset offset) {
    return Offset(dx.clamp(zero.dx, offset.dx), dy.clamp(zero.dy, offset.dy));
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------
//
// The ZoomifyController closs
//
class ZoomifyController extends ChangeNotifier {
  ZoomifyController();

  double _controllerZoomLevel = -1;
  Offset _controllerZoomCenter = Offset.infinite;
  Offset _controllerPanOffset = Offset.zero;
  Offset _controllerPanTo = Offset.infinite;

  String _controllerSetMethod = '';

  /// directly zoom (zoomLevel & zoomCenter), pan relatively (panOffset) or pan absolutely (panTo).
  zoomAndPan({double zoomLevel = -1, Offset zoomCenter = Offset.infinite, Offset panOffset = Offset.zero, Offset panTo = Offset.infinite}) {
    _controllerZoomLevel = zoomLevel;
    _controllerZoomCenter = zoomCenter;
    _controllerPanOffset = panOffset;
    _controllerPanTo = panTo;
    _controllerSetMethod = 'zoomAndPan';
    notifyListeners();
  }

  /// animated  zoom (zoomLevel & zoomCenter), pan relatively (panOffset) or pan absolutely (panTo).
  animateZoomAndPan(
      {double zoomLevel = -1, Offset zoomCenter = Offset.infinite, Offset panOffset = Offset.zero, Offset panTo = Offset.infinite}) {
    _controllerZoomLevel = zoomLevel;
    _controllerZoomCenter = zoomCenter;
    _controllerPanOffset = panOffset;
    _controllerPanTo = panTo;
    _controllerSetMethod = 'animateZoomAndPan';
    notifyListeners();
  }

  /// reset image to initial state
  reset() {
    _controllerSetMethod = 'reset';
    notifyListeners();
  }

  /// Get the current zoomlevel. Each whole number down from the maximum zoomlevel halves the size of the image. The fraction is the
  /// scale between the two levels
  double getZoomLevel() => _zoomLevel;

  /// Get the current offset of the top-left corner of the image related to the top-left corner of the visible image area
  Offset getOffset() => Offset(_horOffset, _verOffset);

  /// Get the current size of the image. You can get the absolute scale by dividing the current image size by the max image size
  Size getCurrentImageSize() => Size(_imageWidth, _imageHeight);
}
