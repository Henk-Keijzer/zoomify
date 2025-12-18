library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_network_image/flutter_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;

enum ImageType { zoomify, dzi }

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

  final bool buttonOrderReversed;

  /// buttonAxis
  final Axis buttonAxis;

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
      this.buttonAxis = Axis.vertical,
      this.buttonOrderReversed = false,
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
  ImageType? _imageType;
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
  double _fitZoomLevel = 0;
  String _format = 'jpg';
  double _overlap = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(() => _controllerFunctions());
    _animationController = AnimationController(duration: widget.animationDuration, vsync: this);
    _animation = CurvedAnimation(parent: _animationController, curve: widget.animationCurve)..addListener(() => _updateAnimation());
    _loadImageData();
  }

  @override
  void didUpdateWidget(Zoomify oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) _loadImageData();
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
            zoomLevel: widget.fitImage && widget.controller!._controllerZoomLevel < _fitZoomLevel
                ? _fitZoomLevel
                : widget.controller!._controllerZoomLevel,
            zoomCenter: widget.controller!._controllerZoomCenter == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerZoomCenter.clamp(Offset.zero, Offset(_windowWidth, _windowHeight)),
            panOffset: widget.controller!._controllerPanOffset,
            panTo: widget.controller!._controllerPanTo == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerPanTo.clamp(Offset.zero, Offset(_maxImageSize.width, _maxImageSize.height)));
      case 'animateZoomAndPan':
        _animateZoomAndPan(
            zoomLevel: widget.fitImage && widget.controller!._controllerZoomLevel < _fitZoomLevel
                ? _fitZoomLevel
                : widget.controller!._controllerZoomLevel,
            zoomCenter: widget.controller!._controllerZoomCenter == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerZoomCenter.clamp(Offset.zero, Offset(_windowWidth, _windowHeight)),
            panOffset: widget.controller!._controllerPanOffset,
            panTo: widget.controller!._controllerPanTo == Offset.infinite
                ? Offset.infinite
                : widget.controller!._controllerPanTo.clamp(Offset.zero, Offset(_maxImageSize.width, _maxImageSize.height)));
    }
  }

  Future<void> _loadImageData() async {
    _zoomRowCols = [];
    _tileGroupMapping = {};
    _imageDataReady = false;
    _imageReady = false;
    // zoomify or deep zoom image?
    var response = await http.get(Uri.parse(path.join(widget.baseUrl, 'ImageProperties.xml')));
    if (response.statusCode == 200) {
      _imageType = ImageType.zoomify;
      _loadZoomifyData(response.body);
      return;
    }
    _imageType = ImageType.dzi;
    response = await http.get(Uri.parse(path.join(widget.baseUrl, 'image.xml')));
    if (response.statusCode == 200) {
      _loadDziData(response.body);
      return;
    }
    response = await http.get(Uri.parse(path.join(widget.baseUrl, 'image.dzi')));
    if (response.statusCode == 200) {
      _loadDziData(response.body);
      return;
    }
    response = await http.get(Uri.parse(path.join(widget.baseUrl, 'image.js')));
    if (response.statusCode == 200) {
      _loadDziData(response.body);
      return;
    }
    throw Exception('Failed to load image data');
  }

  void _loadZoomifyData(String responseBody) {
    // get the essentials from the ImageProperties.xml
    final attributes = XmlDocument.parse(responseBody).getElement("IMAGE_PROPERTIES")?.attributes ?? [];
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
    _overlap = 0; // always 0 for zoomify images
    _format = 'jpg'; // always jpg for zoomify images
    _maxImageSize = Size(_imageWidth, _imageHeight);
    _zoomRowCols = _createZoomRowColsMap(_maxImageSize, _tileSize);
    _maxZoomLevel = _zoomRowCols.length.toDouble();
    // specifically for zoomify images: make a Map with the filename as string and as value the tilegroup number
    var tiles = 0;
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
  }

  void _loadDziData(String responseBody) {
    try {
      // Attempt to parse as XML first.
      final document = XmlDocument.parse(responseBody);
      final imageElement = document.rootElement;
      final dziNamespace = imageElement.namespaceUri;
      _tileSize = int.parse(imageElement.getAttribute('TileSize')!);
      _overlap = double.parse(imageElement.getAttribute('Overlap')!);
      _format = imageElement.getAttribute('Format')!;
      final sizeElement = imageElement.findElements('Size', namespace: dziNamespace).first;
      _maxImageSize = Size(
        double.parse(sizeElement.getAttribute('Width')!),
        double.parse(sizeElement.getAttribute('Height')!),
      );
    } on XmlException {
      // If XML parsing fails, treat it as JSON or a JS-wrapped JSON.
      String jsonString = responseBody;
      // Check if it's a JavaScript-style callback (e.g., "highsmith({...});").
      int openParen = jsonString.indexOf('(');
      int closeParen = jsonString.lastIndexOf(')');
      if (openParen != -1 && closeParen != -1) {
        jsonString = jsonString.substring(openParen + 1, closeParen);
      }
      final dziData = jsonDecode(jsonString);
      _tileSize = int.parse(dziData['Image']['TileSize'].toString());
      _overlap = double.parse(dziData['Image']['Overlap'].toString());
      _format = dziData['Image']['Format'];
      _maxImageSize = Size(
        double.parse(dziData['Image']['Size']['Width'].toString()),
        double.parse(dziData['Image']['Size']['Height'].toString()),
      );
    }
    _zoomRowCols = _createZoomRowColsMap(_maxImageSize, _tileSize);
    _maxZoomLevel = _zoomRowCols.length.toDouble();
    _imageDataReady = true;
    widget.onImageReady?.call(Size(_imageWidth, _imageHeight), _zoomRowCols.length);
    setState(() {});
  }

  List<Map<String, dynamic>> _createZoomRowColsMap(Size maxImageSize, int tileSize) {
    //  make a list  with the number of rows, number of colums, image widths and image heights per zoomlevel (in reverse
    // order, i.e zoomlevel 0 is the smallest image, for zoomify the image that fits in tileSize x tileSize pixels, for DZI 1 x 1)
    var calcWidth = maxImageSize.width;
    var calcHeight = maxImageSize.height;
    List<Map<String, dynamic>> zoomRowCols = [];
    var loop = true; // start with any value > 1
    while (loop) {
      var rows = (calcHeight / _tileSize).ceil();
      var cols = (calcWidth / _tileSize).ceil();
      zoomRowCols.insert(0, {'rows': rows, 'cols': cols, 'width': calcWidth, 'height': calcHeight});
      loop = _imageType == ImageType.zoomify ? rows * cols > 1 : (calcWidth > 1 || calcHeight > 1);
      calcWidth = (calcWidth / 2).ceilToDouble();
      calcHeight = (calcHeight / 2).ceilToDouble();
    }
    return zoomRowCols;
  }

  @override
  Widget build(BuildContext context) {
    FocusScope.of(context).requestFocus(_focusNode); // for keyboard entry
    List<Widget> buttonList = _createButtonList(); // prepare the button list
    if (widget.buttonOrderReversed) buttonList = buttonList.reversed.toList();
    if (!_imageDataReady) return const SizedBox.shrink();
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      // use LayoutBuilder to get the current window size
      _windowWidth = constraints.maxWidth;
      _windowHeight = constraints.maxHeight;
      if (_imageDataReady && !_imageReady) {
        // imagedata is ready but the image itself is not properly scaled within the window yet
        _setInitialImageData(); //
      }
      // 1. Calculate the necessary zoom and scale values.
      int targetZoom = _zoomLevel.ceil() - 1;
      if (targetZoom < 0) targetZoom = 0; // Guard against initial state
      double targetScale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();

      // 2. Calculate the correct offsets BEFORE building the interactive widgets.
      Offset newOffset = _fitImageToScreen(targetZoom, targetScale);

      // 3. IMPORTANT: If the offset has changed, we must trigger a rebuild.
      // We do this safely using a post-frame callback to avoid the "setState during build" error.
      if (newOffset != Offset(_horOffset, _verOffset)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _horOffset = newOffset.dx;
              _verOffset = newOffset.dy;
            });
          }
        });
      }

      return Container(
          color: widget.backgroundColor,
          child: !widget.interactive
              ? _buildImage(Offset(_horOffset, _verOffset)) // Pass the current, correct offset
              : Stack(children: [
                  Listener(
                      onPointerSignal: (pointerSignal) => setState(() {
                            if (pointerSignal is PointerScrollEvent) {
                              _zoomAndPan(zoomLevel: _zoomLevel - pointerSignal.scrollDelta.dy / 500, zoomCenter: pointerSignal.position);
                            }
                          }),
                      child: KeyboardListener(
                          focusNode: _focusNode,
                          onKeyEvent: (event) => _handleKeyEvent(event),
                          child: GestureDetector(
                              onScaleStart: (_) {
                                _scaleStart = 1;
                              },
                              onScaleUpdate: (scaleDetails) => setState(() => _handleGestures(scaleDetails)),
                              onScaleEnd: (_) => _scaleStart = 1,
                              onTapUp: (tapDetails) => widget.onTap?.call(
                                  (tapDetails.localPosition - Offset(_horOffset, _verOffset)) * _maxImageSize.width / _imageWidth,
                                  tapDetails.localPosition),
                              onDoubleTapDown: (tapDetails) =>
                                  _animateZoomAndPan(zoomCenter: tapDetails.localPosition, zoomLevel: _zoomLevel + 0.5),
                              child: Container(color: Colors.transparent, child: _buildImage(Offset(_horOffset, _verOffset)))))),
                  // Pass the current, correct offset
                  Container(
                      alignment: widget.buttonPosition,
                      child: widget.buttonAxis == Axis.horizontal
                          ? Row(mainAxisSize: MainAxisSize.min, children: buttonList)
                          : Column(mainAxisSize: MainAxisSize.min, children: buttonList))
                ]));
    });
  }

  Widget _buildImage(Offset horVerOffset) {
    if (!_imageDataReady || !_imageReady) return const SizedBox.shrink();

    // 1. Calculate Target (Where we are going)
    int targetZoom = _zoomLevel.ceil() - 1;
    if (targetZoom < 0) targetZoom = 0;
    double targetScale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();

    // 2. Calculate Fallback (Where we likely came from / Lower res)
    // Logic: Always use the level *below* the target as the stable foundation.
    // Even if we are zooming out, the lower level is usually cached or smaller/faster to load.
    int fallbackZoom = targetZoom - 1;

    List<Widget> layers = [];

    // 3. Build Fallback Layer
    if (fallbackZoom >= 0) {
      // Calculate scale for fallback relative to current zoom
      // If _zoomLevel is 6.1, fallback (5) needs to be scaled by ~2.14
      double fallbackScale = pow(2, _zoomLevel - (fallbackZoom + 1)).toDouble();

      // Both layers use the SAME offset. The logic inside _buildTileLayer handles the scaling.
      layers.add(_buildTileLayer(zoomLevel: fallbackZoom, scale: fallbackScale, offset: horVerOffset));
    }

    // 4. Build Target Layer
    layers.add(_buildTileLayer(zoomLevel: targetZoom, scale: targetScale, offset: horVerOffset));

    return SizedBox(
      width: _windowWidth,
      height: _windowHeight,
      child: Stack(children: layers),
    );
  }

  Offset _fitImageToScreen(int zoomLevel, double scale) {
    // Recalculate the current image dimensions based on the target zoom and scale.
    final zoomData = _zoomRowCols[zoomLevel];
    final currentImageWidth = zoomData['width'] * scale;
    final currentImageHeight = zoomData['height'] * scale;
    // If fitImage is true and the image is smaller than the window, reset.
    if (widget.fitImage && (currentImageWidth < _windowWidth || currentImageHeight < _windowHeight)) {
      //    _setInitialImageData();
      return Offset(_horOffset, _verOffset);
    }
    double horOffset = _horOffset;
    double verOffset = _verOffset;

    // If image is smaller than window in one dimension, center it.
    if (currentImageHeight < _windowHeight) {
      // Center vertically
      verOffset = (_windowHeight - currentImageHeight) / 2;
    }
    if (currentImageWidth < _windowWidth) {
      // Center horizontally
      horOffset = (_windowWidth - currentImageWidth) / 2;
    }
    // If image is larger than the window, ensure no black borders are visible.
    // This clamps the offset so the image edges cannot be panned inside the window frame.
    if (currentImageHeight >= _windowHeight) {
      verOffset = verOffset.clamp(_windowHeight - currentImageHeight, 0);
    }
    if (currentImageWidth >= _windowWidth) {
      horOffset = horOffset.clamp(_windowWidth - currentImageWidth, 0);
    }
    // Round the final offsets to avoid sub-pixel rendering issues.
    return Offset(horOffset.roundToDouble(), verOffset.roundToDouble());
  }

  Widget _buildTileLayer({required int zoomLevel, required double scale, required Offset offset}) {
    // prepare some values
    final zoomData = _zoomRowCols[zoomLevel];
    final int rows = zoomData['rows'];
    final int cols = zoomData['cols'];
    final double width = zoomData['width'];
    final double height = zoomData['height'];
    final double scaledTileSize = _tileSize * scale;
    const int buffer = 1;

    // Calculate raw visible bounds
    final int rawStartCol = offset.dx < 0 ? (-offset.dx / scaledTileSize).floor() : 0;
    final int rawEndCol = cols > 0 ? min(cols, ((_windowWidth - offset.dx) / scaledTileSize).ceil()) : 0;
    final int rawStartRow = offset.dy < 0 ? (-offset.dy / scaledTileSize).floor() : 0;
    final int rawEndRow = rows > 0 ? min(rows, ((_windowHeight - offset.dy) / scaledTileSize).ceil()) : 0;

    // Apply buffer and clamp to valid range [0, cols] or [0, rows]
    final int startCol = (rawStartCol - buffer).clamp(0, cols);
    final int endCol = (rawEndCol + buffer).clamp(0, cols);
    final int startRow = (rawStartRow - buffer).clamp(0, rows);
    final int endRow = (rawEndRow + buffer).clamp(0, rows);

    // Calculate the screen position of the top-left corner of the *buffered* grid.
    // The tileGridStartX/Y must correspond to the startCol/startRow calculated above.
    final double tileGridStartX = offset.dx + (startCol * scaledTileSize);
    final double tileGridStartY = offset.dy + (startRow * scaledTileSize);

    List<Widget> tiles = [];
    for (int r = startRow; r < endRow; r++) {
      for (int c = startCol; c < endCol; c++) {
        final double overlapLeft = (c == 0) ? 0.0 : _overlap;
        final double overlapTop = (r == 0) ? 0.0 : _overlap;
        final double overlapRight = (c == cols - 1) ? 0.0 : _overlap;
        final double overlapBottom = (r == rows - 1) ? 0.0 : _overlap;

        final double contentWidth;
        if (c == cols - 1) {
          final remainder = width % _tileSize;
          contentWidth = (remainder == 0 && width > 0) ? _tileSize.toDouble() : remainder;
        } else {
          contentWidth = _tileSize.toDouble();
        }

        final double contentHeight;
        if (r == rows - 1) {
          final remainder = height % _tileSize;
          contentHeight = (remainder == 0 && height > 0) ? _tileSize.toDouble() : remainder;
        } else {
          contentHeight = _tileSize.toDouble();
        }

        final double actualTileWidth = contentWidth + overlapLeft + overlapRight;
        final double actualTileHeight = contentHeight + overlapTop + overlapBottom;

        // The tile's position is its index (c, r) relative to the start index (startCol, startRow),
        // offset from the grid's starting screen position.
        final tileX = tileGridStartX + ((c - startCol) * scaledTileSize) - (overlapLeft * scale);
        final tileY = tileGridStartY + ((r - startRow) * scaledTileSize) - (overlapTop * scale);

        String imageUrl;
        if (_imageType == ImageType.dzi) {
          imageUrl = path.join(widget.baseUrl, 'image_files', zoomLevel.toString(), '${c}_$r.$_format');
        } else {
          imageUrl = path.join(widget.baseUrl, 'TileGroup${_tileGroupMapping['$zoomLevel-$c-$r.jpg']}', '$zoomLevel-$c-$r.jpg');
        }

        tiles.add(Transform.translate(
            offset: Offset(tileX, tileY),
            child: SizedBox(
                width: actualTileWidth * scale,
                height: actualTileHeight * scale,
                child: Image(
                  key: ValueKey(imageUrl),
                  gaplessPlayback: true,
                  image: NetworkImageProvider(imageUrl, retryWhen: (Attempt attempt) => attempt.counter < 10),
                  fit: BoxFit.fill,
                  width: actualTileWidth * scale,
                  height: actualTileHeight * scale,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ))));
      }
    }
    return Stack(children: tiles);
  }

  Future<void> _callOnChangeAfterBuild() async {
    await Future.delayed(Duration.zero);
    widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
  }

  List<Widget> _createButtonList() {
    return [
      if (widget.showZoomButtons)
        IconButton(
            onPressed: () => _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel + 0.5),
            icon: Icon(Icons.add_box, color: widget.buttonColor)),
      if (widget.showZoomButtons)
        IconButton(
          onPressed: () => _animateZoomAndPan(
              zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2),
              zoomLevel: widget.fitImage && (_zoomLevel - 0.5) < _fitZoomLevel ? _fitZoomLevel : _zoomLevel - 0.5),
          icon: Icon(Icons.indeterminate_check_box, color: widget.buttonColor),
        ),
      if (widget.showPanButtons && widget.showZoomButtons)
        RotatedBox(
            quarterTurns: widget.buttonAxis == Axis.horizontal ? 1 : 0,
            child: Icon(Icons.horizontal_rule_rounded, color: widget.buttonColor.withAlpha(127))),
      if (widget.showPanButtons)
        IconButton(
          onPressed: () => _animateZoomAndPan(panOffset: Offset(100, 0)),
          icon: Icon(Icons.arrow_forward, color: widget.buttonColor),
        ),
      if (widget.showPanButtons)
        IconButton(
          onPressed: () => _animateZoomAndPan(panOffset: Offset(-100, 0)),
          icon: Icon(Icons.arrow_back, color: widget.buttonColor),
        ),
      if (widget.showPanButtons)
        IconButton(
          onPressed: () => _animateZoomAndPan(panOffset: Offset(0, 100)),
          icon: Icon(Icons.arrow_downward, color: widget.buttonColor),
        ),
      if (widget.showPanButtons)
        IconButton(
            onPressed: () => _animateZoomAndPan(panOffset: Offset(0, -100)), icon: Icon(Icons.arrow_upward, color: widget.buttonColor)),
      if (widget.showResetButton && (widget.showZoomButtons || widget.showPanButtons))
        RotatedBox(
            quarterTurns: widget.buttonAxis == Axis.horizontal ? 1 : 0,
            child: Icon(Icons.horizontal_rule_rounded, color: widget.buttonColor.withAlpha(127))),
      if (widget.showResetButton)
        IconButton(
          onPressed: () => setState(() => _setInitialImageData()),
          icon: Icon(Icons.fullscreen_exit, color: widget.buttonColor),
        ),
    ];
  }

  // set _zoomlevel, _horOffset, _verOffset, _imageWidth, _imageHeight and _zoomcenter for the initial image and set _imageReady to true
  void _setInitialImageData() {
    // a local routine to calculate the scale of the image, fitting in the available space
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
    _fitZoomLevel = _zoomLevel;
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
  void _handleKeyEvent(dynamic event) {
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
          _animateZoomAndPan(
              zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2),
              zoomLevel: widget.fitImage && (_zoomLevel - 0.2) < _fitZoomLevel ? _fitZoomLevel : _zoomLevel - 0.2);
      }
    }
  }

  // translate gestures to pan and zoom values
  void _handleGestures(dynamic scaleDetails) {
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
      _panToAbs(_panTo); // sorry, no animation on the panTo (yet), calculation too complex when zooming and panning to a specific point at
      // the same time
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

  void _pan(dynamic panOffset) {
    _horOffset += (panOffset.dx as double).roundToDouble();
    _horOffset = _horOffset.clamp(10 - _imageWidth, _windowWidth - 10);
    _verOffset += (panOffset.dy as double).roundToDouble();
    _verOffset = _verOffset.clamp(10 - _imageHeight, _windowHeight - 10);
  }

  void _panToAbs(dynamic panTo) {
    if (panTo == Offset.infinite) return;
    var dx = panTo.dx.clamp(0, _maxImageSize.width);
    var dy = panTo.dy.clamp(0, _maxImageSize.height);
    var scale = _imageWidth / _maxImageSize.width;
    _horOffset = (_windowWidth / 2) - (dx * scale);
    _verOffset = (_windowHeight / 2) - (dy * scale);
    _zoomCenter = Offset(_windowWidth / 2, _windowHeight / 2);
  }

  void _zoom(dynamic zoomLevel, dynamic zoomCenter) {
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
  Offset clamp(Offset zero, Offset offset) {
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
  void zoomAndPan(
      {double zoomLevel = -1, Offset zoomCenter = Offset.infinite, Offset panOffset = Offset.zero, Offset panTo = Offset.infinite}) {
    _controllerZoomLevel = zoomLevel;
    _controllerZoomCenter = zoomCenter;
    _controllerPanOffset = panOffset;
    _controllerPanTo = panTo;
    _controllerSetMethod = 'zoomAndPan';
    notifyListeners();
  }

  /// animated  zoom (zoomLevel & zoomCenter), pan relatively (panOffset) or pan absolutely (panTo).
  void animateZoomAndPan(
      {double zoomLevel = -1, Offset zoomCenter = Offset.infinite, Offset panOffset = Offset.zero, Offset panTo = Offset.infinite}) {
    _controllerZoomLevel = zoomLevel;
    _controllerZoomCenter = zoomCenter;
    _controllerPanOffset = panOffset;
    _controllerPanTo = panTo;
    _controllerSetMethod = 'animateZoomAndPan';
    notifyListeners();
  }

  /// reset image to initial state
  void reset() {
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
