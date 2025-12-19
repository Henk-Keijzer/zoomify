import 'dart:async';
import 'dart:ui';

//------------------------------------------------------------------------------------------------------------------------------------------
//
// The ZoomifyController closs
//
// First define a base class for all controller events

abstract class ZoomifyEvent {}

class ResetEvent extends ZoomifyEvent {}

class ZoomAndPanEvent extends ZoomifyEvent {
  final double zoomLevel;
  final Offset zoomCenter;
  final Offset panOffset;
  final Offset panTo;

  ZoomAndPanEvent({
    this.zoomLevel = -1,
    this.zoomCenter = Offset.infinite,
    this.panOffset = Offset.zero,
    this.panTo = Offset.infinite,
  });
}

class AnimateZoomAndPanEvent extends ZoomifyEvent {
  final double zoomLevel;
  final Offset zoomCenter;
  final Offset panOffset;
  final Offset panTo;

  AnimateZoomAndPanEvent({
    this.zoomLevel = -1,
    this.zoomCenter = Offset.infinite,
    this.panOffset = Offset.zero,
    this.panTo = Offset.infinite,
  });
}

class ZoomifyController {
  // Use a broadcast stream so multiple listeners (if any) could subscribe
  final _eventController = StreamController<ZoomifyEvent>.broadcast();
  Stream<ZoomifyEvent> get events => _eventController.stream;

  double _zoomLevel = 0;
  Offset _offset = Offset.zero;
  Size _imageSize = Size.zero;

  // --- EXPOSE GETTERS ---
  double get getZoomLevel => _zoomLevel;
  Offset get getOffset => _offset;
  Size get getImageSize => _imageSize;

  void reset() => _eventController.add(ResetEvent());

  void zoomAndPan(
      {double zoomLevel = -1, Offset zoomCenter = Offset.infinite, Offset panOffset = Offset.zero, Offset panTo = Offset.infinite}) {
    _eventController.add(ZoomAndPanEvent(zoomLevel: zoomLevel, zoomCenter: zoomCenter, panOffset: panOffset, panTo: panTo));
  }

  void animateZoomAndPan(
      {double zoomLevel = -1, Offset zoomCenter = Offset.infinite, Offset panOffset = Offset.zero, Offset panTo = Offset.infinite}) {
    _eventController.add(AnimateZoomAndPanEvent(zoomLevel: zoomLevel, zoomCenter: zoomCenter, panOffset: panOffset, panTo: panTo));
  }

  void dispose() {
    _eventController.close();
  }

  void updateState(double zoomLevel, Offset offset, Size size) {
    _zoomLevel = zoomLevel;
    _offset = offset;
    _imageSize = size;
  }
}
