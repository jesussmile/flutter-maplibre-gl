/// Compatibility layer for JS interop functions.
/// Provides jsify, allowInterop, and getProperty functions that work with
/// modern Dart/Flutter (3.x+) using dart:js_interop.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:js_util' as js_util;

// Re-export the jsify extension from dart:js_interop
// which provides .jsify() on Map and List

/// Converts a Dart object to a JavaScript object.
/// This is a compatibility wrapper for the old package:js/js_util.dart jsify function.
dynamic jsify(Object? object) {
  if (object == null) {
    return null;
  }
  if (object is Map) {
    return object.jsify();
  }
  if (object is List) {
    return object.jsify();
  }
  if (object is String) {
    return object.toJS;
  }
  if (object is num) {
    return object.toJS;
  }
  if (object is bool) {
    return object.toJS;
  }
  if (object is JSAny) {
    return object;
  }
  // For other objects, try to convert as a map
  return object.toString().toJS;
}

/// Wraps a Dart function for use as a JavaScript callback.
/// Uses dart:js_util's allowInterop which properly wraps Dart closures
/// into JavaScript-callable functions (required for dart2js).
F allowInterop<F extends Function>(F function) {
  return js_util.allowInterop(function);
}

/// Gets a property from a JavaScript object.
/// This is a compatibility wrapper for the old package:js/js_util.dart getProperty function.
T? getProperty<T>(Object? jsObject, String key) {
  if (jsObject == null) {
    return null;
  }
  if (jsObject is JSObject) {
    final value = jsObject.getProperty<JSAny?>(key.toJS);
    return dartify(value) as T?;
  }
  return null;
}

/// Converts a JavaScript value back to Dart.
/// This is a compatibility wrapper for dartifying JS values.
Object? dartify(JSAny? jsValue) {
  if (jsValue == null) {
    return null;
  }
  if (jsValue.isA<JSString>()) {
    return (jsValue as JSString).toDart;
  }
  if (jsValue.isA<JSNumber>()) {
    return (jsValue as JSNumber).toDartDouble;
  }
  if (jsValue.isA<JSBoolean>()) {
    return (jsValue as JSBoolean).toDart;
  }
  if (jsValue.isA<JSArray>()) {
    final jsArray = jsValue as JSArray;
    final list = <Object?>[];
    for (var i = 0; i < jsArray.length; i++) {
      list.add(dartify(jsArray[i]));
    }
    return list;
  }
  // Return the raw JS object for other types
  return jsValue;
}
