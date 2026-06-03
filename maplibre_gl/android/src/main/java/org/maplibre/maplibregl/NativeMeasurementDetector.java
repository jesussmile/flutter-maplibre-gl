package org.maplibre.maplibregl;

import android.graphics.PointF;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.MotionEvent;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.maps.Style;
import org.maplibre.android.style.layers.CircleLayer;
import org.maplibre.android.style.layers.Layer;
import org.maplibre.android.style.layers.LineLayer;
import org.maplibre.android.style.layers.SymbolLayer;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.FeatureCollection;
import org.maplibre.geojson.LineString;
import org.maplibre.geojson.Point;

import java.util.ArrayList;
import java.util.List;
import static org.maplibre.android.style.expressions.Expression.*;
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
  private static final float RENDER_MOVEMENT_THRESHOLD_PX = 1.5f;
  private static final long MAP_GESTURE_SUPPRESS_MS = 650;

  private static final String MEASUREMENT_SOURCE_ID = "measurement-source";
  private static final String MEASUREMENT_LINE_LAYER_ID = "measurement-line-layer";
  private static final String MEASUREMENT_ENDPOINT_LAYER_ID = "measurement-endpoint-layer";
  private static final String MEASUREMENT_DISTANCE_LAYER_ID = "measurement-distance-layer";
  private static final String MEASUREMENT_START_BEARING_LAYER_ID =
      "measurement-start-bearing-layer";
  private static final String MEASUREMENT_END_BEARING_LAYER_ID =
      "measurement-end-bearing-layer";

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
  private long lastConsumedMeasurementTouchTime = 0;
  private Runnable holdRunnable;
  private PointF lastRenderedStartScreenPoint;
  private PointF lastRenderedEndScreenPoint;

  private String lineColor = "#E8604C";
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
      return markMeasurementTouchConsumed();
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
            return markMeasurementTouchConsumed();
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
          return markMeasurementTouchConsumed();
        }
        cancelGesture();
        break;

      default:
        break;
    }

    return isMeasuring && markMeasurementTouchConsumed();
  }

  public boolean shouldSuppressMapGestureCallbacks() {
    long currentTime = System.currentTimeMillis();
    return isTwoFingerDown
        || isMeasuring
        || isDraggingStart
        || isDraggingEnd
        || (currentTime - lastConsumedMeasurementTouchTime) < MAP_GESTURE_SUPPRESS_MS;
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
          || style.getLayer(MEASUREMENT_LINE_LAYER_ID) == null
          || style.getLayer(MEASUREMENT_ENDPOINT_LAYER_ID) == null
          || style.getLayer(MEASUREMENT_DISTANCE_LAYER_ID) == null
          || style.getLayer(MEASUREMENT_START_BEARING_LAYER_ID) == null
          || style.getLayer(MEASUREMENT_END_BEARING_LAYER_ID) == null) {
        setupMeasurementLayers();
      }

      String topLayerId = getTopNonMeasurementLayerId();
      if (topLayerId != null) {
        repositionLayerIfNeeded(MEASUREMENT_LINE_LAYER_ID, topLayerId);
        repositionLayerIfNeeded(MEASUREMENT_ENDPOINT_LAYER_ID, MEASUREMENT_LINE_LAYER_ID);
        repositionLayerIfNeeded(MEASUREMENT_DISTANCE_LAYER_ID, MEASUREMENT_ENDPOINT_LAYER_ID);
        repositionLayerIfNeeded(
            MEASUREMENT_START_BEARING_LAYER_ID,
            MEASUREMENT_DISTANCE_LAYER_ID);
        repositionLayerIfNeeded(
            MEASUREMENT_END_BEARING_LAYER_ID,
            MEASUREMENT_START_BEARING_LAYER_ID);
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
      renderMeasurementLine(startLatLng, endLatLng, true);

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

      boolean rendered = renderMeasurementLine(startLatLng, endLatLng);
      if (!rendered) {
        return;
      }

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

      renderMeasurementLine(startLatLng, endLatLng, true);
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
          boolean rendered = renderMeasurementLine(startLatLng, endLatLng);
          if (!rendered) {
            return true;
          }
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

  private boolean markMeasurementTouchConsumed() {
    lastConsumedMeasurementTouchTime = System.currentTimeMillis();
    return true;
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
        lineLayer.setFilter(eq(get("type"), literal("line")));

        String topLayerId = getTopNonMeasurementLayerId();
        if (topLayerId != null) {
          style.addLayerAbove(lineLayer, topLayerId);
          Log.d(TAG, "Added measurement line layer above " + topLayerId);
        } else {
          style.addLayer(lineLayer);
          Log.d(TAG, "Added measurement line layer");
        }
      }

      if (style.getLayer(MEASUREMENT_ENDPOINT_LAYER_ID) == null) {
        CircleLayer endpointLayer =
            new CircleLayer(MEASUREMENT_ENDPOINT_LAYER_ID, MEASUREMENT_SOURCE_ID);
        endpointLayer.setProperties(
            circleColor(endpointColor),
            circleRadius((float) endpointRadius),
            circleOpacity(1.0f),
            circleStrokeColor(lineColor),
            circleStrokeWidth(3.0f),
            circleStrokeOpacity(1.0f));
        endpointLayer.setFilter(eq(get("type"), literal("endpoint")));
        style.addLayerAbove(endpointLayer, MEASUREMENT_LINE_LAYER_ID);
        Log.d(TAG, "Added measurement endpoint layer");
      }

      if (style.getLayer(MEASUREMENT_DISTANCE_LAYER_ID) == null) {
        SymbolLayer distanceLayer =
            new SymbolLayer(MEASUREMENT_DISTANCE_LAYER_ID, MEASUREMENT_SOURCE_ID);
        distanceLayer.setProperties(
            textField(get("label-text")),
            textFont(new String[]{"Noto Sans Bold"}),
            textSize(15.0f),
            textColor("#FFFFFF"),
            textHaloColor("#07111F"),
            textHaloWidth(2.2f),
            textAnchor("center"),
            textOffset(new Float[]{0.0f, -1.5f}),
            textAllowOverlap(true),
            textIgnorePlacement(true));
        distanceLayer.setFilter(eq(get("type"), literal("distance")));
        style.addLayerAbove(distanceLayer, MEASUREMENT_ENDPOINT_LAYER_ID);
        Log.d(TAG, "Added measurement distance label layer");
      }

      if (style.getLayer(MEASUREMENT_START_BEARING_LAYER_ID) == null) {
        SymbolLayer startBearingLayer =
            new SymbolLayer(MEASUREMENT_START_BEARING_LAYER_ID, MEASUREMENT_SOURCE_ID);
        startBearingLayer.setProperties(
            textField(get("label-text")),
            textFont(new String[]{"Noto Sans Bold"}),
            textSize(15.0f),
            textColor("#FFFFFF"),
            textHaloColor("#07111F"),
            textHaloWidth(2.0f),
            textAnchor("center"),
            textOffset(new Float[]{0.0f, -1.05f}),
            textRotate(get("label-rotation")),
            textRotationAlignment("map"),
            textPitchAlignment("map"),
            textKeepUpright(true),
            textAllowOverlap(true),
            textIgnorePlacement(true));
        startBearingLayer.setFilter(eq(get("type"), literal("start-bearing")));
        style.addLayerAbove(startBearingLayer, MEASUREMENT_DISTANCE_LAYER_ID);
        Log.d(TAG, "Added measurement start bearing label layer");
      }

      if (style.getLayer(MEASUREMENT_END_BEARING_LAYER_ID) == null) {
        SymbolLayer endBearingLayer =
            new SymbolLayer(MEASUREMENT_END_BEARING_LAYER_ID, MEASUREMENT_SOURCE_ID);
        endBearingLayer.setProperties(
            textField(get("label-text")),
            textFont(new String[]{"Noto Sans Bold"}),
            textSize(15.0f),
            textColor("#FFFFFF"),
            textHaloColor("#07111F"),
            textHaloWidth(2.0f),
            textAnchor("center"),
            textOffset(new Float[]{0.0f, 1.05f}),
            textRotate(get("label-rotation")),
            textRotationAlignment("map"),
            textPitchAlignment("map"),
            textKeepUpright(true),
            textAllowOverlap(true),
            textIgnorePlacement(true));
        endBearingLayer.setFilter(eq(get("type"), literal("end-bearing")));
        style.addLayerAbove(endBearingLayer, MEASUREMENT_START_BEARING_LAYER_ID);
        Log.d(TAG, "Added measurement end bearing label layer");
      }
    } catch (Exception e) {
      Log.e(TAG, "Error setting up measurement layers", e);
    }
  }

  private boolean renderMeasurementLine(LatLng start, LatLng end) {
    return renderMeasurementLine(start, end, false);
  }

  private boolean renderMeasurementLine(LatLng start, LatLng end, boolean force) {
    try {
      Style style = mapLibreMap.getStyle();
      if (style == null || !style.isFullyLoaded()) {
        Log.w(TAG, "Map style not ready for measurement rendering");
        return false;
      }

      PointF startScreenPoint = mapLibreMap.getProjection().toScreenLocation(start);
      PointF endScreenPoint = mapLibreMap.getProjection().toScreenLocation(end);
      if (!force && !shouldRenderMeasurement(startScreenPoint, endScreenPoint)) {
        return false;
      }

      Point startPoint = Point.fromLngLat(start.getLongitude(), start.getLatitude());
      Point endPoint = Point.fromLngLat(end.getLongitude(), end.getLatitude());
      Point startBearingPoint = interpolateLinePoint(start, end, 0.12);
      Point endBearingPoint = interpolateLinePoint(start, end, 0.88);
      double midLatitude = (start.getLatitude() + end.getLatitude()) / 2.0;
      double midLongitude = (start.getLongitude() + end.getLongitude()) / 2.0;
      Point midPoint = Point.fromLngLat(midLongitude, midLatitude);
      List<Point> points = new ArrayList<>();
      points.add(startPoint);
      points.add(endPoint);

      double distance = calculateDistanceNauticalMiles(start, end);
      double bearing = calculateBearing(start, end);
      double reciprocalBearing = (bearing + 180.0) % 360.0;
      double lineLabelRotation = calculateLineTextRotation(bearing);

      Feature lineFeature = Feature.fromGeometry(LineString.fromLngLats(points));
      lineFeature.addStringProperty("type", "line");
      Feature startFeature = Feature.fromGeometry(startPoint);
      startFeature.addStringProperty("type", "endpoint");
      Feature endFeature = Feature.fromGeometry(endPoint);
      endFeature.addStringProperty("type", "endpoint");
      Feature distanceFeature = Feature.fromGeometry(midPoint);
      distanceFeature.addStringProperty("type", "distance");
      distanceFeature.addStringProperty(
          "label-text",
          String.format("%.1f NM", distance));
      Feature startBearingFeature = Feature.fromGeometry(startBearingPoint);
      startBearingFeature.addStringProperty("type", "start-bearing");
      startBearingFeature.addStringProperty(
          "label-text",
          String.format("%03.0f°", bearing));
      startBearingFeature.addNumberProperty("label-rotation", lineLabelRotation);
      Feature endBearingFeature = Feature.fromGeometry(endBearingPoint);
      endBearingFeature.addStringProperty("type", "end-bearing");
      endBearingFeature.addStringProperty(
          "label-text",
          String.format("%03.0f°", reciprocalBearing));
      endBearingFeature.addNumberProperty("label-rotation", lineLabelRotation);

      List<Feature> features = new ArrayList<>();
      features.add(lineFeature);
      features.add(startFeature);
      features.add(endFeature);
      features.add(distanceFeature);
      features.add(startBearingFeature);
      features.add(endBearingFeature);

      GeoJsonSource source = style.getSourceAs(MEASUREMENT_SOURCE_ID);
      if (source != null) {
        source.setGeoJson(FeatureCollection.fromFeatures(features));
        lastRenderedStartScreenPoint = startScreenPoint;
        lastRenderedEndScreenPoint = endScreenPoint;
        Log.v(TAG, "Updated native measurement rendering");
        return true;
      } else {
        Log.w(TAG, "Measurement source missing during render");
      }
    } catch (Exception e) {
      Log.e(TAG, "Error rendering measurement line", e);
    }
    return false;
  }

  private boolean shouldRenderMeasurement(PointF startScreenPoint, PointF endScreenPoint) {
    if (lastRenderedStartScreenPoint == null || lastRenderedEndScreenPoint == null) {
      return true;
    }

    return screenDistance(lastRenderedStartScreenPoint, startScreenPoint)
        >= RENDER_MOVEMENT_THRESHOLD_PX
        || screenDistance(lastRenderedEndScreenPoint, endScreenPoint)
        >= RENDER_MOVEMENT_THRESHOLD_PX;
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
      lastRenderedStartScreenPoint = null;
      lastRenderedEndScreenPoint = null;
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
        lineLayer.setFilter(eq(get("type"), literal("line")));
      }

      CircleLayer endpointLayer = style.getLayerAs(MEASUREMENT_ENDPOINT_LAYER_ID);
      if (endpointLayer != null) {
        endpointLayer.setProperties(
            circleColor(endpointColor),
            circleRadius((float) endpointRadius),
            circleOpacity(1.0f),
            circleStrokeColor(lineColor),
            circleStrokeWidth(3.0f),
            circleStrokeOpacity(1.0f));
        endpointLayer.setFilter(eq(get("type"), literal("endpoint")));
      }

      SymbolLayer distanceLayer = style.getLayerAs(MEASUREMENT_DISTANCE_LAYER_ID);
      if (distanceLayer != null) {
        distanceLayer.setProperties(
            textField(get("label-text")),
            textFont(new String[]{"Noto Sans Bold"}),
            textSize(15.0f),
            textColor("#FFFFFF"),
            textHaloColor("#07111F"),
            textHaloWidth(2.2f),
            textAnchor("center"),
            textOffset(new Float[]{0.0f, -1.5f}),
            textAllowOverlap(true),
            textIgnorePlacement(true));
        distanceLayer.setFilter(eq(get("type"), literal("distance")));
      }

      SymbolLayer startBearingLayer =
          style.getLayerAs(MEASUREMENT_START_BEARING_LAYER_ID);
      if (startBearingLayer != null) {
        startBearingLayer.setProperties(
            textField(get("label-text")),
            textFont(new String[]{"Noto Sans Bold"}),
            textSize(15.0f),
            textColor("#FFFFFF"),
            textHaloColor("#07111F"),
            textHaloWidth(2.0f),
            textAnchor("center"),
            textOffset(new Float[]{0.0f, -1.05f}),
            textRotate(get("label-rotation")),
            textRotationAlignment("map"),
            textPitchAlignment("map"),
            textKeepUpright(true),
            textAllowOverlap(true),
            textIgnorePlacement(true));
        startBearingLayer.setFilter(eq(get("type"), literal("start-bearing")));
      }

      SymbolLayer endBearingLayer =
          style.getLayerAs(MEASUREMENT_END_BEARING_LAYER_ID);
      if (endBearingLayer != null) {
        endBearingLayer.setProperties(
            textField(get("label-text")),
            textFont(new String[]{"Noto Sans Bold"}),
            textSize(15.0f),
            textColor("#FFFFFF"),
            textHaloColor("#07111F"),
            textHaloWidth(2.0f),
            textAnchor("center"),
            textOffset(new Float[]{0.0f, 1.05f}),
            textRotate(get("label-rotation")),
            textRotationAlignment("map"),
            textPitchAlignment("map"),
            textKeepUpright(true),
            textAllowOverlap(true),
            textIgnorePlacement(true));
        endBearingLayer.setFilter(eq(get("type"), literal("end-bearing")));
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
        Log.d(TAG, "Repositioned " + layerId + " above " + aboveLayerId);
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

  private double calculateLineTextRotation(double bearing) {
    double rotation = (bearing - 90.0) % 360.0;
    if (rotation < 0.0) {
      rotation += 360.0;
    }

    if (rotation > 90.0 && rotation < 270.0) {
      rotation = (rotation + 180.0) % 360.0;
    }

    return rotation;
  }

  private Point interpolateLinePoint(LatLng start, LatLng end, double fraction) {
    double startLongitude = start.getLongitude();
    double endLongitude = end.getLongitude();
    double longitudeDelta = endLongitude - startLongitude;

    if (longitudeDelta > 180.0) {
      longitudeDelta -= 360.0;
    } else if (longitudeDelta < -180.0) {
      longitudeDelta += 360.0;
    }

    double latitude =
        start.getLatitude() + ((end.getLatitude() - start.getLatitude()) * fraction);
    double longitude = startLongitude + (longitudeDelta * fraction);

    if (longitude > 180.0) {
      longitude -= 360.0;
    } else if (longitude < -180.0) {
      longitude += 360.0;
    }

    return Point.fromLngLat(longitude, latitude);
  }
}
