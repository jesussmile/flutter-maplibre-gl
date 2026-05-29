package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.MotionEvent;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.maps.Style;
import org.maplibre.android.style.layers.Layer;
import org.maplibre.android.style.layers.LineLayer;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.FeatureCollection;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;

import java.util.ArrayList;
import java.util.List;
import static org.maplibre.android.style.layers.PropertyFactory.*;

/**
 * Native two-finger line measurement detector.
 *
 * This follows the Flight Canvas native measurement path: detect a stable
 * two-finger hold in the Android plugin, project both fingers through
 * MapLibre, render a GeoJSON line in native MapLibre layers, and send
 * measurement callbacks back through the method channel.
 */
public class NativeMeasurementDetector {
  private static final String TAG = "NativeMeasurementDetector";
  private static final long HOLD_DURATION_MS = 500;
  private static final float MOVEMENT_THRESHOLD_PX = 50f;
  private static final float TAP_MOVEMENT_THRESHOLD_PX = 20f;
  private static final long CLEANUP_GRACE_PERIOD_MS = 500;
  private static final float MARKER_TOUCH_RADIUS_PX = 36f;

  private static final String MEASUREMENT_SOURCE_ID = "measurement-source";
  private static final String MEASUREMENT_LINE_LAYER_ID = "measurement-line-layer";

  private final MapLibreMap mapLibreMap;
  private final OnNativeMeasurementListener listener;
  private final Handler handler = new Handler(Looper.getMainLooper());

  private boolean isTwoFingerDown = false;
  private boolean isMeasuring = false;
  private boolean hasPersistentMeasurement = false;
  private boolean justFinishedMeasurement = false;
  private boolean pendingClearGesture = false;
  private boolean isDraggingStart = false;
  private boolean isDraggingEnd = false;

  private PointF initialPoint1;
  private PointF initialPoint2;
  private PointF currentPoint1;
  private PointF currentPoint2;
  private PointF initialClearPoint;
  private LatLng startLatLng;
  private LatLng endLatLng;
  private long gestureStartTime = 0;
  private long measurementEndTime = 0;
  private Runnable holdRunnable;

  private String lineColor = "#00BFFF";
  private double lineWidth = 4.0;
  private double lineOpacity = 0.9;
  private String endpointColor = "#FFFFFF";
  private double endpointRadius = 9.0;

  public interface OnNativeMeasurementListener {
    void onMeasurementStart(
        PointF point1,
        PointF point2,
        LatLng latLng1,
        LatLng latLng2,
        double distance,
        double bearing,
        long duration);

    void onMeasurementUpdate(
        PointF point1,
        PointF point2,
        LatLng latLng1,
        LatLng latLng2,
        double distance,
        double bearing,
        long duration);

    void onMeasurementEnd(
        PointF point1,
        PointF point2,
        LatLng latLng1,
        LatLng latLng2,
        double distance,
        double bearing,
        long duration);
  }

  public NativeMeasurementDetector(
      MapLibreMap mapLibreMap,
      OnNativeMeasurementListener listener) {
    this.mapLibreMap = mapLibreMap;
    this.listener = listener;
    initializeMeasurementLayers();
  }

  public boolean onTouchEvent(MotionEvent event) {
    if (event.getActionMasked() == MotionEvent.ACTION_DOWN
        || event.getActionMasked() == MotionEvent.ACTION_POINTER_DOWN
        || event.getActionMasked() == MotionEvent.ACTION_POINTER_UP
        || event.getActionMasked() == MotionEvent.ACTION_UP
        || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
      Log.d(TAG, "Touch " + actionName(event) + ", pointers=" + event.getPointerCount());
    }

    if (hasPersistentMeasurement
        && !isMeasuring
        && event.getPointerCount() == 1
        && handlePersistentMeasurementTouch(event)) {
      return true;
    }

    switch (event.getActionMasked()) {
      case MotionEvent.ACTION_DOWN:
        if (event.getPointerCount() == 1) {
          initialPoint1 = new PointF(event.getX(), event.getY());
          currentPoint1 = new PointF(event.getX(), event.getY());
        }
        break;

      case MotionEvent.ACTION_POINTER_DOWN:
        if (event.getPointerCount() == 2) {
          initialPoint1 = new PointF(event.getX(0), event.getY(0));
          initialPoint2 = new PointF(event.getX(1), event.getY(1));
          currentPoint1 = new PointF(event.getX(0), event.getY(0));
          currentPoint2 = new PointF(event.getX(1), event.getY(1));
          isTwoFingerDown = true;
          gestureStartTime = System.currentTimeMillis();
          scheduleHoldDetection();
          Log.d(TAG, "Two-finger measurement candidate started");
        }
        break;

      case MotionEvent.ACTION_MOVE:
        if (isTwoFingerDown && event.getPointerCount() == 2) {
          currentPoint1 = new PointF(event.getX(0), event.getY(0));
          currentPoint2 = new PointF(event.getX(1), event.getY(1));

          if (isMeasuring) {
            updateMeasurement();
            return true;
          }

          if (movedTooFarBeforeHold()) {
            Log.d(TAG, "Two-finger measurement candidate canceled by movement");
            cancelGesture();
          }
        }
        break;

      case MotionEvent.ACTION_POINTER_UP:
      case MotionEvent.ACTION_UP:
      case MotionEvent.ACTION_CANCEL:
        if (isMeasuring) {
          endMeasurement();
          return true;
        }
        cancelGesture();
        break;

      default:
        break;
    }

    return isMeasuring;
  }

  public void setMeasurementStyle(
      String lineColor,
      double lineWidth,
      double lineOpacity,
      String endpointColor,
      double endpointRadius) {
    this.lineColor = lineColor;
    this.lineWidth = lineWidth;
    this.lineOpacity = lineOpacity;
    this.endpointColor = endpointColor;
    this.endpointRadius = endpointRadius;
    updateMeasurementLayerStyle();
  }

  public void clearMeasurement() {
    cancelGesture();
    hasPersistentMeasurement = false;
    justFinishedMeasurement = false;
    pendingClearGesture = false;
    isDraggingStart = false;
    isDraggingEnd = false;
    startLatLng = null;
    endLatLng = null;
    clearMeasurementRendering();
  }

  public void disable() {
    clearMeasurement();
  }

  public void cleanup() {
    clearMeasurement();
    if (holdRunnable != null) {
      handler.removeCallbacks(holdRunnable);
      holdRunnable = null;
    }
  }

  public void ensureMeasurementLayersOnTop() {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || !style.isFullyLoaded()) {
        Log.w(TAG, "Map style not ready for measurement layer ordering");
        return;
      }

      if (style.getSource(MEASUREMENT_SOURCE_ID) == null
          || style.getLayer(MEASUREMENT_LINE_LAYER_ID) == null) {
        setupMeasurementLayers();
      }

      String topLayerId = getTopNonMeasurementLayerId();
      if (topLayerId != null) {
        repositionLayerIfNeeded(MEASUREMENT_LINE_LAYER_ID, topLayerId);
      }
    } catch (Exception e) {
      Log.e(TAG, "Error ensuring measurement layer on top", e);
    }
  }

  private void scheduleHoldDetection() {
    if (holdRunnable != null) {
      handler.removeCallbacks(holdRunnable);
    }

    holdRunnable = new Runnable() {
      @Override
      public void run() {
        if (isTwoFingerDown && !isMeasuring) {
          startMeasurement();
        }
      }
    };
    handler.postDelayed(holdRunnable, HOLD_DURATION_MS);
  }

  private boolean movedTooFarBeforeHold() {
    if (initialPoint1 == null
        || initialPoint2 == null
        || currentPoint1 == null
        || currentPoint2 == null) {
      return true;
    }

    float distance1 = screenDistance(initialPoint1, currentPoint1);
    float distance2 = screenDistance(initialPoint2, currentPoint2);
    return distance1 > MOVEMENT_THRESHOLD_PX || distance2 > MOVEMENT_THRESHOLD_PX;
  }

  private void startMeasurement() {
    if (currentPoint1 == null || currentPoint2 == null) {
      return;
    }

    try {
      ensureMeasurementLayersOnTop();
      startLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint1);
      endLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint2);
      isMeasuring = true;
      hasPersistentMeasurement = false;

      double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
      double bearing = calculateBearing(startLatLng, endLatLng);
      long duration = System.currentTimeMillis() - gestureStartTime;

      Log.d(TAG, String.format(
          "Measurement started: distance=%.2f nm, bearing=%.1f deg",
          distance,
          bearing));
      renderMeasurementLine(startLatLng, endLatLng);

      if (listener != null) {
        listener.onMeasurementStart(
            currentPoint1,
            currentPoint2,
            startLatLng,
            endLatLng,
            distance,
            bearing,
            duration);
      }
    } catch (Exception e) {
      Log.e(TAG, "Error starting measurement", e);
      cancelGesture();
    }
  }

  private void updateMeasurement() {
    if (!isMeasuring || currentPoint1 == null || currentPoint2 == null) {
      return;
    }

    try {
      startLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint1);
      endLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint2);
      double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
      double bearing = calculateBearing(startLatLng, endLatLng);
      long duration = System.currentTimeMillis() - gestureStartTime;

      renderMeasurementLine(startLatLng, endLatLng);

      if (listener != null) {
        listener.onMeasurementUpdate(
            currentPoint1,
            currentPoint2,
            startLatLng,
            endLatLng,
            distance,
            bearing,
            duration);
      }
    } catch (Exception e) {
      Log.e(TAG, "Error updating measurement", e);
    }
  }

  private void endMeasurement() {
    if (!isMeasuring || currentPoint1 == null || currentPoint2 == null) {
      return;
    }

    try {
      startLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint1);
      endLatLng = mapLibreMap.getProjection().fromScreenLocation(currentPoint2);
      double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
      double bearing = calculateBearing(startLatLng, endLatLng);
      long duration = System.currentTimeMillis() - gestureStartTime;

      hasPersistentMeasurement = true;
      justFinishedMeasurement = true;
      measurementEndTime = System.currentTimeMillis();
      handler.postDelayed(new Runnable() {
        @Override
        public void run() {
          justFinishedMeasurement = false;
        }
      }, CLEANUP_GRACE_PERIOD_MS);

      renderMeasurementLine(startLatLng, endLatLng);
      Log.d(TAG, String.format(
          "Measurement ended: distance=%.2f nm, bearing=%.1f deg",
          distance,
          bearing));

      if (listener != null) {
        listener.onMeasurementEnd(
            currentPoint1,
            currentPoint2,
            startLatLng,
            endLatLng,
            distance,
            bearing,
            duration);
      }
    } catch (Exception e) {
      Log.e(TAG, "Error ending measurement", e);
    } finally {
      isMeasuring = false;
      isTwoFingerDown = false;
      clearGesturePoints();
    }
  }

  private boolean handlePersistentMeasurementTouch(MotionEvent event) {
    if (startLatLng == null || endLatLng == null) {
      return false;
    }

    long currentTime = System.currentTimeMillis();
    boolean inGracePeriod = justFinishedMeasurement
        && (currentTime - measurementEndTime) < CLEANUP_GRACE_PERIOD_MS;
    PointF touchPoint = new PointF(event.getX(), event.getY());

    switch (event.getActionMasked()) {
      case MotionEvent.ACTION_DOWN:
        PointF startScreenPoint = mapLibreMap.getProjection().toScreenLocation(startLatLng);
        PointF endScreenPoint = mapLibreMap.getProjection().toScreenLocation(endLatLng);
        if (screenDistance(touchPoint, startScreenPoint) <= MARKER_TOUCH_RADIUS_PX) {
          isDraggingStart = true;
          pendingClearGesture = false;
          Log.d(TAG, "Started dragging measurement start marker");
          return true;
        }
        if (screenDistance(touchPoint, endScreenPoint) <= MARKER_TOUCH_RADIUS_PX) {
          isDraggingEnd = true;
          pendingClearGesture = false;
          Log.d(TAG, "Started dragging measurement end marker");
          return true;
        }

        pendingClearGesture = !inGracePeriod;
        initialClearPoint = touchPoint;
        return false;

      case MotionEvent.ACTION_MOVE:
        if (isDraggingStart || isDraggingEnd) {
          LatLng newPosition = mapLibreMap.getProjection().fromScreenLocation(touchPoint);
          if (isDraggingStart) {
            startLatLng = newPosition;
          } else {
            endLatLng = newPosition;
          }
          renderMeasurementLine(startLatLng, endLatLng);
          sendUpdateForPersistentMeasurement();
          return true;
        }

        if (pendingClearGesture && initialClearPoint != null) {
          if (screenDistance(initialClearPoint, touchPoint) > TAP_MOVEMENT_THRESHOLD_PX) {
            pendingClearGesture = false;
            initialClearPoint = null;
          }
        }
        return false;

      case MotionEvent.ACTION_UP:
        if (isDraggingStart || isDraggingEnd) {
          sendEndForPersistentMeasurement();
          isDraggingStart = false;
          isDraggingEnd = false;
          Log.d(TAG, "Finished dragging measurement marker");
          return true;
        }

        if (pendingClearGesture && initialClearPoint != null && !inGracePeriod) {
          if (screenDistance(initialClearPoint, touchPoint) <= TAP_MOVEMENT_THRESHOLD_PX) {
            Log.d(TAG, "Single tap cleared persistent measurement");
            clearMeasurement();
            return true;
          }
        }
        pendingClearGesture = false;
        initialClearPoint = null;
        return false;

      case MotionEvent.ACTION_CANCEL:
        pendingClearGesture = false;
        initialClearPoint = null;
        isDraggingStart = false;
        isDraggingEnd = false;
        return false;

      default:
        return false;
    }
  }

  private void sendUpdateForPersistentMeasurement() {
    if (listener == null || startLatLng == null || endLatLng == null) {
      return;
    }

    PointF startPoint = mapLibreMap.getProjection().toScreenLocation(startLatLng);
    PointF endPoint = mapLibreMap.getProjection().toScreenLocation(endLatLng);
    double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
    double bearing = calculateBearing(startLatLng, endLatLng);
    listener.onMeasurementUpdate(
        startPoint,
        endPoint,
        startLatLng,
        endLatLng,
        distance,
        bearing,
        0);
  }

  private void sendEndForPersistentMeasurement() {
    if (listener == null || startLatLng == null || endLatLng == null) {
      return;
    }

    PointF startPoint = mapLibreMap.getProjection().toScreenLocation(startLatLng);
    PointF endPoint = mapLibreMap.getProjection().toScreenLocation(endLatLng);
    double distance = calculateDistanceNauticalMiles(startLatLng, endLatLng);
    double bearing = calculateBearing(startLatLng, endLatLng);
    listener.onMeasurementEnd(
        startPoint,
        endPoint,
        startLatLng,
        endLatLng,
        distance,
        bearing,
        0);
  }

  private void cancelGesture() {
    isTwoFingerDown = false;
    isMeasuring = false;
    isDraggingStart = false;
    isDraggingEnd = false;
    if (holdRunnable != null) {
      handler.removeCallbacks(holdRunnable);
      holdRunnable = null;
    }
    if (!hasPersistentMeasurement) {
      clearMeasurementRendering();
    }
    clearGesturePoints();
  }

  private void clearGesturePoints() {
    initialPoint1 = null;
    initialPoint2 = null;
    currentPoint1 = null;
    currentPoint2 = null;
  }

  private void initializeMeasurementLayers() {
    try {
      Style style = mapLibreMap.getStyle();
      if (style != null && style.isFullyLoaded()) {
        setupMeasurementLayers();
      } else {
        mapLibreMap.getStyle(loadedStyle -> setupMeasurementLayers());
      }
    } catch (Exception e) {
      Log.e(TAG, "Error initializing measurement layers", e);
    }
  }

  private void setupMeasurementLayers() {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || !style.isFullyLoaded()) {
        Log.w(TAG, "Map style not ready for measurement layer setup");
        return;
      }

      if (style.getSource(MEASUREMENT_SOURCE_ID) == null) {
        style.addSource(new GeoJsonSource(MEASUREMENT_SOURCE_ID));
        Log.d(TAG, "Added measurement source");
      }

      if (style.getLayer(MEASUREMENT_LINE_LAYER_ID) == null) {
        LineLayer lineLayer =
            new LineLayer(MEASUREMENT_LINE_LAYER_ID, MEASUREMENT_SOURCE_ID);
        lineLayer.setProperties(
            lineColor(lineColor),
            lineWidth((float) lineWidth),
            lineOpacity((float) lineOpacity),
            lineCap("round"),
            lineJoin("round"));

        String topLayerId = getTopNonMeasurementLayerId();
        if (topLayerId != null) {
          style.addLayerAbove(lineLayer, topLayerId);
          Log.d(TAG, "Added measurement line layer above " + topLayerId);
        } else {
          style.addLayer(lineLayer);
          Log.d(TAG, "Added measurement line layer");
        }
      }
    } catch (Exception e) {
      Log.e(TAG, "Error setting up measurement layers", e);
    }
  }

  private void renderMeasurementLine(LatLng start, LatLng end) {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || !style.isFullyLoaded()) {
        Log.w(TAG, "Map style not ready for measurement rendering");
        return;
      }

      ensureMeasurementLayersOnTop();

      Point startPoint = Point.fromLngLat(start.getLongitude(), start.getLatitude());
      Point endPoint = Point.fromLngLat(end.getLongitude(), end.getLatitude());
      List<Point> points = new ArrayList<>();
      points.add(startPoint);
      points.add(endPoint);

      Feature lineFeature = Feature.fromGeometry(LineString.fromLngLats(points));
      lineFeature.addStringProperty("type", "line");
      List<Feature> features = new ArrayList<>();
      features.add(lineFeature);

      GeoJsonSource source = style.getSourceAs(MEASUREMENT_SOURCE_ID);
      if (source != null) {
        source.setGeoJson(FeatureCollection.fromFeatures(features));
        Log.d(TAG, "Updated native measurement line rendering");
      } else {
        Log.w(TAG, "Measurement source missing during render");
      }
    } catch (Exception e) {
      Log.e(TAG, "Error rendering measurement line", e);
    }
  }

  private void clearMeasurementRendering() {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || !style.isFullyLoaded()) {
        return;
      }

      GeoJsonSource source = style.getSourceAs(MEASUREMENT_SOURCE_ID);
      if (source != null) {
        source.setGeoJson(FeatureCollection.fromFeatures(new ArrayList<Feature>()));
        Log.d(TAG, "Cleared native measurement rendering");
      }
    } catch (Exception e) {
      Log.e(TAG, "Error clearing measurement rendering", e);
    }
  }

  private void updateMeasurementLayerStyle() {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || !style.isFullyLoaded()) {
        return;
      }

      LineLayer lineLayer = style.getLayerAs(MEASUREMENT_LINE_LAYER_ID);
      if (lineLayer != null) {
        lineLayer.setProperties(
            lineColor(lineColor),
            lineWidth((float) lineWidth),
            lineOpacity((float) lineOpacity),
            lineCap("round"),
            lineJoin("round"));
      }
    } catch (Exception e) {
      Log.e(TAG, "Error updating measurement line style", e);
    }
  }

  private String getTopNonMeasurementLayerId() {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null) {
        return null;
      }

      List<Layer> layers = style.getLayers();
      for (int i = layers.size() - 1; i >= 0; i--) {
        String layerId = layers.get(i).getId();
        if (!layerId.startsWith("measurement-")) {
          return layerId;
        }
      }
    } catch (Exception e) {
      Log.e(TAG, "Error getting top non-measurement layer", e);
    }
    return null;
  }

  private void repositionLayerIfNeeded(String layerId, String aboveLayerId) {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || layerId.equals(aboveLayerId)) {
        return;
      }

      Layer layer = style.getLayer(layerId);
      Layer aboveLayer = style.getLayer(aboveLayerId);
      if (layer == null || aboveLayer == null) {
        return;
      }

      List<Layer> layers = style.getLayers();
      int currentLayerIndex = -1;
      int aboveLayerIndex = -1;
      for (int i = 0; i < layers.size(); i++) {
        String id = layers.get(i).getId();
        if (id.equals(layerId)) {
          currentLayerIndex = i;
        } else if (id.equals(aboveLayerId)) {
          aboveLayerIndex = i;
        }
      }

      if (currentLayerIndex <= aboveLayerIndex) {
        style.removeLayer(layer);
        style.addLayerAbove(layer, aboveLayerId);
        Log.d(TAG, "Repositioned measurement line above " + aboveLayerId);
      }
    } catch (Exception e) {
      Log.w(TAG, "Could not reposition measurement layer: " + e.getMessage());
    }
  }

  private float screenDistance(PointF a, PointF b) {
    float dx = b.x - a.x;
    float dy = b.y - a.y;
    return (float) Math.sqrt(dx * dx + dy * dy);
  }

  private String actionName(MotionEvent event) {
    switch (event.getActionMasked()) {
      case MotionEvent.ACTION_DOWN:
        return "DOWN";
      case MotionEvent.ACTION_POINTER_DOWN:
        return "POINTER_DOWN";
      case MotionEvent.ACTION_MOVE:
        return "MOVE";
      case MotionEvent.ACTION_POINTER_UP:
        return "POINTER_UP";
      case MotionEvent.ACTION_UP:
        return "UP";
      case MotionEvent.ACTION_CANCEL:
        return "CANCEL";
      default:
        return String.valueOf(event.getActionMasked());
    }
  }

  private double calculateDistanceNauticalMiles(LatLng from, LatLng to) {
    double earthRadiusNm = 3440.065;
    double dLat = Math.toRadians(to.getLatitude() - from.getLatitude());
    double dLon = Math.toRadians(to.getLongitude() - from.getLongitude());
    double fromLat = Math.toRadians(from.getLatitude());
    double toLat = Math.toRadians(to.getLatitude());

    double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
        + Math.cos(fromLat)
        * Math.cos(toLat)
        * Math.sin(dLon / 2)
        * Math.sin(dLon / 2);
    double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusNm * c;
  }

  private double calculateBearing(LatLng from, LatLng to) {
    double dLon = Math.toRadians(to.getLongitude() - from.getLongitude());
    double fromLat = Math.toRadians(from.getLatitude());
    double toLat = Math.toRadians(to.getLatitude());

    double y = Math.sin(dLon) * Math.cos(toLat);
    double x = Math.cos(fromLat) * Math.sin(toLat)
        - Math.sin(fromLat) * Math.cos(toLat) * Math.cos(dLon);
    return (Math.toDegrees(Math.atan2(y, x)) + 360) % 360;
  }
}
