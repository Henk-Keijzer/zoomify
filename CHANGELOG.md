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
