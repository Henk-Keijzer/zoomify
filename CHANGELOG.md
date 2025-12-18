## 1.2.0

- added code for Deep Zoom Image (DZI) images
- further improved transitioning over zoom levels to prevent flashing
- added a single row/col of tiles around the edges to prevent 'black' tiles when panning
- fixed a bug in the controller

## 1.1.1

- improved image display when transitioning from one tile leyer to the next (higer or lower) layer

## 1.1.0

- Added buttonAxis parameter to the constructor (default = Axis.vertical)
- Added buttonOrderReversed parameter to the constructor (default = false)

## 1.0.9

- Added showPanButtons and showResetButton parameters to the constructor (both default false)
- Changed zoomButtonPosition and zoomButtonColor to buttonPosition and buttonColor (breaking)
- Clamped zoomLevel, zoomCenter and panTo inputs to acceptable values
- Added an extra value in the onTap callback function. Now (imageOffset, windowOffset) (breaking)
- Code optimization and bug fixes

## 1.0.8

- Added parameter 'interactive' (default = true). If set to false, you can/should add your own keyboard/mouse/gesture detector on top of 
  the zoomify widget, or use the controller to interact with the image.
- Added parameter 'pantTo: Offset' to controller.(animate)PanAndZoom function. Moves the given point, relative to the original max image, 
  to the center of the window
- Added parameter 'fitImage' (default = true). If set to false, allows the image to become smaller then the winde

## 1.0.7

- Breaking: changed parameters in onImageReady to (Size maxImageSize, int zoomLevels)
- Breaking: changed parameters in onChange to (double zoomLevel, Offset offset, Size currentImageSize)
- Added controller get functions getZoomLevel, getOffset and getCurrentImageSize
- Added onTap callback function, returning the tap offset from the top-left corner of the non-zoomed-in image
- Code optimizations and bugfixes

## 1.0.6

- Added a decent controller for programmatically zooming, panning and reset (see example). The previous way of working (directly calling 
  the state functions) will be removed in the next version.)
- Added an optional sync parameter (default false). Setting it to true will cause the onChange callback 
  function to be triggered each animation frame. This allows for synchronous zooming / panning something else in your app (for example a 
  flutter_map or another zoomify picture in sync with the zoomify widget).

## 1.0.5

- BREAKING CHANGE: in the (animate)ZoomAndPan function the scaleDelta parameter has been removed and replaced by the zoomLevel parameter, i.
  e. you have to supply the new zoom level instead of a delta. The first parameter that is returned in the onImageReady callback is the 
  maximum zoomlevel. Zoomlevel 1 fits the whole picture within a single 256x256 tile (TileGroup0/0-0-0.jpg). However, you cannot zoom 
  out smaller than the size of the widget.

## 1.0.4

- Added zoomAndPan, animateZoomAndPan and reset functions, to allow for programmatically zoom, pan or reset the image
  (See the example how to use these functions)
- Added animation parameters duration and curve
- bugfixes

## 1.0.3

- Improved(?) animations
- Added callback function onImageReady and onChange

## 1.0.2

- Used package 'path' to ensure proper uri creation
- Added basic animation when zooming and panning using keyboard

## 1.0.1

- Minor bug fixes
- Added android, ios, windows, mac, linux and web support in example (tested android, windows and web)

## 1.0.0

- Initial release
- Minor bug fixes

## 0.0.1

Initial (test) release.
