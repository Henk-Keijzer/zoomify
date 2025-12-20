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
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../src/zoomify_controller.dart';
export '../src/zoomify_controller.dart';

enum ImageType { zoomify, dzi }

extension on Offset {
  Offset clamp(Offset zero, Offset offset) {
    return Offset(dx.clamp(zero.dx, offset.dx), dy.clamp(zero.dy, offset.dy));
  }
}

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

  /// panbutton offset in pixels, default 100, a negative value reverses the direction of the buttons
  final double panButtonOffset;

  /// show reset button, default false
  final bool showResetButton;

  /// zoombutton position, default Alignment.bottomRight
  final Alignment buttonPosition;

  /// zoom/pan/reset order, default false
  final bool buttonOrderReversed;

  /// buttonAxis, default Axis.vertical
  final Axis buttonAxis;

  /// zoombutton color, default Colors.white
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
      this.panButtonOffset = 100,
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
// ZoomifyState
//
class ZoomifyState extends State<Zoomify> with SingleTickerProviderStateMixin {
  double _zoomLevel = 0;
  double _horOffset = 0;
  double _verOffset = 0;
  double _imageWidth = 0;
  double _imageHeight = 0;
  double _windowWidth = 0;
  double _windowHeight = 0;
  ImageType? _imageType;
  int _tileSize = 256;
  Size _maxImageSize = Size.zero;
  double _maxZoomLevel = 0;
  List<Map<String, dynamic>> _zoomRowCols = [];
  Map<String, int> _tileGroupMapping = {};
  bool _imageDataReady = false;
  bool _imagePositioned = false;
  Offset _zoomCenter = Offset.infinite;
  Offset _panTo = Offset.infinite;
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _animation;
  Tween<double> _zoomTween = Tween<double>(begin: 0, end: 0);
  Tween<Offset> _panTween = Tween<Offset>(begin: Offset.zero, end: Offset.zero);
  Offset _panStart = Offset.zero;
  double _scaleStart = 1;
  double _fitZoomLevel = 0;
  String _format = 'jpg';
  double _overlap = 0;
  StreamSubscription<ZoomifyEvent>? _controllerSubscription;

  @override
  void initState() {
    super.initState();
    // setup listener for controller events (i.e. the main app wants to zoom, pan, reset, programmatically)
    _controllerSubscription = widget.controller?.events.listen((event) => _handleControllerEvent(event));
    // setup the animation stuff
    _animationController = AnimationController(duration: widget.animationDuration, vsync: this);
    _animation = CurvedAnimation(parent: _animationController, curve: widget.animationCurve)..addListener(() => _updateAnimation());
    // load the image data from the description file
    _loadImageData();
  }

  @override
  void didUpdateWidget(Zoomify oldWidget) {
    super.didUpdateWidget(oldWidget);
    // the following widget parameters need action when they are updated
    if (oldWidget.baseUrl != widget.baseUrl) _loadImageData();
    if (oldWidget.animationDuration != widget.animationDuration) _animationController.duration = widget.animationDuration;
    if (oldWidget.animationCurve != widget.animationCurve) {
      _animation = CurvedAnimation(parent: _animationController, curve: widget.animationCurve);
    }
    // all other widget parameters are directly accessed by the methods in the state class
    setState(() {});
  }

  @override
  void dispose() {
    _controllerSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadImageData() async {
    _zoomRowCols = [];
    _tileGroupMapping = {};
    _imageDataReady = false;
    _imagePositioned = false;
    // go get the description file, first see if it mis Zoomify
    var response = await http.get(Uri.parse(path.join(widget.baseUrl, 'ImageProperties.xml')));
    if (response.statusCode == 200) {
      _imageType = ImageType.zoomify;
      _loadZoomifyData(response.body);
      return;
    }
    // it must be a Deep Zoom Image .xml or .dzi => xml, .json or .jsonp => json
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
    // none of the above...
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
    // _zoomRowCols is a list of maps. See _createZoomRowColsMap for deytailed info
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
    // inform the caller that the image is ready
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
    //
    _zoomRowCols = _createZoomRowColsMap(_maxImageSize, _tileSize);
    _maxZoomLevel = _zoomRowCols.length.toDouble();
    _imageDataReady = true;
    widget.onImageReady?.call(Size(_imageWidth, _imageHeight), _zoomRowCols.length);
    setState(() {});
  }

  List<Map<String, dynamic>> _createZoomRowColsMap(Size maxImageSize, int tileSize) {
    // make a list  with the number of rows, number of colums, image widths and image heights per zoomlevel (in reverse
    // order, i.e zoomlevel 0 is the smallest image: for zoomify the image that fits in tileSize x tileSize pixels, for DZI 1 x 1)
    var calcWidth = maxImageSize.width;
    var calcHeight = maxImageSize.height;
    List<Map<String, dynamic>> zoomRowCols = [];
    var loop = true;
    while (loop) {
      var rows = (calcHeight / _tileSize).ceil();
      var cols = (calcWidth / _tileSize).ceil();
      zoomRowCols.insert(0, {'rows': rows, 'cols': cols, 'width': calcWidth, 'height': calcHeight});
      // loop until the image is smaller than the tileSize (Zoomify) or the image is 1x1 pixels (DZI)
      loop = _imageType == ImageType.zoomify ? rows * cols > 1 : (calcWidth > 1 || calcHeight > 1);
      // prepare for the next zoomlevel
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
    // wait until the image data is ready. Until then just return an empty screen. It is up to the user to show a fancy loading screen
    if (!_imageDataReady) return const SizedBox.shrink();
    // use LayoutBuilder to get the window size that has been given to us
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      bool isResizing = false;
      if (_windowWidth != constraints.maxWidth || _windowHeight != constraints.maxHeight) {
        isResizing = true;
        _windowWidth = constraints.maxWidth;
        _windowHeight = constraints.maxHeight;
        if (_imagePositioned) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _positionInitialImage();
          });
        }
      }
      // the image must be positioned properly. If not done so yet, do it now.
      if (_imageDataReady && !_imagePositioned) {
        // imagedata is ready but the image itself is not properly scaled within the window yet
        _positionInitialImage(); //
      }
      // Calculate the necessary zoom and scale values.
      int targetZoom = _zoomLevel.ceil() - 1;
      if (targetZoom < 0) targetZoom = 0; // Guard against initial state
      double targetScale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
      // Calculate the correct offsets, while at the same time ensuring the image is still properly positioned within the window
      Offset newOffset = _fitImageToScreen(targetZoom, targetScale);
      // If the offset has changed, we must trigger a rebuild.
      if (!isResizing && newOffset != Offset(_horOffset, _verOffset)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _horOffset = newOffset.dx;
              _verOffset = newOffset.dy;
            });
          }
        });
      }
      // now we can build the interactive widget, which is a container with the appropriate color and the (interactive) image
      return Container(
          color: widget.backgroundColor,
          child: !widget.interactive
              ? _buildImage(Offset(_horOffset, _verOffset))
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
                              onScaleStart: (_) => _scaleStart = 1,
                              onScaleUpdate: (scaleDetails) => setState(() => _handleGestures(scaleDetails)),
                              onScaleEnd: (details) => _fling(details),
                              onTapUp: (tapDetails) => widget.onTap?.call(
                                  (tapDetails.localPosition - Offset(_horOffset, _verOffset)) * _maxImageSize.width / _imageWidth,
                                  tapDetails.localPosition),
                              onDoubleTapDown: (tapDetails) =>
                                  _animateZoomAndPan(zoomCenter: tapDetails.localPosition, zoomLevel: _zoomLevel + 0.5),
                              child: Container(color: Colors.transparent, child: _buildImage(Offset(_horOffset, _verOffset)))))),
                  // add the buttons (note: the buttonlist may be empty)
                  Container(
                      alignment: widget.buttonPosition,
                      child: widget.buttonAxis == Axis.horizontal
                          ? Row(mainAxisSize: MainAxisSize.min, children: buttonList)
                          : Column(mainAxisSize: MainAxisSize.min, children: buttonList))
                ]));
    });
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // build the visible part of the image to display
  //
  Widget _buildImage(Offset horVerOffset) {
    if (!_imageDataReady || !_imagePositioned) return const SizedBox.shrink();
    // We are going to make two layers with image tiles. The lower (fallback) layer contains the images of a zoomlevel one lower then
    // the zoomlevel we finally want, but scaled to exactly match the upper (target) layer. That means that if the tiles of the upper
    // image are loaded from the server and not yet rendered, the user still sees the (not so sharp) image of the fallback layer
    // Logic: Always use the level *below* the target as the stable foundation.
    // Even if we are zooming out, the lower level is usually cached or smaller/faster to load.
    List<Widget> layers = [];
    // Calculate top layer zoom and scale
    int targetZoom = _zoomLevel.ceil() - 1;
    if (targetZoom < 0) targetZoom = 0;
    double targetScale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
    // Calculate Fallback layer zoom and scale
    int fallbackZoom = targetZoom - 1;
    if (fallbackZoom >= 0) {
      // Calculate scale for fallback relative to current zoom
      // If _zoomLevel is 6.1, fallback (5) needs to be scaled by ~2.14
      double fallbackScale = pow(2, _zoomLevel - (fallbackZoom + 1)).toDouble();
      // and build the fallback layer
      layers.add(_buildTileLayer(zoomLevel: fallbackZoom, scale: fallbackScale, offset: horVerOffset));
    }
    // Build Target Layer
    layers.add(_buildTileLayer(zoomLevel: targetZoom, scale: targetScale, offset: horVerOffset));
    // and return the stack of two layer fit to the window size
    return RepaintBoundary(
        child: SizedBox(
      width: _windowWidth,
      height: _windowHeight,
      child: Stack(children: layers),
    ));
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // the visible image consists of two layers. Each layer is created here. The layer only contains the image tiles that are visible plus
  // a set of tiles around that, so we have a buffer in case the user starts panning
  //
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
    // Apply buffer and clamp to valid range [0, cols] or [0, rows] to ensure were stay within the bounds of the total image
    final int startCol = (rawStartCol - buffer).clamp(0, cols);
    final int endCol = (rawEndCol + buffer).clamp(0, cols);
    final int startRow = (rawStartRow - buffer).clamp(0, rows);
    final int endRow = (rawEndRow + buffer).clamp(0, rows);
    // Calculate the screen position of the top-left corner of the *buffered* grid.
    // The tileGridStartX/Y must correspond to the startCol/startRow calculated above.
    final double tileGridStartX = offset.dx + (startCol * scaledTileSize);
    final double tileGridStartY = offset.dy + (startRow * scaledTileSize);
    // now make a list of tiles, row by row, column by column
    List<Widget> tiles = [];
    for (int r = startRow; r < endRow; r++) {
      for (int c = startCol; c < endCol; c++) {
        // tiles may have overlap pixels, we need take them into account when positioning the tile correctly on the screen
        // there is no overlap at the top of the top row, the bottom of the bottom row, the left of the left column or the right of the right column
        final double overlapLeft = (c == 0) ? 0.0 : _overlap;
        final double overlapTop = (r == 0) ? 0.0 : _overlap;
        final double overlapRight = (c == cols - 1) ? 0.0 : _overlap;
        final double overlapBottom = (r == rows - 1) ? 0.0 : _overlap;
        // now calculate the size of the visible tile. Normally that is the same as the _tileSize specified in the image description,
        // but it is smaller for the last row and column
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
        // the actual size o the tile image including the overlap pixels
        final double actualTileWidth = contentWidth + overlapLeft + overlapRight;
        final double actualTileHeight = contentHeight + overlapTop + overlapBottom;
        // The tile's position is its index (c, r) relative to the start index (startCol, startRow),
        // offset from the grid's starting screen position.
        final tileX = tileGridStartX + ((c - startCol) * scaledTileSize) - (overlapLeft * scale);
        final tileY = tileGridStartY + ((r - startRow) * scaledTileSize) - (overlapTop * scale);
        //
        // now get the url of the image on the server
        String imageUrl;
        if (_imageType == ImageType.dzi) {
          imageUrl = path.join(widget.baseUrl, 'image_files', zoomLevel.toString(), '${c}_$r.$_format');
        } else {
          imageUrl = path.join(widget.baseUrl, 'TileGroup${_tileGroupMapping['$zoomLevel-$c-$r.jpg']}', '$zoomLevel-$c-$r.jpg');
        }
        // finally we add the image at the right offset in a tile and add the tile to the list of mtiles
        tiles.add(Transform.translate(
            offset: Offset(tileX, tileY),
            child: Container(
                decoration: widget.showGrid ? BoxDecoration(border: Border.all(color: Colors.black, width: 0.5)) : null,
                width: actualTileWidth * scale,
                height: actualTileHeight * scale,
                child: Image(
                  // we use the imageUrl as ValueKey. that means that the image is uniquely identified and can be reloaded from cache
                  // even if it is moved to another place in the tree (in our case moved to the other layer)
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

  //----------------------------------------------------------------------------------------------------------------------------------------
  // on every re-build of the screen we want to make sure the image is properly positioned within the window
  //
  Offset _fitImageToScreen(int zoomLevel, double scale) {
    // Recalculate the current image dimensions based on the target zoom and scale.
    final zoomData = _zoomRowCols[zoomLevel];
    final currentImageWidth = zoomData['width'] * scale;
    final currentImageHeight = zoomData['height'] * scale;
    // If fitImage is true and the image is smaller than the window, don't allow the image to move.
    if (widget.fitImage && (currentImageWidth < _windowWidth || currentImageHeight < _windowHeight)) {
      return Offset(_horOffset, _verOffset);
    }
    double horOffset = _horOffset;
    double verOffset = _verOffset;
    // If image is smaller than window in one dimension, center it.
    if (currentImageHeight < _windowHeight) {
      verOffset = (_windowHeight - currentImageHeight) / 2;
    }
    if (currentImageWidth < _windowWidth) {
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

  //----------------------------------------------------------------------------------------------------------------------------------------
  // this routine calls the user's onChange routine securely after a build in which the position or zoom of the image may have changed,
  // and it also update the controller with the new values in case the user calls controller.getOffset or controller.getZoomLevel
  //
  void _callOnChangeAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
        widget.controller?.updateState(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
      }
    });
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // this routine creates the list of buttons to display
  //
  List<Widget> _createButtonList() {
    return [
      if (widget.showZoomButtons) ...[
        IconButton(
            onPressed: () => _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel + 0.5),
            icon: Icon(Icons.add_box, color: widget.buttonColor)),
        IconButton(
          onPressed: () => _animateZoomAndPan(
              zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2),
              zoomLevel: widget.fitImage && (_zoomLevel - 0.5) < _fitZoomLevel ? _fitZoomLevel : _zoomLevel - 0.5),
          icon: Icon(Icons.indeterminate_check_box, color: widget.buttonColor),
        )
      ],
      if (widget.showPanButtons) ...[
        if (widget.showZoomButtons)
          RotatedBox(
              quarterTurns: widget.buttonAxis == Axis.horizontal ? 1 : 0,
              child: Icon(Icons.horizontal_rule_rounded, color: widget.buttonColor.withAlpha(127))),
        IconButton(
          onPressed: () => _animateZoomAndPan(panOffset: Offset(-widget.panButtonOffset, 0)),
          icon: Icon(Icons.arrow_forward, color: widget.buttonColor),
        ),
        IconButton(
          onPressed: () => _animateZoomAndPan(panOffset: Offset(widget.panButtonOffset, 0)),
          icon: Icon(Icons.arrow_back, color: widget.buttonColor),
        ),
        IconButton(
          onPressed: () => _animateZoomAndPan(panOffset: Offset(0, -widget.panButtonOffset)),
          icon: Icon(Icons.arrow_downward, color: widget.buttonColor),
        ),
        IconButton(
            onPressed: () => _animateZoomAndPan(panOffset: Offset(0, widget.panButtonOffset)),
            icon: Icon(Icons.arrow_upward, color: widget.buttonColor))
      ],
      if (widget.showResetButton) ...[
        if (widget.showZoomButtons || widget.showPanButtons)
          RotatedBox(
              quarterTurns: widget.buttonAxis == Axis.horizontal ? 1 : 0,
              child: Icon(Icons.horizontal_rule_rounded, color: widget.buttonColor.withAlpha(127))),
        IconButton(
          onPressed: () => setState(() => _positionInitialImage()),
          icon: Icon(Icons.fullscreen_exit, color: widget.buttonColor),
        )
      ]
    ];
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------
  // set all relevant vars (_zoomlevel, _horOffset, _verOffset, _imageWidth, _imageHeight and _zoomcenter) so that the image fits the screen
  //
  void _positionInitialImage() {
    _animationController.reset(); // stop any animation that may be running

    // define a local routine to calculate the scale of the image, fitting in the available space
    double calculateScale(double width1, double height1, double width2, double height2) {
      double scaleWidth = width2 / width1;
      double scaleHeight = height2 / height1;
      return scaleWidth < scaleHeight ? scaleWidth : scaleHeight;
    }

    //
    // find the baseZoomLevel one above the available size, so to fit the total picture, then we scale down
    var zoom = 0;
    while (zoom < _zoomRowCols.length && _zoomRowCols[zoom]['width'] < _windowWidth && _zoomRowCols[zoom]['height'] < _windowHeight) {
      zoom++;
    }
    var baseZoomLevel = (zoom < _zoomRowCols.length) ? zoom : _zoomRowCols.length - 1;
    // scale is the factor that we have to reduce the image at the given zoomlevel to fit the window
    var scale = calculateScale(
        _zoomRowCols[baseZoomLevel]['width'].toDouble(), _zoomRowCols[baseZoomLevel]['height'].toDouble(), _windowWidth, _windowHeight);
    _zoomLevel = baseZoomLevel + 1 + (log(scale) / log(2));
    _fitZoomLevel = _zoomLevel;
    _horOffset = ((_windowWidth - _zoomRowCols[baseZoomLevel]['width'] * scale) / 2);
    _verOffset = ((_windowHeight - _zoomRowCols[baseZoomLevel]['height'] * scale) / 2);
    _imageWidth = (_zoomRowCols[baseZoomLevel]['width'] * scale);
    _imageHeight = (_zoomRowCols[baseZoomLevel]['height'] * scale);
    _zoomCenter = Offset(_windowWidth / 2, _windowHeight / 2);
    _imagePositioned = true;
    // sometimes this routine is called during the build process. In that situation we cannot call the users onChange routine, so
    // schedule a call after the build is complete.
    _callOnChangeAfterBuild();
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // routine for handling keyboard events
  //
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) return;
    final key = event.logicalKey;
    final double offset = widget.panButtonOffset;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyR) {
      _animateZoomAndPan(panOffset: Offset(-offset, 0));
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyL) {
      _animateZoomAndPan(panOffset: Offset(offset, 0));
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyU) {
      _animateZoomAndPan(panOffset: Offset(0, offset));
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyD) {
      _animateZoomAndPan(panOffset: Offset(0, -offset));
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyH) {
      setState(() => _positionInitialImage());
    } else if (key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.equal) {
      _animateZoomAndPan(zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2), zoomLevel: _zoomLevel + 0.2);
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.underscore) {
      _animateZoomAndPan(
          zoomCenter: Offset(_windowWidth / 2, _windowHeight / 2),
          zoomLevel: widget.fitImage && (_zoomLevel - 0.2) < _fitZoomLevel ? _fitZoomLevel : _zoomLevel - 0.2);
    }
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // routine to handle finger and mouse gestures
  //
  void _handleGestures(ScaleUpdateDetails scaleDetails) {
    _animationController.reset(); // stop any animation that may be running
    _zoomAndPan(
        zoomCenter: scaleDetails.localFocalPoint,
        zoomLevel: _zoomLevel + (scaleDetails.scale - _scaleStart),
        panOffset: scaleDetails.focalPointDelta,
        panTo: Offset.infinite);
    _scaleStart = scaleDetails.scale;
  }

  void _fling(ScaleEndDetails details) {
    // Check if there is enough velocity to warrant a fling.
    final double velocityMagnitude = details.velocity.pixelsPerSecond.distance;
    if (velocityMagnitude < 200.0) {
      // Not enough speed, just stop.
      setState(() => _scaleStart = 1);
      return;
    }
    // Calculate the direction of the velocity
    final Offset velocity = details.velocity.pixelsPerSecond;
    // Create a physics simulation to predict the final resting position.
    // We simulate friction to determine how far the image would slide.
    // 0.005 is a friction coefficient constant (tweak for "slipperiness").
    // We calculate separate simulations for X and Y to handle 2D movement.
    final FrictionSimulation simulationX = FrictionSimulation(0.005, 0.0, velocity.dx);
    final FrictionSimulation simulationY = FrictionSimulation(0.005, 0.0, velocity.dy);
    // Calculate the total distance traveled by the simulation (final position at infinity)
    // simulation.x(time) gives position. simulation.finalX is the resting point.
    final double distanceX = simulationX.finalX;
    final double distanceY = simulationY.finalX;
    // Apply this delta to the current offset
    // Note: We are just adding the delta to the current offset.
    // The boundaries will be handled by the clamping logic inside _animateZoomAndPan.
    final Offset targetPanOffset = Offset(distanceX, distanceY);
    // Trigger the animation.
    // We use a custom duration based on how long the physics simulation thinks it should take,
    // clamped to a reasonable max (e.g., 1 second) to prevent it from feeling too floaty.
    // Alternatively, just use the standard animationDuration.
    _animateZoomAndPan(panOffset: targetPanOffset, fling: true);
    setState(() => _scaleStart = 1);
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // set new pan and zoom values without animation
  //
  void _zoomAndPan({double zoomLevel = -1, zoomCenter = Offset.infinite, panOffset = Offset.zero, panTo = Offset.infinite}) {
    _animationController.reset();
    _zoom(zoomLevel < 0 ? _zoomLevel : zoomLevel, zoomCenter);
    _pan(panOffset);
    _panToAbs(panTo);
    setState(() {});
    widget.onChange?.call(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // same with animation
  // initialization of the animation
  //
  void _animateZoomAndPan(
      {double zoomLevel = -1, zoomCenter = Offset.infinite, panOffset = Offset.zero, panTo = Offset.infinite, fling = false}) {
    _animationController.reset();
    // Determine the actual target zoom level
    double targetZoom = zoomLevel < 0.0 ? _zoomLevel : zoomLevel;
    if (widget.fitImage) targetZoom = targetZoom.clamp(_fitZoomLevel, _maxZoomLevel);
    _panTween = Tween<Offset>(begin: Offset.zero, end: panOffset);
    _zoomTween = Tween<double>(begin: _zoomLevel, end: targetZoom);
    _zoomCenter = zoomCenter == Offset.infinite ? _zoomCenter : zoomCenter;
    _panStart = Offset.zero;
    _panTo = panTo;
    _animationController.duration = fling ? Duration(milliseconds: 500) : widget.animationDuration;
    _animationController.forward();
  }

  void _updateAnimation() {
    if (_animation.isCompleted) {
      _animationController.reset();
      _panTo = Offset.infinite; // Clear the target
      _callOnChangeAfterBuild();
    } else if (_animation.isAnimating) {
      _zoom(_zoomTween.evaluate(_animation), _zoomCenter);
      if (_panTo != Offset.infinite) {
        // A. Get the current scale (calculated by _zoom just now)
        var currentScale = _imageWidth / _maxImageSize.width;
        // B. Calculate where the top-left offset MUST be to center the _panTo point at this exact moment in the animation.
        var dx = _panTo.dx.clamp(0, _maxImageSize.width);
        var dy = _panTo.dy.clamp(0, _maxImageSize.height);

        var requiredHorOffset = (_windowWidth / 2) - (dx * currentScale);
        var requiredVerOffset = (_windowHeight / 2) - (dy * currentScale);

        // C. Apply boundaries (centering if smaller, clamping if larger) This effectively "sets" the offset directly rather than adding a delta.
        if (_imageWidth <= _windowWidth) {
          _horOffset = (_windowWidth - _imageWidth) / 2;
        } else {
          _horOffset = requiredHorOffset.clamp(_windowWidth - _imageWidth, 0.0);
        }

        if (_imageHeight <= _windowHeight) {
          _verOffset = (_windowHeight - _imageHeight) / 2;
        } else {
          _verOffset = requiredVerOffset.clamp(_windowHeight - _imageHeight, 0.0);
        }
      } else {
        // Standard relative panning using the Tween
        var currentPan = _panTween.evaluate(_animation);
        _pan(currentPan - _panStart);
        _panStart = currentPan;
      }
      widget.controller?.updateState(_zoomLevel, Offset(_horOffset, _verOffset), Size(_imageWidth, _imageHeight));
      if (widget.animationSync) _callOnChangeAfterBuild();
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // straight forward pan  and zoom routines
  //
  void _pan(Offset panOffset) {
    _horOffset += panOffset.dx;
    _verOffset += panOffset.dy;
    _clampOffset();
  }

  void _panToAbs(Offset panTo) {
    if (panTo == Offset.infinite) return;
    var dx = panTo.dx.clamp(0, _maxImageSize.width);
    var dy = panTo.dy.clamp(0, _maxImageSize.height);
    var scale = _imageWidth / _maxImageSize.width;
    _horOffset = (_windowWidth / 2) - (dx * scale);
    _verOffset = (_windowHeight / 2) - (dy * scale);
    _clampOffset();
    _zoomCenter = Offset(_windowWidth / 2, _windowHeight / 2);
  }

  void _zoom(double zoomLevel, Offset zoomCenter) {
    _zoomCenter = zoomCenter == Offset.infinite ? _zoomCenter : zoomCenter;
    if (zoomLevel == _zoomLevel || zoomLevel < 0) return;
    double targetZoom = zoomLevel;
    if (widget.fitImage && targetZoom < _fitZoomLevel) {
      targetZoom = _fitZoomLevel;
    }
    _zoomLevel = targetZoom.clamp(0, _maxZoomLevel).toDouble();
    int baseZoomLevel = _zoomLevel.ceil() - 1;
    double scale = pow(2, _zoomLevel - _zoomLevel.ceil()).toDouble();
    var newWidth = (_zoomRowCols[baseZoomLevel]['width'] * scale).roundToDouble();
    var newHeight = (_zoomRowCols[baseZoomLevel]['height'] * scale).roundToDouble();
    _horOffset = (newWidth > _windowWidth
        ? (((_horOffset - zoomCenter.dx) * newWidth / _imageWidth) + zoomCenter.dx)
        : ((_windowWidth - newWidth) / 2));
    _verOffset = (newHeight > _windowHeight
        ? (((_verOffset - zoomCenter.dy) * newHeight / _imageHeight) + zoomCenter.dy)
        : ((_windowHeight - newHeight) / 2));
    _imageWidth = newWidth;
    _imageHeight = newHeight;
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // this routine ensures that the image, big enough, continues to cover tha whole screen
  //
  void _clampOffset() {
    _horOffset = (_imageWidth <= _windowWidth) ? (_windowWidth - _imageWidth) / 2 : _horOffset.clamp(_windowWidth - _imageWidth, 0.0);
    _verOffset = (_imageHeight <= _windowHeight) ? (_windowHeight - _imageHeight) / 2 : _verOffset.clamp(_windowHeight - _imageHeight, 0.0);
  }

  //----------------------------------------------------------------------------------------------------------------------------------------
  // this routine handles the events coming from the stream of the controller
  //
  void _handleControllerEvent(ZoomifyEvent event) {
    if (event is ResetEvent) {
      setState(() => _positionInitialImage());
    } else if (event is ZoomAndPanEvent) {
      _zoomAndPan(
        zoomLevel: (event.zoomLevel >= 0 && widget.fitImage && event.zoomLevel < _fitZoomLevel) ? _fitZoomLevel : event.zoomLevel,
        zoomCenter: event.zoomCenter == Offset.infinite
            ? Offset.infinite
            : event.zoomCenter.clamp(Offset.zero, Offset(_windowWidth, _windowHeight)),
        panOffset: event.panOffset,
        panTo: event.panTo == Offset.infinite
            ? Offset.infinite
            : event.panTo.clamp(Offset.zero, Offset(_maxImageSize.width, _maxImageSize.height)),
      );
    } else if (event is AnimateZoomAndPanEvent) {
      _animateZoomAndPan(
        zoomLevel: (event.zoomLevel >= 0 && widget.fitImage && event.zoomLevel < _fitZoomLevel) ? _fitZoomLevel : event.zoomLevel,
        zoomCenter: event.zoomCenter == Offset.infinite
            ? Offset.infinite
            : event.zoomCenter.clamp(Offset.zero, Offset(_windowWidth, _windowHeight)),
        panOffset: event.panOffset,
        panTo: event.panTo == Offset.infinite
            ? Offset.infinite
            : event.panTo.clamp(Offset.zero, Offset(_maxImageSize.width, _maxImageSize.height)),
      );
    }
  }
}
