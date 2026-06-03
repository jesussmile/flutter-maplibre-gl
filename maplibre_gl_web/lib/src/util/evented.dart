import 'dart:js_interop';

import 'package:maplibre_gl_web/src/geo/geojson.dart';
import 'package:maplibre_gl_web/src/js_util_compat.dart';
import 'package:maplibre_gl_web/src/geo/lng_lat.dart';
import 'package:maplibre_gl_web/src/interop/interop.dart';
import 'package:maplibre_gl_web/src/ui/control/geolocate_control.dart';
import 'package:maplibre_gl_web/src/ui/map.dart';
import 'package:maplibre_gl_web/src/geo/point.dart';

typedef Listener = dynamic Function(Event object);
typedef GeoListener = dynamic Function(dynamic object);

class Event extends JsObjectWrapper<EventJsImpl> {
  String get id => jsObject.id;

  String get type => jsObject.type;

  LngLat get lngLat => LngLat.fromJsObject(jsObject.lngLat);

  List<Feature> get features {
    final rawFeatures = jsObject.features;
    if (rawFeatures == null) return const <Feature>[];
    final features = dartify(rawFeatures);
    if (features is! List) return const <Feature>[];
    return features
        .map((dynamic feature) => Feature.fromJsObject(feature))
        .toList();
  }

  Point get point => Point.fromJsObject(jsObject.point);

  factory Event({
    String? id,
    String? type,
    required LngLat lngLat,
    required List<Feature> features,
    required Point point,
  }) =>
      Event.fromJsObject(EventJsImpl(
        id: id,
        type: type,
        lngLat: lngLat.jsObject,
        features: jsify(features.map((dynamic f) => f.jsObject).toList()),
        point: point.jsObject,
      ));

  preventDefault() => jsObject.preventDefault();

  /// Creates a new Event from a [jsObject].
  Event.fromJsObject(super.jsObject) : super.fromJsObject();
}

class Evented extends JsObjectWrapper<EventedJsImpl> {
  ///  Adds a listener to a specified event type.
  ///
  ///  @param {string} type The event type to add a listen for.
  ///  @param {Function} listener The function to be called when the event is fired.
  ///    The listener function is called with the data object passed to `fire`,
  ///    extended with `target` and `type` properties.
  ///  @returns {Object} `this`
  void on(String type, [dynamic layerIdOrListener, Listener? listener]) {
    if (this is GeolocateControl && listener == null) {
      final callback = layerIdOrListener as Function;
      jsObject.on(
          type,
          ((JSAny? position) {
            callback(position);
          }).toJS);
      return;
    }
    if (listener == null) {
      final callback = layerIdOrListener as Function;
      jsObject.on(
          type,
          ((EventJsImpl object) {
            callback(Event.fromJsObject(object));
          }).toJS);
      return;
    }
    jsObject.on(
      type,
      layerIdOrListener is String ? layerIdOrListener.toJS : layerIdOrListener,
      ((EventJsImpl object) {
        listener!(Event.fromJsObject(object));
      }).toJS,
    );
  }

  ///  Removes a previously registered event listener.
  ///
  ///  @param {string} type The event type to remove listeners for.
  ///  @param {Function} listener The listener function to remove.
  ///  @returns {Object} `this`
  void off(String type, [dynamic layerIdOrListener, Listener? listener]) {
    if (listener == null) {
      final callback = layerIdOrListener as Function;
      jsObject.off(
          type,
          ((EventJsImpl object) {
            callback(Event.fromJsObject(object));
          }).toJS);
      return;
    }
    jsObject.off(
      type,
      layerIdOrListener is String ? layerIdOrListener.toJS : layerIdOrListener,
      ((EventJsImpl object) {
        listener!(Event.fromJsObject(object));
      }).toJS,
    );
  }

  ///  Adds a listener that will be called only once to a specified event type.
  ///
  ///  The listener will be called first time the event fires after the listener is registered.
  ///
  ///  @param {string} type The event type to listen for.
  ///  @param {Function} listener The function to be called when the event is fired the first time.
  ///  @returns {Object} `this`
  void once(String type, Listener listener) {
    jsObject.once(
        type,
        ((EventJsImpl object) {
          listener(Event.fromJsObject(object));
        }).toJS);
  }

  fire(Event event, [dynamic properties]) =>
      jsObject.fire(event.jsObject, properties);

  ///  Returns a true if this instance of Evented or any forwardeed instances of Evented have a listener for the specified type.
  ///
  ///  @param {string} type The event type
  ///  @returns {boolean} `true` if there is at least one registered listener for specified event type, `false` otherwise
  ///  @private
  listens(String type) => jsObject.listens(type);

  ///  Bubble all events fired by this instance of Evented to this parent instance of Evented.
  ///
  ///  @private
  ///  @returns {Object} `this`
  ///  @private
  setEventedParent([Evented? parent, dynamic data]) =>
      jsObject.setEventedParent(parent?.jsObject, data);

  /// Creates a new Evented from a [jsObject].
  Evented.fromJsObject(super.jsObject) : super.fromJsObject();
}
