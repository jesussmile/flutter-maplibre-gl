// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package org.maplibre.maplibregl;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.res.AssetFileDescriptor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PointF;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.location.Location;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.TextureView;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.util.Pair;

import androidx.annotation.NonNull;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonParser;

import org.maplibre.android.gestures.AndroidGesturesManager;
import org.maplibre.android.gestures.MoveGestureDetector;
import org.maplibre.android.location.engine.LocationEngine;
import org.maplibre.android.location.engine.LocationEngineDefault;
import org.maplibre.android.location.engine.LocationEngineProxy;
import org.maplibre.android.location.engine.LocationEngineRequest;
import org.maplibre.geojson.Feature;
import org.maplibre.geojson.FeatureCollection;
import org.maplibre.android.camera.CameraPosition;
import org.maplibre.android.camera.CameraUpdate;
import org.maplibre.android.camera.CameraUpdateFactory;
import org.maplibre.android.constants.MapLibreConstants;
import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.geometry.LatLngBounds;
import org.maplibre.android.geometry.LatLngQuad;
import org.maplibre.android.geometry.VisibleRegion;
import org.maplibre.android.location.LocationComponent;
import org.maplibre.android.location.LocationComponentActivationOptions;
import org.maplibre.android.location.LocationComponentOptions;
import org.maplibre.android.location.OnCameraTrackingChangedListener;
import org.maplibre.android.location.engine.LocationEngineCallback;
import org.maplibre.android.location.engine.LocationEngineResult;
import org.maplibre.android.location.modes.CameraMode;
import org.maplibre.android.location.modes.RenderMode;
import org.maplibre.android.maps.MapView;
import org.maplibre.android.maps.MapLibreMap;
import org.maplibre.android.maps.MapLibreMapOptions;
import org.maplibre.android.maps.OnMapReadyCallback;
import org.maplibre.android.maps.Style;
import org.maplibre.android.offline.OfflineManager;
import org.maplibre.android.style.expressions.Expression;
import org.maplibre.android.style.layers.CircleLayer;
import org.maplibre.android.style.layers.FillExtrusionLayer;
import org.maplibre.android.style.layers.FillLayer;
import org.maplibre.android.style.layers.HeatmapLayer;
import org.maplibre.android.style.layers.HillshadeLayer;
import org.maplibre.android.style.layers.Layer;
import org.maplibre.android.style.layers.LineLayer;
import org.maplibre.android.style.layers.Property;
import org.maplibre.android.style.layers.PropertyValue;
import org.maplibre.android.style.layers.RasterLayer;
import org.maplibre.android.style.layers.SymbolLayer;
// import org.maplibre.android.style.layers.TriangleLayer; // Not available in MapLibre Android SDK
import org.maplibre.android.style.layers.CustomLayer;
import org.maplibre.android.style.layers.PropertyFactory;
import org.maplibre.android.style.sources.CustomGeometrySource;
import org.maplibre.android.style.sources.GeoJsonSource;
import org.maplibre.android.style.sources.ImageSource;
import org.maplibre.android.style.sources.Source;
import org.maplibre.android.style.sources.VectorSource;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

// Polyline editing imports
import org.maplibre.maplibregl.PolylineEditingManager;
import org.maplibre.maplibregl.PolylineBreakPointSystem;
import org.maplibre.maplibregl.EditablePolylineRenderer;
import org.maplibre.maplibregl.PolylineGestureDetector;

import java.util.concurrent.ConcurrentHashMap;

/** Controller of a single MapLibreMaps MapView instance. */
@SuppressLint("MissingPermission")
final class MapLibreMapController
    implements DefaultLifecycleObserver,
        MapLibreMap.OnCameraIdleListener,
        MapLibreMap.OnCameraMoveListener,
        MapLibreMap.OnCameraMoveStartedListener,
        MapView.OnDidBecomeIdleListener,
        MapLibreMap.OnMapClickListener,
        MapLibreMap.OnMapLongClickListener,
        MapLibreMapOptionsSink,
        MethodChannel.MethodCallHandler,
        OnMapReadyCallback,
        OnCameraTrackingChangedListener,
        PlatformView {
  
  
  private static final String TAG = "MapLibreMapController";
  
  // Feature flags for experimental features
  private static final boolean ENABLE_EXPERIMENTAL_TRIANGLE_LAYERS;
  
  static {
    String systemProp = System.getProperty("maplibre.experimental.triangleLayers", "false");
    String envVar = System.getenv("MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS");
    boolean sysPropEnabled = Boolean.parseBoolean(systemProp);
    boolean envVarEnabled = "true".equalsIgnoreCase(envVar);
    
    // Also check BuildConfig if available (from Gradle build configuration)
    boolean buildConfigEnabled = false;
    try {
      // Use reflection to check BuildConfig without compile-time dependency on example app
      Class<?> buildConfigClass = Class.forName("org.maplibre.example.BuildConfig");
      java.lang.reflect.Field field = buildConfigClass.getDeclaredField("ENABLE_EXPERIMENTAL_TRIANGLE_LAYERS");
      buildConfigEnabled = field.getBoolean(null);
    } catch (Exception e) {
      // BuildConfig not available or field doesn't exist - that's okay
    }
    
    ENABLE_EXPERIMENTAL_TRIANGLE_LAYERS = sysPropEnabled || envVarEnabled || buildConfigEnabled;
    
    Log.d("MapLibreMapController", "Triangle layers experimental flag check:");
    Log.d("MapLibreMapController", "  System property 'maplibre.experimental.triangleLayers': " + systemProp);
    Log.d("MapLibreMapController", "  Environment variable 'MAPLIBRE_EXPERIMENTAL_TRIANGLE_LAYERS': " + envVar);
    Log.d("MapLibreMapController", "  BuildConfig ENABLE_EXPERIMENTAL_TRIANGLE_LAYERS: " + buildConfigEnabled);
    Log.d("MapLibreMapController", "  System property enabled: " + sysPropEnabled);
    Log.d("MapLibreMapController", "  Environment variable enabled: " + envVarEnabled);
    Log.d("MapLibreMapController", "  BuildConfig enabled: " + buildConfigEnabled);
    Log.d("MapLibreMapController", "  Final ENABLE_EXPERIMENTAL_TRIANGLE_LAYERS: " + ENABLE_EXPERIMENTAL_TRIANGLE_LAYERS);
  }
  
  private final int id;
  private final MethodChannel methodChannel;
  private final MapLibreMapsPlugin.LifecycleProvider lifecycleProvider;
  private final float density;
  private final Context context;
  private final String styleStringInitial;
  /**
   * This container is returned as the final platform view instead of returning `mapView`.
   * See {@link MapLibreMapController#destroyMapViewIfNecessary()} for details.
   */
  private FrameLayout mapViewContainer;
  private MapView mapView;
  private MapLibreMap mapLibreMap;
  private boolean trackCameraPosition = false;
  private boolean myLocationEnabled = false;
  private int myLocationTrackingMode = 0;
  private int myLocationRenderMode = 0;
  private boolean disposed = false;
  private boolean dragEnabled = true;
  private boolean featureTapsTriggersMapClick = false;
  private MethodChannel.Result mapReadyResult;
  private LocationComponent locationComponent = null;
  private LocationEngineCallback<LocationEngineResult> locationEngineCallback = null;
  private Style style;
  private Feature draggedFeature;
  private AndroidGesturesManager androidGesturesManager;
  private PolylineEditingManager polylineEditingManager;
  private PolylineBreakPointSystem polylineBreakPointSystem;
  private EditablePolylineRenderer polylineRenderer;
  private PolylineGestureDetector polylineGestureDetector;
  private TextView polylineDeleteZoneView;
  private NativeMeasurementDetector nativeMeasurementDetector;

  private LatLng dragOrigin;
  private LatLng dragPrevious;

  private Set<String> interactiveFeatureLayerIds;
  private Map<String, FeatureCollection> addedFeaturesByLayer;
  private Map<String, ImageOverlayControlsView> imageOverlayControls;

  // Debounce handling for altitude updates
  private final Map<String, android.os.Handler> debounceHandlers = new ConcurrentHashMap<>();
  private static final long DEBOUNCE_DELAY_MS = 300; // 300ms debounce delay

  private LatLngBounds bounds = null;
  // Package-private accessors for terrain manager integration
  MapLibreMap getMapLibreMap() {
    return mapLibreMap;
  }
  
  Style getStyle() {
    return style;
  }

  

  Style.OnStyleLoaded onStyleLoadedCallback =
      new Style.OnStyleLoaded() {
        @Override
        public void onStyleLoaded(@NonNull Style style) {
          MapLibreMapController.this.style = style;

          // commented out while cherry-picking upstream956
          // if (myLocationEnabled) {
          //   if (hasLocationPermission()) {
          //     updateMyLocationEnabled();
          //   }
          // }
          updateMyLocationEnabled();

          if (null != bounds) {
            mapLibreMap.setLatLngBoundsForCameraTarget(bounds);
          }

          mapLibreMap.addOnMapClickListener(MapLibreMapController.this);
          mapLibreMap.addOnMapLongClickListener(MapLibreMapController.this);

          // Initialize polyline renderer after style is loaded
          if (polylineRenderer != null) {
            polylineRenderer.initialize();
          }

          if (nativeMeasurementDetector != null) {
            nativeMeasurementDetector.ensureMeasurementLayersOnTop();
          }

          methodChannel.invokeMethod("map#onStyleLoaded", null);
        }
      };

  MapLibreMapController(
      int id,
      Context context,
      BinaryMessenger messenger,
      MapLibreMapsPlugin.LifecycleProvider lifecycleProvider,
      MapLibreMapOptions options,
      String styleStringInitial,
      boolean dragEnabled,
      boolean featureTapsTriggersMapClick) {
    MapLibreUtils.getMapLibre(context);
    this.id = id;
    this.context = context;
    this.dragEnabled = dragEnabled;
    this.featureTapsTriggersMapClick = featureTapsTriggersMapClick;
    this.styleStringInitial = styleStringInitial;
    this.mapViewContainer = new FrameLayout(context);
    this.mapView = new MapView(context, options);
    this.interactiveFeatureLayerIds = new HashSet<>();
    this.addedFeaturesByLayer = new HashMap<String, FeatureCollection>();
    this.imageOverlayControls = new HashMap<>();
    this.density = context.getResources().getDisplayMetrics().density;
    this.lifecycleProvider = lifecycleProvider;
    if (dragEnabled) {
      this.androidGesturesManager = new AndroidGesturesManager(this.mapView.getContext(), false);
    }

    mapViewContainer.addView(mapView);
    methodChannel = new MethodChannel(messenger, "plugins.flutter.io/maplibre_gl_" + id);
    methodChannel.setMethodCallHandler(this);
    

  }

  @Override
  public View getView() {
    return mapViewContainer;
  }

  void init() {
    lifecycleProvider.getLifecycle().addObserver(this);
    mapView.getMapAsync(this);
  }

  private void moveCamera(CameraUpdate cameraUpdate) {
    mapLibreMap.moveCamera(cameraUpdate);
  }

  private void animateCamera(CameraUpdate cameraUpdate) {
    mapLibreMap.animateCamera(cameraUpdate);
  }

  private CameraPosition getCameraPosition() {
    return trackCameraPosition ? mapLibreMap.getCameraPosition() : null;
  }

  @Override
  public void onMapReady(MapLibreMap mapLibreMap) {
    this.mapLibreMap = mapLibreMap;
    if (mapReadyResult != null) {
      mapReadyResult.success(null);
      mapReadyResult = null;
    }
    mapLibreMap.addOnCameraMoveStartedListener(this);
    mapLibreMap.addOnCameraMoveListener(this);
    mapLibreMap.addOnCameraIdleListener(this);





    // Initialize polyline editing manager
    polylineEditingManager = new PolylineEditingManager(mapLibreMap);
    
    // Initialize polyline break point system
    polylineBreakPointSystem = new PolylineBreakPointSystem(mapLibreMap);
    
    // Initialize polyline renderer
    polylineRenderer = new EditablePolylineRenderer(mapLibreMap);
    
  // Initialize polyline gesture detector with callback implementation
  polylineGestureDetector = new PolylineGestureDetector(
      mapLibreMap, 
      polylineEditingManager, 
      polylineBreakPointSystem,
      polylineRenderer,
      mapView,
      density,
      new PolylineGestureDetector.OnPolylineGestureListener() {
        @Override
        public void onPolylineBroken(@NonNull String lineId, @NonNull LatLng breakPoint, 
                                   @NonNull List<LatLng> segment1, @NonNull List<LatLng> segment2) {
          try {
            // Show break point marker visually
            if (polylineRenderer != null) {
              polylineRenderer.showBreakPoint(lineId, breakPoint);
            }
            
            // Convert LatLng coordinates to Flutter format
            List<List<Double>> segment1Coords = convertLatLngListToCoordinates(segment1);
            List<List<Double>> segment2Coords = convertLatLngListToCoordinates(segment2);
            
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("lineId", lineId);
            arguments.put("segment1", segment1Coords);
            arguments.put("segment2", segment2Coords);
            
            Log.d(TAG, "Sending polylineEditing#onBroken callback for line: " + lineId);
            methodChannel.invokeMethod("polylineEditing#onBroken", arguments);
          } catch (Exception e) {
            Log.e(TAG, "Error sending onPolylineBroken callback: " + e.getMessage(), e);
          }
        }
        
        @Override
        public void onPolylineModified(@NonNull String lineId, @NonNull List<LatLng> newCoordinates) {
          try {
            // Hide visual feedback elements
            if (polylineRenderer != null) {
              polylineRenderer.hideBreakPoint(lineId);
            }
            
            // Convert LatLng coordinates to Flutter format
            List<List<Double>> coordinates = convertLatLngListToCoordinates(newCoordinates);
            
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("lineId", lineId);
            arguments.put("coordinates", coordinates);
            
            Log.d(TAG, "Sending polylineEditing#onModified callback for line: " + lineId);
            methodChannel.invokeMethod("polylineEditing#onModified", arguments);
          } catch (Exception e) {
            Log.e(TAG, "Error sending onPolylineModified callback: " + e.getMessage(), e);
          }
        }

        @Override
        public void onPolylineEditCompleted(
            @NonNull String lineId,
            @NonNull List<LatLng> newCoordinates,
            int pointIndex,
            boolean inserted) {
          List<List<Double>> coordinates = convertLatLngListToCoordinates(newCoordinates);
          Map<String, Object> arguments = new HashMap<>();
          arguments.put("lineId", lineId);
          arguments.put("coordinates", coordinates);
          arguments.put("pointIndex", pointIndex);
          arguments.put("inserted", inserted);
          methodChannel.invokeMethod("polylineEditing#onCompleted", arguments);
        }

        @Override
        public void onPolylinePointDeleted(
            @NonNull String lineId,
            @NonNull List<LatLng> newCoordinates,
            int pointIndex,
            @NonNull LatLng deletedCoordinate) {
          List<List<Double>> coordinates = convertLatLngListToCoordinates(newCoordinates);
          Map<String, Object> arguments = new HashMap<>();
          arguments.put("lineId", lineId);
          arguments.put("coordinates", coordinates);
          arguments.put("pointIndex", pointIndex);
          arguments.put(
              "deletedCoordinate",
              Arrays.asList(deletedCoordinate.getLatitude(), deletedCoordinate.getLongitude()));
          methodChannel.invokeMethod("polylineEditing#onPointDeleted", arguments);
        }

        @Override
        public void onPolylineDeleteZoneChanged(boolean visible, boolean armed) {
          setPolylineDeleteZoneVisible(visible, armed);
        }
        
        @Override
        public void onPolylineEditingError(@NonNull String lineId, @NonNull String error) {
          try {
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("lineId", lineId);
            arguments.put("error", error);
            
            Log.d(TAG, "Sending polylineEditing#onError callback for line: " + lineId);
            methodChannel.invokeMethod("polylineEditing#onError", arguments);
          } catch (Exception e) {
            Log.e(TAG, "Error sending onPolylineEditingError callback: " + e.getMessage(), e);
          }
        }
      }
  );

    if (androidGesturesManager != null) {
      androidGesturesManager.setMoveGestureListener(new MoveGestureListener());
      mapView.setOnTouchListener(
          new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
              emitMapTouchState(event);

              if (nativeMeasurementDetector != null
                  && nativeMeasurementDetector.onTouchEvent(event)) {
                return true;
              }

              // Handle polyline editing gestures
              if (polylineGestureDetector != null) {
                boolean polylineHandled = polylineGestureDetector.onTouchEvent(event);
                if (polylineHandled) {
                  return true; // Polyline gesture consumed the event
                }
              }

              androidGesturesManager.onTouchEvent(event);

              boolean consumedByDrag = draggedFeature != null;
              return consumedByDrag;
            }
          });
    }

    mapView.addOnStyleImageMissingListener(
        (id) -> {
          DisplayMetrics displayMetrics = context.getResources().getDisplayMetrics();
          final Bitmap bitmap = getScaledImage(id, displayMetrics.density);
          if (bitmap != null) {
            mapLibreMap.getStyle().addImage(id, bitmap);
          }
        });

    mapView.addOnDidBecomeIdleListener(this);

    setStyleString(styleStringInitial);
  }

  @Override
  public void setStyleString(@NonNull String styleString) {
    // clear old layer id from the location Component
    clearLocationComponentLayer();
    styleString = styleString.trim();

    // Check if json, url, absolute path or asset path:
    if (styleString == null || styleString.isEmpty()) {
      Log.e(TAG, "setStyleString - string empty or null");
    } else if (styleString.startsWith("{") || styleString.startsWith("[")) {
      mapLibreMap.setStyle(new Style.Builder().fromJson(styleString), onStyleLoadedCallback);
    } else if (styleString.startsWith("/")) {
      // Absolute path
      mapLibreMap.setStyle(
          new Style.Builder().fromUri("file://" + styleString), onStyleLoadedCallback);
    } else if (!styleString.startsWith("http://")
        && !styleString.startsWith("https://")
        && !styleString.startsWith("mapbox://")) {
      // We are assuming that the style will be loaded from an asset here.
      String key = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(styleString);
      mapLibreMap.setStyle(new Style.Builder().fromUri("asset://" + key), onStyleLoadedCallback);
    } else {
      mapLibreMap.setStyle(new Style.Builder().fromUri(styleString), onStyleLoadedCallback);
    }
  }



  @SuppressWarnings({"MissingPermission"})
  private void enableLocationComponent(@NonNull Style style) {
    if (hasLocationPermission()) {

      locationComponent = mapLibreMap.getLocationComponent();

      LocationComponentActivationOptions options =
              LocationComponentActivationOptions
                      .builder(context, style)
                      .locationComponentOptions(buildLocationComponentOptions(style))
                      .build();

      locationComponent.activateLocationComponent(options);
      locationComponent.setLocationComponentEnabled(true);
      locationComponent.setMaxAnimationFps(30);
      updateMyLocationTrackingMode();
      updateMyLocationRenderMode();
      locationComponent.addOnCameraTrackingChangedListener(this);
    } else {
      Log.e(TAG, "missing location permissions");
    }
  }

  private void updateLocationComponentLayer() {
    if (locationComponent != null && locationComponentRequiresUpdate()) {
      locationComponent.applyStyle(buildLocationComponentOptions(style));
    }
  }

  private void clearLocationComponentLayer() {
    if (locationComponent != null) {
      locationComponent.applyStyle(buildLocationComponentOptions(null));
    }
  }

  String getLastLayerOnStyle(Style style) {
    if (style != null) {
      final List<Layer> layers = style.getLayers();

      if (layers.size() > 0) {
        return layers.get(layers.size() - 1).getId();
      }
    }
    return null;
  }

  /// only update if the last layer is not the mapbox-location-bearing-layer
  boolean locationComponentRequiresUpdate() {
    final String lastLayerId = getLastLayerOnStyle(style);
    return lastLayerId != null && !lastLayerId.equals("mapbox-location-bearing-layer");
  }

  private LocationComponentOptions buildLocationComponentOptions(Style style) {
    final LocationComponentOptions.Builder optionsBuilder =
        LocationComponentOptions.builder(context);
    optionsBuilder.trackingGesturesManagement(true);

    final String lastLayerId = getLastLayerOnStyle(style);
    if (lastLayerId != null) {
      optionsBuilder.layerAbove(lastLayerId);
    }
    return optionsBuilder.build();
  }

  private void onUserLocationUpdate(Location location) {
    if (location == null) {
      return;
    }

    final Map<String, Object> userLocation = new HashMap<>(6);
    userLocation.put("position", new double[] {location.getLatitude(), location.getLongitude()});
    userLocation.put("speed", location.getSpeed());
    userLocation.put("altitude", location.getAltitude());
    userLocation.put("bearing", location.getBearing());
    userLocation.put("speed", location.getSpeed());
    userLocation.put("horizontalAccuracy", location.getAccuracy());
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      userLocation.put(
          "verticalAccuracy",
          (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
              ? location.getVerticalAccuracyMeters()
              : null);
    }
    userLocation.put("timestamp", location.getTime());

    final Map<String, Object> arguments = new HashMap<>(1);
    arguments.put("userLocation", userLocation);
    methodChannel.invokeMethod("map#onUserLocationUpdated", arguments);
  }

  private void addGeoJsonSource(String sourceName, String source) {
    FeatureCollection featureCollection = FeatureCollection.fromJson(source);
    addedFeaturesByLayer.put(sourceName, featureCollection);

    Source existingSource = style.getSource(sourceName);
    if (existingSource instanceof GeoJsonSource) {
      ((GeoJsonSource) existingSource).setGeoJson(featureCollection);
      return;
    }

    if (existingSource != null) {
      Log.w(
          TAG,
          "Attempted to add GeoJSON source '" + sourceName + "' but an incompatible source exists.");
      return;
    }

    GeoJsonSource geoJsonSource = new GeoJsonSource(sourceName, featureCollection);
    style.addSource(geoJsonSource);
  }

  private void setGeoJsonSource(String sourceName, String geojson) {
    FeatureCollection featureCollection = FeatureCollection.fromJson(geojson);
    addedFeaturesByLayer.put(sourceName, featureCollection);

    GeoJsonSource geoJsonSource = style.getSourceAs(sourceName);
    if (geoJsonSource == null) {
      Source existingSource = style.getSource(sourceName);
      if (existingSource != null) {
        Log.w(
            TAG,
            "Attempted to update GeoJSON source '" + sourceName + "' but an incompatible source exists.");
        return;
      }

      geoJsonSource = new GeoJsonSource(sourceName, featureCollection);
      style.addSource(geoJsonSource);
      return;
    }

    geoJsonSource.setGeoJson(featureCollection);
  }

  private void setGeoJsonFeature(String sourceName, String geojsonFeature) {
    Feature feature = Feature.fromJson(geojsonFeature);
    FeatureCollection featureCollection = addedFeaturesByLayer.get(sourceName);
    GeoJsonSource geoJsonSource = style.getSourceAs(sourceName);
    if (featureCollection != null && geoJsonSource != null) {
      final List<Feature> features = featureCollection.features();
      for (int i = 0; i < features.size(); i++) {
        final String id = features.get(i).id();
        if (id.equals(feature.id())) {
          features.set(i, feature);
          break;
        }
      }

      geoJsonSource.setGeoJson(featureCollection);
    }
  }

  private void addSymbolLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    SymbolLayer symbolLayer = new SymbolLayer(layerName, sourceName);
    symbolLayer.setProperties(properties);
    if (sourceLayer != null) {
      symbolLayer.setSourceLayer(sourceLayer);
    }
    if (minZoom != null) {
      symbolLayer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      symbolLayer.setMaxZoom(maxZoom);
    }
    if (filter != null) {
      symbolLayer.setFilter(filter);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(symbolLayer, belowLayerId);
    } else {
      style.addLayer(symbolLayer);
    }
    if (enableInteraction) {
      interactiveFeatureLayerIds.add(layerName);
    }
  }

  private void addLineLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    LineLayer lineLayer = new LineLayer(layerName, sourceName);
    lineLayer.setProperties(properties);
    if (sourceLayer != null) {
      lineLayer.setSourceLayer(sourceLayer);
    }
    if (minZoom != null) {
      lineLayer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      lineLayer.setMaxZoom(maxZoom);
    }
    if (filter != null) {
      lineLayer.setFilter(filter);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(lineLayer, belowLayerId);
    } else {
      style.addLayer(lineLayer);
    }
    if (enableInteraction) {
      interactiveFeatureLayerIds.add(layerName);
    }
  }

  private void addFillLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    FillLayer fillLayer = new FillLayer(layerName, sourceName);
    fillLayer.setProperties(properties);
    if (sourceLayer != null) {
      fillLayer.setSourceLayer(sourceLayer);
    }
    if (minZoom != null) {
      fillLayer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      fillLayer.setMaxZoom(maxZoom);
    }
    if (filter != null) {
      fillLayer.setFilter(filter);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(fillLayer, belowLayerId);
    } else {
      style.addLayer(fillLayer);
    }
    if (enableInteraction) {
      interactiveFeatureLayerIds.add(layerName);
    }
  }

  private void addFillExtrusionLayer(
          String layerName,
          String sourceName,
          String belowLayerId,
          String sourceLayer,
          Float minZoom,
          Float maxZoom,
          PropertyValue[] properties,
          boolean enableInteraction,
          Expression filter) {
    FillExtrusionLayer fillLayer = new FillExtrusionLayer(layerName, sourceName);
    fillLayer.setProperties(properties);
    if (sourceLayer != null) {
      fillLayer.setSourceLayer(sourceLayer);
    }
    if (minZoom != null) {
      fillLayer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      fillLayer.setMaxZoom(maxZoom);
    }
    if (filter != null) {
      fillLayer.setFilter(filter);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(fillLayer, belowLayerId);
    } else {
      style.addLayer(fillLayer);
    }
    if (enableInteraction) {
      interactiveFeatureLayerIds.add(layerName);
    }
  }

  private void addCircleLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    CircleLayer circleLayer = new CircleLayer(layerName, sourceName);
    circleLayer.setProperties(properties);
    if (sourceLayer != null) {
      circleLayer.setSourceLayer(sourceLayer);
    }
    if (minZoom != null) {
      circleLayer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      circleLayer.setMaxZoom(maxZoom);
    }
    if (filter != null) {
      circleLayer.setFilter(filter);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(circleLayer, belowLayerId);
    } else {
      style.addLayer(circleLayer);
    }
    if (enableInteraction) {
      interactiveFeatureLayerIds.add(layerName);
    }
  }

  // Triangle layer implementation using symbol layers with triangle icons
  private void addTriangleLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    
    Log.d(TAG, "Adding triangle symbol layer: " + layerName);
    
    try {
      // Create triangle icon if it doesn't exist
      ensureTriangleIconExists();
      
      // Use symbol layer with triangle icon for triangle rendering
      addTriangleSymbolLayer(layerName, sourceName, belowLayerId, sourceLayer, minZoom, maxZoom, properties, enableInteraction, filter);
      
    } catch (Exception e) {
      String errorMessage = "Failed to create triangle layer '" + layerName + "': " + e.getMessage();
      Log.e(TAG, errorMessage, e);
      throw new RuntimeException(errorMessage, e);
    }
  }
  
  
  // Fallback implementation using circle layer for immediate functionality
  private void addTriangleLayerFallback(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    try {
      Log.d(TAG, "Adding triangle layer fallback (circle): " + layerName);
      
      // Use circle layer as simple fallback
      CircleLayer circleLayer = new CircleLayer(layerName, sourceName);
      
      // Convert triangle properties to circle properties where possible
      List<PropertyValue> circleProperties = new ArrayList<>();
      
      // Default circle properties - use more visible defaults
      circleProperties.add(PropertyFactory.circleRadius(10.0f));
      circleProperties.add(PropertyFactory.circleColor("#FF6B35")); // Orange color for visibility
      circleProperties.add(PropertyFactory.circleOpacity(0.8f));
      circleProperties.add(PropertyFactory.circleStrokeColor("#FFFFFF")); // White outline
      circleProperties.add(PropertyFactory.circleStrokeWidth(2.0f));
      circleProperties.add(PropertyFactory.circleStrokeOpacity(0.9f));
      
      if (properties != null) {
        for (PropertyValue<?> prop : properties) {
          if (prop != null) {
            try {
              switch (prop.name) {
                case "triangle-size":
                  if (prop.value instanceof Number) {
                    circleProperties.add(PropertyFactory.circleRadius(((Number) prop.value).floatValue()));
                  }
                  break;
                case "triangle-color":
                  if (prop.value instanceof String) {
                    circleProperties.add(PropertyFactory.circleColor((String) prop.value));
                  } else if (prop.value instanceof Integer) {
                    circleProperties.add(PropertyFactory.circleColor((Integer) prop.value));
                  }
                  break;
                case "triangle-opacity":
                  if (prop.value instanceof Number) {
                    circleProperties.add(PropertyFactory.circleOpacity(((Number) prop.value).floatValue()));
                  }
                  break;
                case "triangle-stroke-width":
                  if (prop.value instanceof Number) {
                    circleProperties.add(PropertyFactory.circleStrokeWidth(((Number) prop.value).floatValue()));
                  }
                  break;
                case "triangle-stroke-color":
                  if (prop.value instanceof String) {
                    circleProperties.add(PropertyFactory.circleStrokeColor((String) prop.value));
                  } else if (prop.value instanceof Integer) {
                    circleProperties.add(PropertyFactory.circleStrokeColor((Integer) prop.value));
                  }
                  break;
                case "triangle-stroke-opacity":
                  if (prop.value instanceof Number) {
                    circleProperties.add(PropertyFactory.circleStrokeOpacity(((Number) prop.value).floatValue()));
                  }
                  break;
                default:
                  Log.v(TAG, "Triangle property not mapped to circle: " + prop.name);
                  break;
              }
            } catch (Exception e) {
              Log.w(TAG, "Failed to map triangle property: " + prop.name + ", error: " + e.getMessage());
            }
          }
        }
      }
      
      // Set all properties on the layer
      circleLayer.setProperties(circleProperties.toArray(new PropertyValue[0]));
      
      if (sourceLayer != null) {
        circleLayer.setSourceLayer(sourceLayer);
      }
      if (minZoom != null) {
        circleLayer.setMinZoom(minZoom);
      }
      if (maxZoom != null) {
        circleLayer.setMaxZoom(maxZoom);
      }
      if (filter != null) {
        circleLayer.setFilter(filter);
      }
      
      // Add layer to style
      if (style != null) {
        if (belowLayerId != null) {
          style.addLayerBelow(circleLayer, belowLayerId);
        } else {
          style.addLayer(circleLayer);
        }
        
        Log.d(TAG, "Added triangle layer fallback (circle): " + layerName);
        
        if (enableInteraction) {
          interactiveFeatureLayerIds.add(layerName);
        }
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error adding triangle layer fallback: " + layerName, e);
    }
  }

  private Expression parseFilter(String filter) {
    JsonParser parser = new JsonParser();
    JsonElement filterJsonElement = parser.parse(filter);
    return filterJsonElement.isJsonNull() ? null : Expression.Converter.convert(filterJsonElement);
  }

  private void addRasterLayer(
      String layerName,
      String sourceName,
      Float minZoom,
      Float maxZoom,
      String belowLayerId,
      PropertyValue[] properties,
      Expression filter) {
    RasterLayer layer = new RasterLayer(layerName, sourceName);
    layer.setProperties(properties);
    if (minZoom != null) {
      layer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      layer.setMaxZoom(maxZoom);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(layer, belowLayerId);
    } else {
      style.addLayer(layer);
    }
  }

  private void addHillshadeLayer(
      String layerName,
      String sourceName,
      Float minZoom,
      Float maxZoom,
      String belowLayerId,
      PropertyValue[] properties,
      Expression filter) {
    HillshadeLayer layer = new HillshadeLayer(layerName, sourceName);
    layer.setProperties(properties);
    if (minZoom != null) {
      layer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      layer.setMaxZoom(maxZoom);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(layer, belowLayerId);
    } else {
      style.addLayer(layer);
    }
  }

  private void addHeatmapLayer(
      String layerName,
      String sourceName,
      Float minZoom,
      Float maxZoom,
      String belowLayerId,
      PropertyValue[] properties,
      Expression filter) {
    HeatmapLayer layer = new HeatmapLayer(layerName, sourceName);
    layer.setProperties(properties);
    if (minZoom != null) {
      layer.setMinZoom(minZoom);
    }
    if (maxZoom != null) {
      layer.setMaxZoom(maxZoom);
    }
    if (belowLayerId != null) {
      style.addLayerBelow(layer, belowLayerId);
    } else {
      style.addLayer(layer);
    }
  }

  private Pair<Feature, String> firstFeatureOnLayers(RectF in) {
    final List<Layer> layers = style.getLayers();
    Collections.reverse(layers);
    
    // First, check for triangle CustomLayers with manual hit-testing
    for (Layer layer : layers) {
      if (layer instanceof CustomLayer && interactiveFeatureLayerIds.contains(layer.getId())) {
        String layerId = layer.getId();
        if (layerId.startsWith("triangle-") || isTriangleLayer(layerId)) {
          // Perform manual hit-testing for triangle layer
          Feature hitFeature = performTriangleHitTest(layerId, in);
          if (hitFeature != null) {
            return new Pair<>(hitFeature, layerId);
          }
        }
      }
    }
    
    // Then check regular layers (symbols, etc.). Only layers explicitly
    // marked interactive should produce feature taps. Otherwise noninteractive
    // labels/counts can swallow the normal map click used by app-level
    // hit-testing.
    for (Layer layer : layers) {
      if (layer instanceof SymbolLayer && interactiveFeatureLayerIds.contains(layer.getId())) {
        final List<Feature> features =
            mapLibreMap.queryRenderedFeatures(in, layer.getId());
        if (!features.isEmpty()) {
          return new Pair<>(features.get(0), layer.getId());
        }
      }
    }
    return null;
  }


  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {

    switch (call.method) {
      case "map#waitForMap":
        if (mapLibreMap != null) {
          result.success(null);
          return;
        }
        mapReadyResult = result;
        break;
      case "map#update":
        {
          Convert.interpretMapLibreMapOptions(call.argument("options"), this, context);
          result.success(Convert.toJson(getCameraPosition()));
          break;
        }
      case "map#updateMyLocationTrackingMode":
        {
          int myLocationTrackingMode = call.argument("mode");
          setMyLocationTrackingMode(myLocationTrackingMode);
          result.success(null);
          break;
        }
      case "map#matchMapLanguageWithDeviceDefault":
        {
          try {
            final Locale deviceLocale = Locale.getDefault();
            MapLibreMapUtils.setMapLanguage(mapLibreMap, deviceLocale.getLanguage());

            result.success(null);
          } catch (RuntimeException exception) {
            Log.d(TAG, exception.toString());
            result.error("MAPBOX LOCALIZATION PLUGIN ERROR", exception.toString(), null);
          }
          break;
        }
      case "map#updateContentInsets":
        {
          HashMap<String, Object> insets = call.argument("bounds");
          final CameraUpdate cameraUpdate =
              CameraUpdateFactory.paddingTo(
                  Convert.toPixels(insets.get("left"), density),
                  Convert.toPixels(insets.get("top"), density),
                  Convert.toPixels(insets.get("right"), density),
                  Convert.toPixels(insets.get("bottom"), density));

          if (call.argument("animated")) {
            animateCamera(cameraUpdate, null, result);
          } else {
            moveCamera(cameraUpdate, result);
          }
          break;
        }
      case "map#setMapLanguage":
        {
          final String language = call.argument("language");
          try {
            MapLibreMapUtils.setMapLanguage(mapLibreMap, language);

            result.success(null);
          } catch (RuntimeException exception) {
            Log.d(TAG, exception.toString());
            result.error("MAPBOX LOCALIZATION PLUGIN ERROR", exception.toString(), null);
          }
          break;
        }
      case "map#getVisibleRegion":
        {
          Map<String, Object> reply = new HashMap<>();
          VisibleRegion visibleRegion = mapLibreMap.getProjection().getVisibleRegion();
          reply.put(
              "sw",
              Arrays.asList(
                  visibleRegion.latLngBounds.getLatSouth(), visibleRegion.latLngBounds.getLonWest()));
          reply.put(
              "ne",
              Arrays.asList(
                    visibleRegion.latLngBounds.getLatNorth(), visibleRegion.latLngBounds.getLonEast()));

          result.success(reply);
          break;
        }
      case "map#toScreenLocation":
        {
          Map<String, Object> reply = new HashMap<>();
          PointF pointf =
              mapLibreMap
                  .getProjection()
                  .toScreenLocation(
                      new LatLng(call.argument("latitude"), call.argument("longitude")));
          reply.put("x", pointf.x);
          reply.put("y", pointf.y);
          result.success(reply);
          break;
        }
      case "map#toScreenLocationBatch":
        {
          double[] param = (double[]) call.argument("coordinates");
          double[] reply = new double[param.length];

          for (int i = 0; i < param.length; i += 2) {
            PointF pointf =
                mapLibreMap.getProjection().toScreenLocation(new LatLng(param[i], param[i + 1]));
            reply[i] = pointf.x;
            reply[i + 1] = pointf.y;
          }

          result.success(reply);
          break;
        }
      case "map#toLatLng":
        {
          Map<String, Object> reply = new HashMap<>();
          LatLng latlng =
              mapLibreMap
                  .getProjection()
                  .fromScreenLocation(
                      new PointF(
                          ((Double) call.argument("x")).floatValue(),
                          ((Double) call.argument("y")).floatValue()));
          reply.put("latitude", latlng.getLatitude());
          reply.put("longitude", latlng.getLongitude());
          result.success(reply);
          break;
        }
      case "map#getMetersPerPixelAtLatitude":
        {
          Map<String, Object> reply = new HashMap<>();
          Double retVal =
              mapLibreMap
                  .getProjection()
                  .getMetersPerPixelAtLatitude((Double) call.argument("latitude"));
          reply.put("metersperpixel", retVal);
          result.success(reply);
          break;
        }
      case "camera#move":
        {
          final CameraUpdate cameraUpdate =
              Convert.toCameraUpdate(call.argument("cameraUpdate"), mapLibreMap, density);
          if (cameraUpdate != null) {
            // camera transformation not handled yet
            mapLibreMap.moveCamera(
                cameraUpdate,
                new OnCameraMoveFinishedListener() {
                  @Override
                  public void onFinish() {
                    super.onFinish();
                    result.success(true);
                  }

                  @Override
                  public void onCancel() {
                    super.onCancel();
                    result.success(false);
                  }
                });

            // moveCamera(cameraUpdate);
          } else {
            result.success(false);
          }
          break;
        }
      case "camera#animate":
        {
          final CameraUpdate cameraUpdate =
              Convert.toCameraUpdate(call.argument("cameraUpdate"), mapLibreMap, density);
          final Integer duration = call.argument("duration");

          final OnCameraMoveFinishedListener onCameraMoveFinishedListener =
              new OnCameraMoveFinishedListener() {
                @Override
                public void onFinish() {
                  super.onFinish();
                  result.success(true);
                }

                @Override
                public void onCancel() {
                  super.onCancel();
                  result.success(false);
                }
              };
          if (cameraUpdate != null && duration != null) {
            // camera transformation not handled yet
            mapLibreMap.animateCamera(cameraUpdate, duration, onCameraMoveFinishedListener);
          } else if (cameraUpdate != null) {
            // camera transformation not handled yet
            mapLibreMap.animateCamera(cameraUpdate, onCameraMoveFinishedListener);
          } else {
            result.success(false);
          }
          break;
        }
      case "map#queryRenderedFeatures":
        {
          Map<String, Object> reply = new HashMap<>();
          List<Feature> features;

          String[] layerIds = ((List<String>) call.argument("layerIds")).toArray(new String[0]);

          List<Object> filter = call.argument("filter");
          JsonElement jsonElement = filter == null ? null : new Gson().toJsonTree(filter);
          JsonArray jsonArray = null;
          if (jsonElement != null && jsonElement.isJsonArray()) {
            jsonArray = jsonElement.getAsJsonArray();
          }
          Expression filterExpression =
              jsonArray == null ? null : Expression.Converter.convert(jsonArray);
          if (call.hasArgument("x")) {
            Double x = call.argument("x");
            Double y = call.argument("y");
            PointF pixel = new PointF(x.floatValue(), y.floatValue());
            features = mapLibreMap.queryRenderedFeatures(pixel, filterExpression, layerIds);
          } else {
            Double left = call.argument("left");
            Double top = call.argument("top");
            Double right = call.argument("right");
            Double bottom = call.argument("bottom");
            RectF rectF =
                new RectF(
                    left.floatValue(), top.floatValue(), right.floatValue(), bottom.floatValue());
            features = mapLibreMap.queryRenderedFeatures(rectF, filterExpression, layerIds);
          }
          List<String> featuresJson = new ArrayList<>();
          for (Feature feature : features) {
            featuresJson.add(feature.toJson());
          }
          reply.put("features", featuresJson);
          result.success(reply);
          break;
        }
      case "map#setTelemetryEnabled":
        {
          result.success(null);
          break;
        }
      case "map#getTelemetryEnabled":
        {
          result.success(false);
          break;
        }
      case "map#invalidateAmbientCache":
        {
          OfflineManager fileSource = OfflineManager.Companion.getInstance(context);

          fileSource.invalidateAmbientCache(
              new OfflineManager.FileSourceCallback() {
                @Override
                public void onSuccess() {
                  result.success(null);
                }

                @Override
                public void onError(@NonNull String message) {
                  result.error("MAPBOX CACHE ERROR", message, null);
                }
              });
          break;
        }
      case "map#clearAmbientCache":
      {
        OfflineManager fileSource = OfflineManager.Companion.getInstance(context);

        fileSource.clearAmbientCache(
                new OfflineManager.FileSourceCallback() {
                  @Override
                  public void onSuccess() {
                    result.success(null);
                  }

                  @Override
                  public void onError(@NonNull String message) {
                    result.error("MAPBOX CACHE ERROR", message, null);
                  }
                });
        break;
      }
      case "source#addGeoJson":
        {
          final String sourceId = call.argument("sourceId");
          final String geojson = call.argument("geojson");
          addGeoJsonSource(sourceId, geojson);
          result.success(null);
          break;
        }
      case "source#setGeoJson":
        {
          final String sourceId = call.argument("sourceId");
          final String geojson = call.argument("geojson");
          setGeoJsonSource(sourceId, geojson);
          result.success(null);
          break;
        }
      case "source#setFeature":
        {
          final String sourceId = call.argument("sourceId");
          final String geojsonFeature = call.argument("geojsonFeature");
          setGeoJsonFeature(sourceId, geojsonFeature);
          result.success(null);
          break;
        }
      case "symbolLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final String sourceLayer = call.argument("sourceLayer");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final String filter = call.argument("filter");
          final boolean enableInteraction = call.argument("enableInteraction");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretSymbolLayerProperties(call.argument("properties"));

          Expression filterExpression = parseFilter(filter);

          addSymbolLayer(
              layerId,
              sourceId,
              belowLayerId,
              sourceLayer,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              properties,
              enableInteraction,
              filterExpression);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "lineLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final String sourceLayer = call.argument("sourceLayer");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final String filter = call.argument("filter");
          final boolean enableInteraction = call.argument("enableInteraction");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretLineLayerProperties(call.argument("properties"));

          Expression filterExpression = parseFilter(filter);

          addLineLayer(
              layerId,
              sourceId,
              belowLayerId,
              sourceLayer,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              properties,
              enableInteraction,
              filterExpression);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
        case "layer#setProperties": {
          final String layerId = call.argument("layerId");

          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }

          Layer layer = style.getLayer(layerId);

          if (layer != null) {
            final PropertyValue[] properties;

            if (layer instanceof LineLayer) {
              properties = LayerPropertyConverter
                  .interpretLineLayerProperties(call.argument("properties"));
            } else if (layer instanceof FillLayer) {
              properties = LayerPropertyConverter
                  .interpretFillLayerProperties(call.argument("properties"));
            } else if (layer instanceof CircleLayer) {
              properties = LayerPropertyConverter
                  .interpretCircleLayerProperties(call.argument("properties"));
            } else if (layer instanceof SymbolLayer) {
              properties = LayerPropertyConverter
                  .interpretSymbolLayerProperties(call.argument("properties"));
            } else if (layer instanceof RasterLayer) {
              properties = LayerPropertyConverter
                  .interpretRasterLayerProperties(call.argument("properties"));
            } else if (layer instanceof HillshadeLayer) {
              properties = LayerPropertyConverter
                  .interpretHillshadeLayerProperties(call.argument("properties"));
            } else {
              result.error("UNSUPPORTED_LAYER_TYPE", "Layer type not supported", null);
              return;
            }
            layer.setProperties(properties);
            result.success(null);
          } else {
            result.error("LAYER_NOT_FOUND_ERROR", "Layer " + layerId + "not found", null);
          }

          break;
        }
      case "fillLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final String sourceLayer = call.argument("sourceLayer");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final String filter = call.argument("filter");
          final boolean enableInteraction = call.argument("enableInteraction");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretFillLayerProperties(call.argument("properties"));

          Expression filterExpression = parseFilter(filter);

          addFillLayer(
              layerId,
              sourceId,
              belowLayerId,
              sourceLayer,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              properties,
              enableInteraction,
              filterExpression);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "fillExtrusionLayer#add":
      {
        final String sourceId = call.argument("sourceId");
        final String layerId = call.argument("layerId");
        final String belowLayerId = call.argument("belowLayerId");
        final String sourceLayer = call.argument("sourceLayer");
        final Double minzoom = call.argument("minzoom");
        final Double maxzoom = call.argument("maxzoom");
        final String filter = call.argument("filter");
        final boolean enableInteraction = call.argument("enableInteraction");
        final PropertyValue[] properties =
                LayerPropertyConverter.interpretFillExtrusionLayerProperties(
                        call.argument("properties"));

        Expression filterExpression = parseFilter(filter);

        addFillExtrusionLayer(
                layerId,
                sourceId,
                belowLayerId,
                sourceLayer,
                minzoom != null ? minzoom.floatValue() : null,
                maxzoom != null ? maxzoom.floatValue() : null,
                properties,
                enableInteraction,
                filterExpression);
        updateLocationComponentLayer();

        result.success(null);
        break;
      }
      case "circleLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final String sourceLayer = call.argument("sourceLayer");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final String filter = call.argument("filter");
          final boolean enableInteraction = call.argument("enableInteraction");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretCircleLayerProperties(call.argument("properties"));

          Expression filterExpression = parseFilter(filter);

          addCircleLayer(
              layerId,
              sourceId,
              belowLayerId,
              sourceLayer,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              properties,
              enableInteraction,
              filterExpression);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "triangleLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final String sourceLayer = call.argument("sourceLayer");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final String filter = call.argument("filter");
          final boolean enableInteraction = call.argument("enableInteraction");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretTriangleLayerProperties(call.argument("properties"));

          Expression filterExpression = parseFilter(filter);

          addTriangleLayer(
              layerId,
              sourceId,
              belowLayerId,
              sourceLayer,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              properties,
              enableInteraction,
              filterExpression);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "adsbArrowLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final String sourceLayer = call.argument("sourceLayer");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final String filter = call.argument("filter");
          final boolean enableInteraction = call.argument("enableInteraction");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretSymbolLayerProperties(call.argument("properties"));

          Expression filterExpression = parseFilter(filter);

          addADSBArrowLayer(
              layerId,
              sourceId,
              belowLayerId,
              sourceLayer,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              properties,
              enableInteraction,
              filterExpression);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "rotatableSymbolLayers#add":
        {
          final String sourceId = call.argument("sourceId");
          final String baseLayerId = call.argument("baseLayerId");
          final String belowLayerId = call.argument("belowLayerId");
          final boolean enableInteraction = call.argument("enableInteraction");
          final Map<String, Object> properties = call.argument("properties");

          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            break;
          }
          
          try {
            addRotatableSymbolLayers(
                sourceId,
                baseLayerId,
                belowLayerId,
                properties,
                enableInteraction);
            result.success(null);
          } catch (Exception e) {
            result.error(
                "ROTATABLE_SYMBOL_LAYER_ERROR",
                "Failed to add rotatable symbol layers: " + e.getMessage(),
                null);
          }
          break;
        }
      case "rotatableSymbolPngLayers#add":
        {
          final String sourceId = call.argument("sourceId");
          final String baseLayerId = call.argument("baseLayerId");
          final String belowLayerId = call.argument("belowLayerId");
          final boolean enableInteraction = call.argument("enableInteraction");
          final Map<String, Object> properties = call.argument("properties");

          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            break;
          }
          
          try {
            addRotatableSymbolPngLayers(
                sourceId,
                baseLayerId,
                belowLayerId,
                properties,
                enableInteraction);
            result.success(null);
          } catch (Exception e) {
            result.error(
                "ROTATABLE_SYMBOL_PNG_LAYER_ERROR",
                "Failed to add rotatable symbol PNG layers: " + e.getMessage(),
                null);
          }
          break;
        }
      case "rasterLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretRasterLayerProperties(call.argument("properties"));
          addRasterLayer(
              layerId,
              sourceId,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              belowLayerId,
              properties,
              null);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "hillshadeLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretHillshadeLayerProperties(call.argument("properties"));
          addHillshadeLayer(
              layerId,
              sourceId,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              belowLayerId,
              properties,
              null);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "heatmapLayer#add":
        {
          final String sourceId = call.argument("sourceId");
          final String layerId = call.argument("layerId");
          final String belowLayerId = call.argument("belowLayerId");
          final Double minzoom = call.argument("minzoom");
          final Double maxzoom = call.argument("maxzoom");
          final PropertyValue[] properties =
              LayerPropertyConverter.interpretHeatmapLayerProperties(call.argument("properties"));
          addHeatmapLayer(
              layerId,
              sourceId,
              minzoom != null ? minzoom.floatValue() : null,
              maxzoom != null ? maxzoom.floatValue() : null,
              belowLayerId,
              properties,
              null);
          updateLocationComponentLayer();

          result.success(null);
          break;
        }
      case "locationComponent#getLastLocation":
        {
          Log.e(TAG, "location component: getLastLocation");
          if (this.myLocationEnabled
              && locationComponent != null
              && locationComponent.isLocationComponentActivated()
              && locationComponent.getLocationEngine() != null) {
            Map<String, Object> reply = new HashMap<>();

            mapLibreMap.getLocationComponent().getLocationEngine().getLastLocation(
                new LocationEngineCallback<LocationEngineResult>() {
                  @Override
                  public void onSuccess(LocationEngineResult locationEngineResult) {
                    Location lastLocation = locationEngineResult.getLastLocation();
                    if (lastLocation != null) {
                      reply.put("latitude", lastLocation.getLatitude());
                      reply.put("longitude", lastLocation.getLongitude());
                      reply.put("altitude", lastLocation.getAltitude());
                      result.success(reply);
                    } else {
                      result.error("", "", null); // ???
                    }
                  }

                  @Override
                  public void onFailure(@NonNull Exception exception) {
                    result.error("", "", null); // ???
                  }
                });
          } else {
            result.error(
                "LOCATION DISABLED",
                "Location is disabled or location component is unavailable",
                null);
          }
          break;
        }
      case "style#addImage":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          Bitmap bitmap = BitmapFactory.decodeByteArray(
              call.argument("bytes"), 0, call.argument("length"));
          Double pixelRatio = call.argument("pixelRatio");
          if (pixelRatio != null && pixelRatio > 0) {
            bitmap.setDensity((int) Math.round(pixelRatio * DisplayMetrics.DENSITY_DEFAULT));
          }
          style.addImage(
              call.argument("name"),
              bitmap,
              call.argument("sdf"));
          result.success(null);
          break;
        }
      case "style#createPillLabel":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            break;
          }
          try {
            String imageName = call.argument("name");
            String labelText = call.argument("text");
            String backgroundColor = call.argument("backgroundColor"); // e.g., "#0066FF"
            String textColor = call.argument("textColor"); // e.g., "#FFFFFF"
            Double textSize = call.argument("textSize"); // e.g., 14.0
            Double paddingHorizontal = call.argument("paddingHorizontal"); // e.g., 12.0
            Double paddingVertical = call.argument("paddingVertical"); // e.g., 6.0
            Double cornerRadius = call.argument("cornerRadius"); // e.g., 8.0
            
            // Generate the pill/lozenge bitmap
            Bitmap pillBitmap = createPillLabelBitmap(
                labelText,
                backgroundColor != null ? backgroundColor : "#0066FF",
                textColor != null ? textColor : "#FFFFFF",
                textSize != null ? textSize.floatValue() : 14.0f,
                paddingHorizontal != null ? paddingHorizontal.floatValue() : 12.0f,
                paddingVertical != null ? paddingVertical.floatValue() : 6.0f,
                cornerRadius != null ? cornerRadius.floatValue() : 8.0f
            );
            
            // Add the bitmap to the map style
            // Note: Bitmap is density-scaled, so iconSize in Flutter should be adjusted (1.0/density)
            style.addImage(imageName, pillBitmap, false); // false = not SDF (signed distance field)
            
            // DEBUG: Log image addition
            android.util.Log.d("MapLibreMapController", "✅ Added image to style: " + imageName + " (" + pillBitmap.getWidth() + "x" + pillBitmap.getHeight() + " px)");
            
            result.success(null);
          } catch (Exception e) {
            result.error("CREATE_PILL_LABEL_ERROR", e.getMessage(), null);
          }
          break;
        }
      case "style#createCircleLabel":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            break;
          }
          try {
            String imageName = call.argument("name");
            String labelText = call.argument("text");
            Double radius = call.argument("radius"); // Circle radius in dp
            String circleColor = call.argument("circleColor"); // e.g., "#0066FF"
            Double circleStrokeWidth = call.argument("circleStrokeWidth"); // e.g., 2.0
            String textColor = call.argument("textColor"); // e.g., "#FFFFFF"
            Double textSize = call.argument("textSize"); // e.g., 14.0
            Boolean topArc = call.argument("topArc"); // true = text on top arc, false = bottom arc
            Boolean roundedEdges = call.argument("roundedEdges"); // true = rounded caps, false = straight edges
            
            // Generate the circular label bitmap
            Bitmap circleBitmap = createCircleLabelBitmap(
                labelText,
                radius != null ? radius.floatValue() : 30.0f,
                circleColor != null ? circleColor : "#0066FF",
                circleStrokeWidth != null ? circleStrokeWidth.floatValue() : 2.0f,
                textColor != null ? textColor : "#FFFFFF",
                textSize != null ? textSize.floatValue() : 14.0f,
                topArc != null ? topArc : true,
                roundedEdges != null ? roundedEdges : true
            );
            
            // Add the bitmap to the map style
            style.addImage(imageName, circleBitmap, false);
            
            // DEBUG: Log image addition
            android.util.Log.d("MapLibreMapController", "✅ Added circle label to style: " + imageName + " (" + circleBitmap.getWidth() + "x" + circleBitmap.getHeight() + " px)");
            
            result.success(null);
          } catch (Exception e) {
            result.error("CREATE_CIRCLE_LABEL_ERROR", e.getMessage(), null);
          }
          break;
        }
      case "style#addImageSource":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          List<LatLng> coordinates = Convert.toLatLngList(call.argument("coordinates"), false);
          style.addSource(
              new ImageSource(
                  call.argument("imageSourceId"),
                  new LatLngQuad(
                      coordinates.get(0),
                      coordinates.get(1),
                      coordinates.get(2),
                      coordinates.get(3)),
                  BitmapFactory.decodeByteArray(
                      call.argument("bytes"), 0, call.argument("length"))));
          result.success(null);
          break;
        }
        case "style#updateImageSource":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          ImageSource imageSource = style.getSourceAs(call.argument("imageSourceId"));
          List<LatLng> coordinates = Convert.toLatLngList(call.argument("coordinates"), false);
          if (coordinates != null) {
            imageSource.setCoordinates(
                new LatLngQuad(
                    coordinates.get(0),
                    coordinates.get(1),
                    coordinates.get(2),
                    coordinates.get(3)));
          }
          byte[] bytes = call.argument("bytes");
          if (bytes != null) {
            imageSource.setImage(BitmapFactory.decodeByteArray(bytes, 0, call.argument("length")));
          }
          result.success(null);
          break;
        }
      case "style#addSource":
        {
          final String id = Convert.toString(call.argument("sourceId"));
          final Map<String, Object> properties = (Map<String, Object>) call.argument("properties");
          SourcePropertyConverter.addSource(id, properties, style);
          result.success(null);
          break;
        }

      case "style#removeSource":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          style.removeSource((String) call.argument("sourceId"));
          result.success(null);
          break;
        }
      case "style#addLayer":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          addRasterLayer(
              call.argument("imageLayerId"),
              call.argument("imageSourceId"),
              call.argument("minzoom") != null
                  ? ((Double) call.argument("minzoom")).floatValue()
                  : null,
              call.argument("maxzoom") != null
                  ? ((Double) call.argument("maxzoom")).floatValue()
                  : null,
              null,
              new PropertyValue[] {},
              null);
          result.success(null);
          break;
        }
      case "style#addLayerBelow":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          addRasterLayer(
              call.argument("imageLayerId"),
              call.argument("imageSourceId"),
              call.argument("minzoom") != null
                  ? ((Double) call.argument("minzoom")).floatValue()
                  : null,
              call.argument("maxzoom") != null
                  ? ((Double) call.argument("maxzoom")).floatValue()
                  : null,
              call.argument("belowLayerId"),
              new PropertyValue[] {},
              null);
          result.success(null);
          break;
        }
      case "style#removeLayer":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          String layerId = call.argument("layerId");
          style.removeLayer(layerId);
          interactiveFeatureLayerIds.remove(layerId);

          result.success(null);
          break;
        }
      case "map#setCameraBounds":
        {
          double west = call.argument("west");
          double north = call.argument("north");
          double south = call.argument("south");
          double east = call.argument("east");

          int padding = call.argument("padding");

          LatLng locationOne = new LatLng(north, east);
          LatLng locationTwo = new LatLng(south, west);
          LatLngBounds latLngBounds = new LatLngBounds.Builder()
                  .include(locationOne) // Northeast
                  .include(locationTwo) // Southwest
                  .build();
          mapLibreMap.easeCamera(CameraUpdateFactory.newLatLngBounds(latLngBounds,
                  padding), 200);

          break;
        }
      case "style#setFilter":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          String layerId = call.argument("layerId");
          String filter = call.argument("filter");

          Layer layer = style.getLayer(layerId);

          JsonParser parser = new JsonParser();
          JsonElement jsonElement = parser.parse(filter);
          Expression expression = Expression.Converter.convert(jsonElement);

          if (layer instanceof CircleLayer) {
            ((CircleLayer) layer).setFilter(expression);
          } else if (layer instanceof FillExtrusionLayer) {
            ((FillExtrusionLayer) layer).setFilter(expression);
          } else if (layer instanceof FillLayer) {
            ((FillLayer) layer).setFilter(expression);
          } else if (layer instanceof HeatmapLayer) {
            ((HeatmapLayer) layer).setFilter(expression);
          } else if (layer instanceof LineLayer) {
            ((LineLayer) layer).setFilter(expression);
          } else if (layer instanceof SymbolLayer) {
            ((SymbolLayer) layer).setFilter(expression);
          } else {
            result.error(
                "INVALID LAYER TYPE",
                String.format("Layer '%s' does not support filtering.", layerId),
                null);
            break;
          }

          result.success(null);
          break;
        }
        case "style#getFilter":
        {
          if (style == null) {
            result.error(
                    "STYLE IS NULL",
                    "The style is null. Has onStyleLoaded() already been invoked?",
                    null);
            return;
          }
          Map<String, Object> reply = new HashMap<>();
          String layerId = call.argument("layerId");
          Layer layer = style.getLayer(layerId);

          Expression filter;
          if (layer instanceof CircleLayer) {
            filter = ((CircleLayer) layer).getFilter();
          } else if (layer instanceof FillExtrusionLayer) {
            filter = ((FillExtrusionLayer) layer).getFilter();
          } else if (layer instanceof FillLayer) {
            filter = ((FillLayer) layer).getFilter();
          } else if (layer instanceof HeatmapLayer) {
            filter = ((HeatmapLayer) layer).getFilter();
          } else if (layer instanceof LineLayer) {
            filter = ((LineLayer) layer).getFilter();
          } else if (layer instanceof SymbolLayer) {
            filter = ((SymbolLayer) layer).getFilter();
          } else {
            result.error(
                    "INVALID LAYER TYPE",
                    String.format("Layer '%s' does not support filtering.", layerId),
                    null);
            break;
          }

          reply.put("filter", filter.toString());
          result.success(reply);
          break;
        }
        case "layer#setVisibility":
        {

          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
            return;
          }
          String layerId = call.argument("layerId");
          boolean visible = call.argument("visible");

          Layer layer = style.getLayer(layerId);

          if (layer != null) {
            layer.setProperties(PropertyFactory.visibility(visible ? Property.VISIBLE : Property.NONE));
          }

          result.success(null);
          break;

        }
        case "map#querySourceFeatures":
        {
          Map<String, Object> reply = new HashMap<>();
          List<Feature> features;

          String sourceId = (String) call.argument("sourceId");

          String sourceLayerId = (String) call.argument("sourceLayerId");

          List<Object> filter = call.argument("filter");
          JsonElement jsonElement = filter == null ? null : new Gson().toJsonTree(filter);
          JsonArray jsonArray = null;
          if (jsonElement != null && jsonElement.isJsonArray()) {
            jsonArray = jsonElement.getAsJsonArray();
          }
          Expression filterExpression =
                  jsonArray == null ? null : Expression.Converter.convert(jsonArray);


          Source source = style.getSource(sourceId);
          if (source instanceof GeoJsonSource) {
            features = ((GeoJsonSource) source).querySourceFeatures(filterExpression);
          } else if (source instanceof CustomGeometrySource) {
            features = ((CustomGeometrySource) source).querySourceFeatures(filterExpression);
          } else if (source instanceof VectorSource && sourceLayerId != null) {
            features = ((VectorSource) source).querySourceFeatures(new String[] {sourceLayerId}, filterExpression);
          } else {
            features = Collections.emptyList();
          }

          List<String> featuresJson = new ArrayList<>();
          for (Feature feature : features) {
            featuresJson.add(feature.toJson());
          }
          reply.put("features", featuresJson);
          result.success(reply);
          break;
        }
        case "source#getGeoJsonClusterLeaves":
        {
          Map<String, Object> reply = new HashMap<>();
          String sourceId = (String) call.argument("sourceId");
          String clusterJson = (String) call.argument("cluster");
          Number limitNumber = (Number) call.argument("limit");
          Number offsetNumber = (Number) call.argument("offset");
          long limit = limitNumber == null ? Long.MAX_VALUE : limitNumber.longValue();
          long offset = offsetNumber == null ? 0L : offsetNumber.longValue();

          Source source = style.getSource(sourceId);
          if (!(source instanceof GeoJsonSource) || clusterJson == null) {
            reply.put("features", Collections.emptyList());
            result.success(reply);
            break;
          }

          Feature cluster = Feature.fromJson(clusterJson);
          FeatureCollection leaves =
              ((GeoJsonSource) source).getClusterLeaves(cluster, limit, offset);
          List<String> featuresJson = new ArrayList<>();
          if (leaves.features() != null) {
            for (Feature feature : leaves.features()) {
              featuresJson.add(feature.toJson());
            }
          }
          reply.put("features", featuresJson);
          result.success(reply);
          break;
        }
        case "style#getLayerIds":
        {
          if (style == null) {
            result.error(
                    "STYLE IS NULL",
                    "The style is null. Has onStyleLoaded() already been invoked?",
                    null);
            return;
          }
          Map<String, Object> reply = new HashMap<>();

          List<String> layerIds = new ArrayList<>();
          for (Layer layer : style.getLayers()) {
            layerIds.add(layer.getId());
          }

          reply.put("layers", layerIds);
          result.success(reply);
          break;
        }
      case "style#getSourceIds":
      {
        if (style == null) {
          result.error(
                  "STYLE IS NULL",
                  "The style is null. Has onStyleLoaded() already been invoked?",
                  null);
          return;
        }
        Map<String, Object> reply = new HashMap<>();

        List<String> sourceIds = new ArrayList<>();
        for (Source source : style.getSources()) {
          sourceIds.add(source.getId());
        }

        reply.put("sources", sourceIds);
        result.success(reply);
        break;
      }
      case "imageOverlay#addControls":
        {
          final String overlayId = call.argument("overlayId");
          final List<LatLng> coordinates = Convert.toLatLngList(call.argument("coordinates"), true);
          final boolean editMode = call.argument("editMode");
          addImageOverlayControls(overlayId, coordinates, editMode, result);
          break;
        }
      case "imageOverlay#updateControls":
        {
          final String overlayId = call.argument("overlayId");
          final List<LatLng> coordinates = Convert.toLatLngList(call.argument("coordinates"), true);
          final boolean editMode = call.argument("editMode");
          updateImageOverlayControls(overlayId, coordinates, editMode, result);
          break;
        }
      case "imageOverlay#removeControls":
        {
          final String overlayId = call.argument("overlayId");
          removeImageOverlayControls(overlayId, result);
          break;
        }
      case "imageOverlay#handleGesture":
        {
          final String overlayId = call.argument("overlayId");
          final String gestureType = call.argument("gestureType");
          final double screenX = call.argument("screenX");
          final double screenY = call.argument("screenY");
          final double deltaX = call.argument("deltaX");
          final double deltaY = call.argument("deltaY");
          handleImageOverlayGesture(overlayId, gestureType, screenX, screenY, deltaX, deltaY, result);
          break;
        }
      case "imageOverlay#setSensitivity":
        {
          final String overlayId = call.argument("overlayId");
          final double sensitivity = call.argument("sensitivity");
          setImageOverlayControlsSensitivity(overlayId, sensitivity, result);
          break;
        }
      case "map#enableNativeMeasurement":
        {
          Boolean enabled = call.argument("enabled");
          if (enabled != null) {
            enableNativeMeasurement(enabled);
          }
          result.success(null);
          break;
        }
      case "map#setNativeMeasurementStyle":
        {
          setNativeMeasurementStyle(call.arguments());
          result.success(null);
          break;
        }
      case "map#clearNativeMeasurement":
        {
          clearNativeMeasurement();
          result.success(null);
          break;
        }
      case "map#ensureMeasurementLayersOnTop":
        {
          ensureMeasurementLayersOnTop();
          result.success(null);
          break;
        }
      case "line#enableEditing":
        {
          try {
            String lineId = call.argument("lineId");
            Boolean enabled = call.argument("enabled");
            List<Object> coordinatesList = call.argument("coordinates");
            List<Number> lockedPointIndicesList =
                call.argument("lockedPointIndices");
            
            if (lineId != null && enabled != null && polylineEditingManager != null) {
              polylineEditingManager.enableLineEditing(lineId, enabled);
              
              // If enabling and coordinates are provided, store them for the break point system
              if (enabled && coordinatesList != null && polylineBreakPointSystem != null) {
                List<LatLng> coordinates = new ArrayList<>();
                for (Object coordObj : coordinatesList) {
                  if (coordObj instanceof List) {
                    List<Object> coord = (List<Object>) coordObj;
                    if (coord.size() >= 2) {
                      double lat = ((Number) coord.get(0)).doubleValue();
                      double lng = ((Number) coord.get(1)).doubleValue();
                      coordinates.add(new LatLng(lat, lng));
                    }
                  }
                }
                
                if (!coordinates.isEmpty()) {
                  polylineBreakPointSystem.setPolylineCoordinates(lineId, coordinates);
                  List<Integer> lockedPointIndices = new ArrayList<>();
                  if (lockedPointIndicesList != null) {
                    for (Number index : lockedPointIndicesList) {
                      lockedPointIndices.add(index.intValue());
                    }
                  }
                  polylineBreakPointSystem.setLockedPointIndices(
                      lineId, lockedPointIndices);
                  if (polylineRenderer != null) {
                    polylineRenderer.syncBreakPoints(
                        lineId,
                        coordinates,
                        polylineBreakPointSystem.getLockedPointIndices(lineId));
                  }
                  Log.d(TAG, "Stored coordinates for editable polyline " + lineId + ": " + coordinates.size() + " points");
                }
              } else if (!enabled && polylineBreakPointSystem != null) {
                // If disabling, remove stored coordinates
                polylineBreakPointSystem.removePolylineCoordinates(lineId);
                Log.d(TAG, "Removed stored coordinates for polyline " + lineId);
              }
              
              result.success(null);
            } else {
              result.error("INVALID_ARGUMENTS", "lineId and enabled are required", null);
            }
          } catch (Exception e) {
            Log.e(TAG, "Error in line#enableEditing: " + e.getMessage(), e);
            result.error("NATIVE_ERROR", "Failed to enable/disable line editing: " + e.getMessage(), null);
          }
          break;
        }
      case "line#setEditingStyle":
        {
          try {
            Map<String, Object> style = call.arguments();
            if (style != null && polylineEditingManager != null) {
              polylineEditingManager.setEditingStyle(style);
              
              // Also update the renderer styling
              if (polylineRenderer != null) {
                polylineRenderer.updateStyle(style);
              }
              if (polylineGestureDetector != null) {
                Object tolerance = style.get("hitTestTolerance");
                if (tolerance instanceof Number) {
                  float density = context.getResources().getDisplayMetrics().density;
                  polylineGestureDetector.setHitTestRadiusPx(
                      ((Number) tolerance).floatValue() * density);
                }
              }
              
              result.success(null);
            } else {
              result.error("INVALID_ARGUMENTS", "style is required", null);
            }
          } catch (Exception e) {
            Log.e(TAG, "Error in line#setEditingStyle: " + e.getMessage(), e);
            result.error("NATIVE_ERROR", "Failed to set editing style: " + e.getMessage(), null);
          }
          break;
        }
      case "line#isEditable":
        {
          try {
            String lineId = call.argument("lineId");
            if (lineId != null && polylineEditingManager != null) {
              boolean isEditable = polylineEditingManager.isLineEditable(lineId);
              result.success(isEditable);
            } else {
              result.error("INVALID_ARGUMENTS", "lineId is required", null);
            }
          } catch (Exception e) {
            Log.e(TAG, "Error in line#isEditable: " + e.getMessage(), e);
            result.error("NATIVE_ERROR", "Failed to check if line is editable: " + e.getMessage(), null);
          }
          break;
        }
      case "map#addRotatableSymbolPngLayers":
        {
          try {
            final String sourceId = call.argument("sourceId");
            final String baseLayerId = call.argument("baseLayerId");
            final String belowLayerId = call.argument("belowLayerId");
            final String aircraftIconPath = call.argument("aircraftIconPath");
            final String arrowIconPath = call.argument("arrowIconPath");
            final Object aircraftIconSizeObj = call.argument("aircraftIconSize");
            final Object arrowIconSizeObj = call.argument("arrowIconSize");
            final boolean enableInteraction = call.argument("enableInteraction");
            final Map<String, Object> config = call.argument("config");
            
            // Convert size parameters
            double aircraftIconSize = aircraftIconSizeObj instanceof Number ? ((Number) aircraftIconSizeObj).doubleValue() : 0.8;
            double arrowIconSize = arrowIconSizeObj instanceof Number ? ((Number) arrowIconSizeObj).doubleValue() : 0.5;
            
            addRotatableSymbolPngLayers(sourceId, baseLayerId, belowLayerId, aircraftIconPath, arrowIconPath, aircraftIconSize, arrowIconSize, enableInteraction, config);
            result.success(null);
          } catch (Exception e) {
            Log.e(TAG, "Error in addRotatableSymbolPngLayers: " + e.getMessage(), e);
            result.error("NATIVE_ERROR", "Failed to add rotatable symbol PNG layers: " + e.getMessage(), null);
          }
          break;
        }
      default:
        result.notImplemented();
    }
  }

  @Override
  public void onCameraMoveStarted(int reason) {
    final Map<String, Object> arguments = new HashMap<>(2);
    boolean isGesture = reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE;
    arguments.put("isGesture", isGesture);
    methodChannel.invokeMethod("camera#onMoveStarted", arguments);
  }

  private void emitMapTouchState(MotionEvent event) {
    final int actionMasked = event.getActionMasked();
    if (actionMasked != MotionEvent.ACTION_DOWN
        && actionMasked != MotionEvent.ACTION_POINTER_DOWN
        && actionMasked != MotionEvent.ACTION_UP
        && actionMasked != MotionEvent.ACTION_POINTER_UP
        && actionMasked != MotionEvent.ACTION_CANCEL) {
      return;
    }

    final int pointerIndex = event.getActionIndex();
    final Map<String, Object> arguments = new HashMap<>(6);
    arguments.put("action", mapTouchActionName(actionMasked));
    arguments.put("pointerCount", event.getPointerCount());
    arguments.put("pointerIndex", pointerIndex);
    arguments.put("x", event.getX(pointerIndex));
    arguments.put("y", event.getY(pointerIndex));
    arguments.put("actionMasked", actionMasked);
    methodChannel.invokeMethod("map#onTouchState", arguments);
  }

  private String mapTouchActionName(int actionMasked) {
    switch (actionMasked) {
      case MotionEvent.ACTION_DOWN:
        return "down";
      case MotionEvent.ACTION_POINTER_DOWN:
        return "pointer_down";
      case MotionEvent.ACTION_UP:
        return "up";
      case MotionEvent.ACTION_POINTER_UP:
        return "pointer_up";
      case MotionEvent.ACTION_CANCEL:
        return "cancel";
      default:
        return "other";
    }
  }

  @Override
  public void onCameraMove() {
    if (!trackCameraPosition) {
      return;
    }
    final Map<String, Object> arguments = new HashMap<>(2);
    arguments.put("position", Convert.toJson(mapLibreMap.getCameraPosition()));
    methodChannel.invokeMethod("camera#onMove", arguments);
  }

  @Override
  public void onCameraIdle() {
    final Map<String, Object> arguments = new HashMap<>(2);
    if (trackCameraPosition) {
      arguments.put("position", Convert.toJson(mapLibreMap.getCameraPosition()));
    }
    methodChannel.invokeMethod("camera#onIdle", arguments);
    

  }

  @Override
  public void onCameraTrackingChanged(int currentMode) {
    final Map<String, Object> arguments = new HashMap<>(2);
    switch (currentMode) {
        case CameraMode.NONE:
            arguments.put("mode", 0);
            break;
        case CameraMode.TRACKING:
            arguments.put("mode", 1);
            break;
        case CameraMode.TRACKING_COMPASS:
            arguments.put("mode", 2);
            break;
        case CameraMode.TRACKING_GPS:
            arguments.put("mode", 3);
            break;
        default:
            Log.e(TAG, "Unable to map " + currentMode + " to a tracking mode");
            return;
    }

    methodChannel.invokeMethod("map#onCameraTrackingChanged", arguments);
  }

  @Override
  public void onCameraTrackingDismissed() {
    this.myLocationTrackingMode = 0;
    methodChannel.invokeMethod("map#onCameraTrackingDismissed", new HashMap<>());
  }

  @Override
  public void onDidBecomeIdle() {
    methodChannel.invokeMethod("map#onIdle", new HashMap<>());
  }

  @Override
  public boolean onMapClick(@NonNull LatLng point) {
    PointF pointf = mapLibreMap.getProjection().toScreenLocation(point);
    RectF rectF = new RectF(pointf.x - 10, pointf.y - 10, pointf.x + 10, pointf.y + 10);
    Pair<Feature, String> featureLayerPair = firstFeatureOnLayers(rectF);
    final Map<String, Object> arguments = new HashMap<>();
    arguments.put("x", pointf.x);
    arguments.put("y", pointf.y);
    arguments.put("lng", point.getLongitude());
    arguments.put("lat", point.getLatitude());
    if (featureLayerPair != null && featureLayerPair.first != null) {
      arguments.put("layerId", featureLayerPair.second);
      arguments.put("id", featureLayerPair.first.id());
      methodChannel.invokeMethod("feature#onTap", arguments);
      if (featureTapsTriggersMapClick) {
        methodChannel.invokeMethod("map#onMapClick", arguments);
      }
    } else {
      methodChannel.invokeMethod("map#onMapClick", arguments);
    }
    return true;
  }

  @Override
  public boolean onMapLongClick(@NonNull LatLng point) {
    if (nativeMeasurementDetector != null
        && nativeMeasurementDetector.shouldSuppressMapGestureCallbacks()) {
      Log.d(TAG, "Suppressed map long click during native measurement interaction");
      return true;
    }

    PointF pointf = mapLibreMap.getProjection().toScreenLocation(point);
    final Map<String, Object> arguments = new HashMap<>(5);
    arguments.put("x", pointf.x);
    arguments.put("y", pointf.y);
    arguments.put("lng", point.getLongitude());
    arguments.put("lat", point.getLatitude());
    methodChannel.invokeMethod("map#onMapLongClick", arguments);
    return true;
  }

  @Override
  public void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;

    if (nativeMeasurementDetector != null) {
      nativeMeasurementDetector.cleanup();
      nativeMeasurementDetector = null;
    }
    setPolylineDeleteZoneVisible(false, false);

    methodChannel.setMethodCallHandler(null);
    destroyMapViewIfNecessary();
    Lifecycle lifecycle = lifecycleProvider.getLifecycle();
    if (lifecycle != null) {
      lifecycle.removeObserver(this);
    }
  }

  private void moveCamera(CameraUpdate cameraUpdate, MethodChannel.Result result) {
    if (cameraUpdate != null) {
      // camera transformation not handled yet
      mapLibreMap.moveCamera(
          cameraUpdate,
          new OnCameraMoveFinishedListener() {
            @Override
            public void onFinish() {
              super.onFinish();
              result.success(true);
            }

            @Override
            public void onCancel() {
              super.onCancel();
              result.success(false);
            }
          });

      // moveCamera(cameraUpdate);
    } else {
      result.success(false);
    }
  }

  private void animateCamera(
      CameraUpdate cameraUpdate, Integer duration, MethodChannel.Result result) {
    final OnCameraMoveFinishedListener onCameraMoveFinishedListener =
        new OnCameraMoveFinishedListener() {
          @Override
          public void onFinish() {
            super.onFinish();
            result.success(true);
          }

          @Override
          public void onCancel() {
            super.onCancel();
            result.success(false);
          }
        };
    if (cameraUpdate != null && duration != null) {
      // camera transformation not handled yet
      mapLibreMap.animateCamera(cameraUpdate, duration, onCameraMoveFinishedListener);
    } else if (cameraUpdate != null) {
      // camera transformation not handled yet
      mapLibreMap.animateCamera(cameraUpdate, onCameraMoveFinishedListener);
    } else {
      result.success(false);
    }
  }

  /**
   * Destroy the MapView and cleans up listeners.
   * It's very important to call mapViewContainer.removeView(mapView) to make sure
   * that {@link TextureView#onDetachedFromWindowInternal()} is called which releases the
   * underlying surface.
   * This is required due to an FlutterEngine change that was introduce when updating from
   * Flutter 2.10.5 to Flutter 3.10.0.
   * This FlutterEngine change is not calling `removeView` on a PlatformView which causes the issue.
   * <p>
   * For more information check out:
   * <a href="https://github.com/flutter/flutter/issues/107297">Flutter issue</a>
   * <a href="https://github.com/flutter/engine/commit/8dc7cd1b1a33b5da561ac859cdcc49705ad1e598">Flutter Engine commit that introduced the issue</a>
   * <a href="https://github.com/maplibre/flutter-maplibre-gl/issues/182">The reported issue in the MapLibre repo</a>
   */
  private void destroyMapViewIfNecessary() {
    if (mapView == null) {
      return;
    }

    if (locationComponent != null) {
      locationComponent.setLocationComponentEnabled(false);
    }
    stopListeningForLocationUpdates();

    mapViewContainer.removeView(mapView);

    mapView.onStop();
    mapView.onDestroy();

    mapView = null;
  }

  @Override
  public void onCreate(@NonNull LifecycleOwner owner) {
    if (disposed) {
      return;
    }
    mapView.onCreate(null);
  }

  @Override
  public void onStart(@NonNull LifecycleOwner owner) {
    if (disposed) {
      return;
    }
    mapView.onStart();
  }

  @Override
  public void onResume(@NonNull LifecycleOwner owner) {
    if (disposed) {
      return;
    }
    mapView.onResume();
    if (myLocationEnabled) {
      startListeningForLocationUpdates();
    }
  }

  @Override
  public void onPause(@NonNull LifecycleOwner owner) {
    if (disposed) {
      return;
    }
    mapView.onPause();
  }

  @Override
  public void onStop(@NonNull LifecycleOwner owner) {
    if (disposed) {
      return;
    }
    mapView.onStop();
  }

  @Override
  public void onDestroy(@NonNull LifecycleOwner owner) {
    owner.getLifecycle().removeObserver(this);
    if (disposed) {
      return;
    }
    destroyMapViewIfNecessary();
  }

  // MapLibreMapOptionsSink methods

  @Override
  public void setCameraTargetBounds(LatLngBounds bounds) {
    this.bounds = bounds;
  }

  @Override
  public void setLocationEngineProperties(LocationEngineRequest locationEngineRequest){
    if(locationComponent != null){
        if(locationEngineRequest.getPriority() == LocationEngineRequest.PRIORITY_HIGH_ACCURACY){
            locationComponent.setLocationEngine(new LocationEngineProxy(
                new MapLibreGPSLocationEngine(context)));
     } else {
       locationComponent.setLocationEngine(
               LocationEngineDefault.INSTANCE.getDefaultLocationEngine(context));
            }
      locationComponent.setLocationEngineRequest(locationEngineRequest);
    }
  }

  @Override
  public void setCompassEnabled(boolean compassEnabled) {
    mapLibreMap.getUiSettings().setCompassEnabled(compassEnabled);
  }

  @Override
  public void setTrackCameraPosition(boolean trackCameraPosition) {
    this.trackCameraPosition = trackCameraPosition;
  }

  @Override
  public void setRotateGesturesEnabled(boolean rotateGesturesEnabled) {
    mapLibreMap.getUiSettings().setRotateGesturesEnabled(rotateGesturesEnabled);
  }

  @Override
  public void setScrollGesturesEnabled(boolean scrollGesturesEnabled) {
    mapLibreMap.getUiSettings().setScrollGesturesEnabled(scrollGesturesEnabled);
  }

  @Override
  public void setTiltGesturesEnabled(boolean tiltGesturesEnabled) {
    mapLibreMap.getUiSettings().setTiltGesturesEnabled(tiltGesturesEnabled);
  }

  @Override
  public void setTextureMode(boolean textureMode) {
    // Texture mode can only be set during map creation; runtime updates are ignored.
  }

  @Override
  public void setUseHybridComposition(boolean useHybridComposition) {
    // Hybrid composition is selected before the native map view is constructed.
  }

  @Override
  public void setFeatureTapsTriggersMapClick(boolean triggers) {
    this.featureTapsTriggersMapClick = triggers;
  }

  @Override
  public void setMinMaxZoomPreference(Float min, Float max) {
    mapLibreMap.setMinZoomPreference(min != null ? min : MapLibreConstants.MINIMUM_ZOOM);
    mapLibreMap.setMaxZoomPreference(max != null ? max : MapLibreConstants.MAXIMUM_ZOOM);
  }

  @Override
  public void setZoomGesturesEnabled(boolean zoomGesturesEnabled) {
    mapLibreMap.getUiSettings().setZoomGesturesEnabled(zoomGesturesEnabled);
  }

  @Override
  public void setMyLocationEnabled(boolean myLocationEnabled) {
    if (this.myLocationEnabled == myLocationEnabled) {
      return;
    }
    this.myLocationEnabled = myLocationEnabled;
    if (mapLibreMap != null) {
      updateMyLocationEnabled();
    }
  }

  @Override
  public void setMyLocationTrackingMode(int myLocationTrackingMode) {
    if (mapLibreMap != null) {
      // ensure that location is trackable
      updateMyLocationEnabled();
    }
    if (this.myLocationTrackingMode == myLocationTrackingMode) {
      return;
    }
    this.myLocationTrackingMode = myLocationTrackingMode;
    if (mapLibreMap != null && locationComponent != null) {
      updateMyLocationTrackingMode();
    }
  }

  @Override
  public void setMyLocationRenderMode(int myLocationRenderMode) {
    if (this.myLocationRenderMode == myLocationRenderMode) {
      return;
    }
    this.myLocationRenderMode = myLocationRenderMode;
    if (mapLibreMap != null && locationComponent != null) {
      updateMyLocationRenderMode();
    }
  }

  @Override
  public void setLogoEnabled(boolean logoEnabled) {
    mapLibreMap.getUiSettings().setLogoEnabled(logoEnabled);
  }

  @Override
  public void setLogoViewGravity(int gravity) {
    switch (gravity) {
      case 0:
        mapLibreMap.getUiSettings().setLogoGravity(Gravity.TOP | Gravity.START);
        break;
      case 1:
        mapLibreMap.getUiSettings().setLogoGravity(Gravity.TOP | Gravity.END);
        break;
      default:
      case 2:
        mapLibreMap.getUiSettings().setLogoGravity(Gravity.BOTTOM | Gravity.START);
        break;
      case 3:
        mapLibreMap.getUiSettings().setLogoGravity(Gravity.BOTTOM | Gravity.END);
        break;
    }
  }

  public void setLogoViewMargins(int x, int y) {
    mapLibreMap.getUiSettings().setLogoMargins(x, 0, 0, y);
  }

  @Override
  public void setCompassGravity(int gravity) {
    switch (gravity) {
      case 0:
        mapLibreMap.getUiSettings().setCompassGravity(Gravity.TOP | Gravity.START);
        break;
      default:
      case 1:
        mapLibreMap.getUiSettings().setCompassGravity(Gravity.TOP | Gravity.END);
        break;
      case 2:
        mapLibreMap.getUiSettings().setCompassGravity(Gravity.BOTTOM | Gravity.START);
        break;
      case 3:
        mapLibreMap.getUiSettings().setCompassGravity(Gravity.BOTTOM | Gravity.END);
        break;
    }
  }

  @Override
  public void setCompassViewMargins(int x, int y) {
    switch (mapLibreMap.getUiSettings().getCompassGravity()) {
      case Gravity.TOP | Gravity.START:
        mapLibreMap.getUiSettings().setCompassMargins(x, y, 0, 0);
        break;
      default:
      case Gravity.TOP | Gravity.END:
        mapLibreMap.getUiSettings().setCompassMargins(0, y, x, 0);
        break;
      case Gravity.BOTTOM | Gravity.START:
        mapLibreMap.getUiSettings().setCompassMargins(x, 0, 0, y);
        break;
      case Gravity.BOTTOM | Gravity.END:
        mapLibreMap.getUiSettings().setCompassMargins(0, 0, x, y);
        break;
    }
  }

  @Override
  public void setAttributionButtonGravity(int gravity) {
    switch (gravity) {
      case 0:
        mapLibreMap.getUiSettings().setAttributionGravity(Gravity.TOP | Gravity.START);
        break;
      default:
      case 1:
        mapLibreMap.getUiSettings().setAttributionGravity(Gravity.TOP | Gravity.END);
        break;
      case 2:
        mapLibreMap.getUiSettings().setAttributionGravity(Gravity.BOTTOM | Gravity.START);
        break;
      case 3:
        mapLibreMap.getUiSettings().setAttributionGravity(Gravity.BOTTOM | Gravity.END);
        break;
    }
  }

  @Override
  public void setAttributionButtonMargins(int x, int y) {
    switch (mapLibreMap.getUiSettings().getAttributionGravity()) {
      case Gravity.TOP | Gravity.START:
        mapLibreMap.getUiSettings().setAttributionMargins(x, y, 0, 0);
        break;
      default:
      case Gravity.TOP | Gravity.END:
        mapLibreMap.getUiSettings().setAttributionMargins(0, y, x, 0);
        break;
      case Gravity.BOTTOM | Gravity.START:
        mapLibreMap.getUiSettings().setAttributionMargins(x, 0, 0, y);
        break;
      case Gravity.BOTTOM | Gravity.END:
        mapLibreMap.getUiSettings().setAttributionMargins(0, 0, x, y);
        break;
    }
  }

  @Override
  public void setForegroundLoadColor(int loadColor) {
    // Foreground load color is only used during native map creation.
  }

  @Override
  public void setTranslucentTextureSurface(boolean translucentTextureSurface) {
    // The texture surface is fixed once the native map view has been created.
  }

  private void updateMyLocationEnabled() {
    if (this.locationComponent == null && mapLibreMap.getStyle() != null && myLocationEnabled) {
      enableLocationComponent(mapLibreMap.getStyle());
    }

    if (myLocationEnabled) {
      startListeningForLocationUpdates();
    } else {
      stopListeningForLocationUpdates();
    }

    if (locationComponent != null) {
      locationComponent.setLocationComponentEnabled(myLocationEnabled);
    }
  }

  private void startListeningForLocationUpdates() {
    if (locationEngineCallback == null
        && locationComponent != null
        && locationComponent.isLocationComponentActivated()
        && locationComponent.getLocationEngine() != null) {
      locationEngineCallback =
          new LocationEngineCallback<LocationEngineResult>() {
            @Override
            public void onSuccess(LocationEngineResult result) {
              onUserLocationUpdate(result.getLastLocation());
            }

            @Override
            public void onFailure(@NonNull Exception exception) {}
          };
      locationComponent
          .getLocationEngine()
          .requestLocationUpdates(
              locationComponent.getLocationEngineRequest(), locationEngineCallback, null);
    }
  }

  private void stopListeningForLocationUpdates() {
    if (locationEngineCallback != null
        && locationComponent != null
        && locationComponent.isLocationComponentActivated()
        && locationComponent.getLocationEngine() != null) {
      locationComponent.getLocationEngine().removeLocationUpdates(locationEngineCallback);
      locationEngineCallback = null;
    }
  }

  private void updateMyLocationTrackingMode() {
    int[] mapboxTrackingModes =
        new int[] {
          CameraMode.NONE, CameraMode.TRACKING, CameraMode.TRACKING_COMPASS, CameraMode.TRACKING_GPS
        };
    locationComponent.setCameraMode(mapboxTrackingModes[this.myLocationTrackingMode]);
  }

  private void updateMyLocationRenderMode() {
    int[] mapboxRenderModes = new int[] {RenderMode.NORMAL, RenderMode.COMPASS, RenderMode.GPS};
    locationComponent.setRenderMode(mapboxRenderModes[this.myLocationRenderMode]);
  }

  private boolean hasLocationPermission() {
    return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
            == PackageManager.PERMISSION_GRANTED
        || checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
            == PackageManager.PERMISSION_GRANTED;
  }

  private int checkSelfPermission(String permission) {
    if (permission == null) {
      throw new IllegalArgumentException("permission is null");
    }
    return context.checkPermission(
        permission, android.os.Process.myPid(), android.os.Process.myUid());
  }

  /**
   * Load asset directly using multiple strategies to ensure compatibility
   */
  private Bitmap loadAssetDirectly(String assetPath) {
    Log.d(TAG, "loadAssetDirectly called for: " + assetPath);
    
    // Strategy 1: Try Flutter asset resolution
    if (MapLibreMapsPlugin.flutterAssets != null) {
      try {
        String flutterAssetPath = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(assetPath);
        Log.d(TAG, "Flutter resolved path: " + flutterAssetPath);
        InputStream inputStream = mapView.getContext().getAssets().open(flutterAssetPath);
        Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
        inputStream.close();
        if (bitmap != null) {
          Log.d(TAG, "Successfully loaded via Flutter asset resolution: " + flutterAssetPath);
          return bitmap;
        }
      } catch (Exception e) {
        Log.d(TAG, "Flutter asset resolution failed: " + e.getMessage());
      }
    }
    
    // Strategy 2: Try looking in flutter_assets directory explicitly
    try {
      String flutterAssetPath = "flutter_assets/" + assetPath;
      Log.d(TAG, "Trying flutter_assets path: " + flutterAssetPath);
      InputStream inputStream = mapView.getContext().getAssets().open(flutterAssetPath);
      Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
      inputStream.close();
      if (bitmap != null) {
        Log.d(TAG, "Successfully loaded via flutter_assets path: " + flutterAssetPath);
        return bitmap;
      }
    } catch (Exception e) {
      Log.d(TAG, "Flutter_assets path loading failed: " + e.getMessage());
    }
    
    // Strategy 3: Try direct asset path
    try {
      InputStream inputStream = mapView.getContext().getAssets().open(assetPath);
      Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
      inputStream.close();
      if (bitmap != null) {
        Log.d(TAG, "Successfully loaded via direct path: " + assetPath);
        return bitmap;
      }
    } catch (Exception e) {
      Log.d(TAG, "Direct asset loading failed: " + e.getMessage());
    }
    
    // Strategy 4: Try with assets/ prefix
    try {
      String prefixedPath = "assets/" + assetPath;
      InputStream inputStream = mapView.getContext().getAssets().open(prefixedPath);
      Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
      inputStream.close();
      if (bitmap != null) {
        Log.d(TAG, "Successfully loaded via prefixed path: " + prefixedPath);
        return bitmap;
      }
    } catch (Exception e) {
      Log.d(TAG, "Prefixed asset loading failed: " + e.getMessage());
    }
    
    // Strategy 5: List flutter_assets directory and search for the file
    try {
      String[] flutterAssets = mapView.getContext().getAssets().list("flutter_assets");
      Log.d(TAG, "Flutter assets directory contents: " + java.util.Arrays.toString(flutterAssets));
      
      // Look for the asset in flutter_assets directory
      for (String asset : flutterAssets) {
        if (asset.equals(assetPath)) {
          String fullPath = "flutter_assets/" + asset;
          InputStream inputStream = mapView.getContext().getAssets().open(fullPath);
          Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
          inputStream.close();
          if (bitmap != null) {
            Log.d(TAG, "Successfully loaded via flutter_assets listing: " + fullPath);
            return bitmap;
          }
        }
      }
    } catch (Exception e) {
      Log.d(TAG, "Flutter_assets listing strategy failed: " + e.getMessage());
    }
    
    // Strategy 6: Try flutter_assets/assets/ path (where Flutter puts assets)
    try {
      String flutterAssetsPath = "flutter_assets/assets/" + assetPath;
      Log.d(TAG, "Trying flutter_assets/assets path: " + flutterAssetsPath);
      InputStream inputStream = mapView.getContext().getAssets().open(flutterAssetsPath);
      Bitmap bitmap = BitmapFactory.decodeStream(inputStream);
      inputStream.close();
      if (bitmap != null) {
        Log.d(TAG, "Successfully loaded via flutter_assets/assets path: " + flutterAssetsPath);
        return bitmap;
      }
    } catch (Exception e) {
      Log.d(TAG, "Flutter_assets/assets path loading failed: " + e.getMessage());
    }
    
    Log.e(TAG, "All asset loading strategies failed for: " + assetPath);
    return null;
  }

  /**
   * Debug version of getScaledImage with detailed logging
   */
  private Bitmap getScaledImageWithDebug(String imageId, float density) {
    AssetFileDescriptor assetFileDescriptor;
    Log.d(TAG, "getScaledImageWithDebug called with imageId: " + imageId + ", density: " + density);

    // Split image path into parts.
    List<String> imagePathList = Arrays.asList(imageId.split("/"));
    List<String> assetPathList = new ArrayList<>();
    Log.d(TAG, "Image path parts: " + imagePathList);

    // "On devices with a device pixel ratio of 1.8, the asset .../2.0x/my_icon.png would be chosen.
    // For a device pixel ratio of 2.7, the asset .../3.0x/my_icon.png would be chosen."
    // Source: https://flutter.dev/docs/development/ui/assets-and-images#resolution-aware
    for (int i = (int) Math.ceil(density); i > 0; i--) {
      String assetPath;
      if (i == 1) {
        // If density is 1.0x then simply take the default asset path
        assetPath = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(imageId);
        Log.d(TAG, "Default (1x) asset path for '" + imageId + "': " + assetPath);
      } else {
        // Build a resolution aware asset path as follows:
        // <directory asset>/<ratio>/<image name>
        // where ratio is 1.0x, 2.0x or 3.0x.
        StringBuilder stringBuilder = new StringBuilder();
        for (int j = 0; j < imagePathList.size() - 1; j++) {
          stringBuilder.append(imagePathList.get(j));
          stringBuilder.append("/");
        }
        stringBuilder.append(((float) i) + "x");
        stringBuilder.append("/");
        stringBuilder.append(imagePathList.get(imagePathList.size() - 1));
        String scaledImageId = stringBuilder.toString();
        assetPath = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(scaledImageId);
        Log.d(TAG, "Scaled (" + i + "x) asset path for '" + scaledImageId + "': " + assetPath);
      }
      // Build up a list of resolution aware asset paths.
      assetPathList.add(assetPath);
    }

    Log.d(TAG, "All asset paths to try: " + assetPathList);

    // Iterate over asset paths and get the highest scaled asset (as a bitmap).
    Bitmap bitmap = null;
    for (String assetPath : assetPathList) {
      try {
        Log.d(TAG, "Trying to load asset: " + assetPath);
        // Read path (throws exception if doesn't exist).
        assetFileDescriptor = mapView.getContext().getAssets().openFd(assetPath);
        InputStream assetStream = assetFileDescriptor.createInputStream();
        bitmap = BitmapFactory.decodeStream(assetStream);
        assetFileDescriptor.close(); // Close for memory
        if (bitmap != null) {
          Log.d(TAG, "Successfully loaded asset: " + assetPath + " (" + bitmap.getWidth() + "x" + bitmap.getHeight() + ")");
        } else {
          Log.w(TAG, "Bitmap decode returned null for: " + assetPath);
        }
        break; // If exists, break
      } catch (IOException e) {
        Log.d(TAG, "Failed to load asset: " + assetPath + " - " + e.getMessage());
        // Skip
      }
    }
    
    if (bitmap == null) {
      Log.e(TAG, "All asset loading attempts failed for: " + imageId);
    }
    
    return bitmap;
  }

  /**
   * Tries to find highest scale image for display type
   *
   * @param imageId
   * @param density
   * @return
   */
  private Bitmap getScaledImage(String imageId, float density) {
    AssetFileDescriptor assetFileDescriptor;

    // Split image path into parts.
    List<String> imagePathList = Arrays.asList(imageId.split("/"));
    List<String> assetPathList = new ArrayList<>();

    // "On devices with a device pixel ratio of 1.8, the asset .../2.0x/my_icon.png would be chosen.
    // For a device pixel ratio of 2.7, the asset .../3.0x/my_icon.png would be chosen."
    // Source: https://flutter.dev/docs/development/ui/assets-and-images#resolution-aware
    for (int i = (int) Math.ceil(density); i > 0; i--) {
      String assetPath;
      if (i == 1) {
        // If density is 1.0x then simply take the default asset path
        assetPath = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(imageId);
      } else {
        // Build a resolution aware asset path as follows:
        // <directory asset>/<ratio>/<image name>
        // where ratio is 1.0x, 2.0x or 3.0x.
        StringBuilder stringBuilder = new StringBuilder();
        for (int j = 0; j < imagePathList.size() - 1; j++) {
          stringBuilder.append(imagePathList.get(j));
          stringBuilder.append("/");
        }
        stringBuilder.append(((float) i) + "x");
        stringBuilder.append("/");
        stringBuilder.append(imagePathList.get(imagePathList.size() - 1));
        assetPath = MapLibreMapsPlugin.flutterAssets.getAssetFilePathByName(stringBuilder.toString());
      }
      // Build up a list of resolution aware asset paths.
      assetPathList.add(assetPath);
    }

    // Iterate over asset paths and get the highest scaled asset (as a bitmap).
    Bitmap bitmap = null;
    for (String assetPath : assetPathList) {
      try {
        // Read path (throws exception if doesn't exist).
        assetFileDescriptor = mapView.getContext().getAssets().openFd(assetPath);
        InputStream assetStream = assetFileDescriptor.createInputStream();
        bitmap = BitmapFactory.decodeStream(assetStream);
        assetFileDescriptor.close(); // Close for memory
        break; // If exists, break
      } catch (IOException e) {
        // Skip
      }
    }
    return bitmap;
  }

  boolean onMoveBegin(MoveGestureDetector detector) {
    // onMoveBegin gets called even during a move - move end is also not called unless this function
    // returns
    // true at least once. To avoid redundant queries only check for feature if the previous event
    // was ACTION_DOWN
    if (detector.getPreviousEvent().getActionMasked() == MotionEvent.ACTION_DOWN
        && detector.getPointersCount() == 1) {
      PointF pointf = detector.getFocalPoint();
      LatLng origin = mapLibreMap.getProjection().fromScreenLocation(pointf);
      RectF rectF = new RectF(pointf.x - 10, pointf.y - 10, pointf.x + 10, pointf.y + 10);
      Pair<Feature, String> featureLayerPair = firstFeatureOnLayers(rectF);
      if (featureLayerPair != null && featureLayerPair.first != null && startDragging(featureLayerPair.first, origin)) {
        invokeFeatureDrag(pointf, "start");
        return true;
      }
    }
    return false;
  }

  private void invokeFeatureDrag(PointF pointf, String eventType) {
    LatLng current = mapLibreMap.getProjection().fromScreenLocation(pointf);

    final Map<String, Object> arguments = new HashMap<>(9);
    arguments.put("id", draggedFeature.id());
    arguments.put("x", pointf.x);
    arguments.put("y", pointf.y);
    arguments.put("originLng", dragOrigin.getLongitude());
    arguments.put("originLat", dragOrigin.getLatitude());
    arguments.put("currentLng", current.getLongitude());
    arguments.put("currentLat", current.getLatitude());
    arguments.put("eventType", eventType);
    arguments.put("deltaLng", current.getLongitude() - dragPrevious.getLongitude());
    arguments.put("deltaLat", current.getLatitude() - dragPrevious.getLatitude());
    dragPrevious = current;
    methodChannel.invokeMethod("feature#onDrag", arguments);
  }

  boolean onMove(MoveGestureDetector detector) {
    if (draggedFeature != null) {
      if (detector.getPointersCount() > 1) {
        stopDragging();
        return true;
      }
      PointF pointf = detector.getFocalPoint();
      invokeFeatureDrag(pointf, "drag");
      return false;
    }
    return true;
  }

  void onMoveEnd(MoveGestureDetector detector) {
    PointF pointf = detector.getFocalPoint();
    invokeFeatureDrag(pointf, "end");
    stopDragging();
  }

  boolean startDragging(@NonNull Feature feature, @NonNull LatLng origin) {
    final boolean draggable =
        feature.hasNonNullValueForProperty("draggable")
            ? feature.getBooleanProperty("draggable")
            : false;
    if (draggable) {
      draggedFeature = feature;
      dragPrevious = origin;
      dragOrigin = origin;
      return true;
    }
    return false;
  }

  void stopDragging() {
    draggedFeature = null;
    dragOrigin = null;
    dragPrevious = null;
  }

  /** Simple Listener to listen for the status of camera movements. */
  public class OnCameraMoveFinishedListener implements MapLibreMap.CancelableCallback {
    @Override
    public void onFinish() {}

    @Override
    public void onCancel() {}
  }

  private class MoveGestureListener implements MoveGestureDetector.OnMoveGestureListener {

    @Override
    public boolean onMoveBegin(MoveGestureDetector detector) {
      return MapLibreMapController.this.onMoveBegin(detector);
    }

    @Override
    public boolean onMove(MoveGestureDetector detector, float distanceX, float distanceY) {
      return MapLibreMapController.this.onMove(detector);
    }

    @Override
    public void onMoveEnd(MoveGestureDetector detector, float velocityX, float velocityY) {
      MapLibreMapController.this.onMoveEnd(detector);
    }
  }

  // ================================
  // Image Overlay Controls Methods
  // ================================
  
  private void addImageOverlayControls(String overlayId, List<LatLng> coordinates, boolean editMode, MethodChannel.Result result) {
    try {
      // Remove existing controls if any
      removeImageOverlayControls(overlayId, null);
      
      if (editMode && coordinates != null && coordinates.size() == 4) {
        ImageOverlayControlsView controlsView = new ImageOverlayControlsView(
          context, 
          mapLibreMap, 
          coordinates, 
          density,
          overlayId,
          methodChannel
        );
        
        // Add to map view container
        mapViewContainer.addView(controlsView);
        imageOverlayControls.put(overlayId, controlsView);
        
        result.success(null);
      } else {
        result.success(null); // No controls needed when not in edit mode
      }
    } catch (Exception e) {
      result.error("ADD_CONTROLS_ERROR", "Failed to add image overlay controls: " + e.getMessage(), null);
    }
  }
  
  private void updateImageOverlayControls(String overlayId, List<LatLng> coordinates, boolean editMode, MethodChannel.Result result) {
    try {
      ImageOverlayControlsView controlsView = imageOverlayControls.get(overlayId);
      
      if (editMode && coordinates != null && coordinates.size() == 4) {
        if (controlsView != null) {
          // Update existing controls
          controlsView.updateCoordinates(coordinates);
          result.success(null);
        } else {
          // Create new controls
          addImageOverlayControls(overlayId, coordinates, editMode, result);
        }
      } else {
        // Remove controls when not in edit mode
        removeImageOverlayControls(overlayId, result);
      }
    } catch (Exception e) {
      result.error("UPDATE_CONTROLS_ERROR", "Failed to update image overlay controls: " + e.getMessage(), null);
    }
  }
  
  private void removeImageOverlayControls(String overlayId, MethodChannel.Result result) {
    try {
      ImageOverlayControlsView controlsView = imageOverlayControls.get(overlayId);
      if (controlsView != null) {
        mapViewContainer.removeView(controlsView);
        imageOverlayControls.remove(overlayId);
      }
      
      if (result != null) {
        result.success(null);
      }
    } catch (Exception e) {
      if (result != null) {
        result.error("REMOVE_CONTROLS_ERROR", "Failed to remove image overlay controls: " + e.getMessage(), null);
      }
    }
  }
  
  private void handleImageOverlayGesture(String overlayId, String gestureType, double screenX, double screenY, double deltaX, double deltaY, MethodChannel.Result result) {
    try {
      ImageOverlayControlsView controlsView = imageOverlayControls.get(overlayId);
      if (controlsView != null) {
        controlsView.handleGesture(gestureType, (float)screenX, (float)screenY, (float)deltaX, (float)deltaY);
        result.success(null);
      } else {
        result.error("CONTROLS_NOT_FOUND", "Image overlay controls not found for overlayId: " + overlayId, null);
      }
    } catch (Exception e) {
      result.error("GESTURE_HANDLING_ERROR", "Failed to handle gesture: " + e.getMessage(), null);
    }
  }
  
  private void setImageOverlayControlsSensitivity(String overlayId, double sensitivity, MethodChannel.Result result) {
    try {
      ImageOverlayControlsView controlsView = imageOverlayControls.get(overlayId);
      if (controlsView != null) {
        controlsView.setSensitivity(sensitivity);
        result.success(null);
        Log.d(TAG, "Updated sensitivity for overlay " + overlayId + " to " + sensitivity);
      } else {
        result.error("CONTROLS_NOT_FOUND", "Image overlay controls not found for overlayId: " + overlayId, null);
      }
    } catch (Exception e) {
      result.error("SENSITIVITY_ERROR", "Failed to set sensitivity: " + e.getMessage(), null);
    }
  }

  private void enableNativeMeasurement(boolean enabled) {
    if (enabled) {
      if (nativeMeasurementDetector == null && mapLibreMap != null) {
        nativeMeasurementDetector =
            new NativeMeasurementDetector(
                mapLibreMap,
                new NativeMeasurementDetector.OnNativeMeasurementListener() {
                  @Override
                  public void onMeasurementStart(
                      PointF point1,
                      PointF point2,
                      LatLng latLng1,
                      LatLng latLng2,
                      double distance,
                      double bearing,
                      long duration) {
                    sendNativeMeasurementEvent(
                        "measurement#onStart",
                        point1,
                        point2,
                        latLng1,
                        latLng2,
                        distance,
                        bearing,
                        duration);
                  }

                  @Override
                  public void onMeasurementUpdate(
                      PointF point1,
                      PointF point2,
                      LatLng latLng1,
                      LatLng latLng2,
                      double distance,
                      double bearing,
                      long duration) {
                    sendNativeMeasurementEvent(
                        "measurement#onUpdate",
                        point1,
                        point2,
                        latLng1,
                        latLng2,
                        distance,
                        bearing,
                        duration);
                  }

                  @Override
                  public void onMeasurementEnd(
                      PointF point1,
                      PointF point2,
                      LatLng latLng1,
                      LatLng latLng2,
                      double distance,
                      double bearing,
                      long duration) {
                    sendNativeMeasurementEvent(
                        "measurement#onEnd",
                        point1,
                        point2,
                        latLng1,
                        latLng2,
                        distance,
                        bearing,
                        duration);
                  }
                });
        Log.d(TAG, "Native measurement enabled");
      } else if (nativeMeasurementDetector != null) {
        nativeMeasurementDetector.ensureMeasurementLayersOnTop();
      }
    } else if (nativeMeasurementDetector != null) {
      nativeMeasurementDetector.disable();
      nativeMeasurementDetector = null;
      Log.d(TAG, "Native measurement disabled");
    }
  }

  private void setNativeMeasurementStyle(Object arguments) {
    if (nativeMeasurementDetector == null || !(arguments instanceof Map)) {
      return;
    }

    Map<String, Object> styleArgs = (Map<String, Object>) arguments;
    String lineColor = (String) styleArgs.get("lineColor");
    Double lineWidth = (Double) styleArgs.get("lineWidth");
    Double lineOpacity = (Double) styleArgs.get("lineOpacity");
    String endpointColor = (String) styleArgs.get("endpointColor");
    Double endpointRadius = (Double) styleArgs.get("endpointRadius");

    if (lineColor == null) lineColor = "#E8604C";
    if (lineWidth == null) lineWidth = 4.0;
    if (lineOpacity == null) lineOpacity = 0.9;
    if (endpointColor == null) endpointColor = "#FFFFFF";
    if (endpointRadius == null) endpointRadius = 9.0;

    nativeMeasurementDetector.setMeasurementStyle(
        lineColor,
        lineWidth,
        lineOpacity,
        endpointColor,
        endpointRadius);
  }

  private void clearNativeMeasurement() {
    if (nativeMeasurementDetector != null) {
      nativeMeasurementDetector.clearMeasurement();
    }
  }

  private void ensureMeasurementLayersOnTop() {
    if (nativeMeasurementDetector != null) {
      nativeMeasurementDetector.ensureMeasurementLayersOnTop();
    }
  }

  private void sendNativeMeasurementEvent(
      String eventName,
      PointF point1,
      PointF point2,
      LatLng latLng1,
      LatLng latLng2,
      double distance,
      double bearing,
      long duration) {
    Map<String, Object> arguments = new HashMap<>();
    arguments.put("x1", (double) point1.x);
    arguments.put("y1", (double) point1.y);
    arguments.put("x2", (double) point2.x);
    arguments.put("y2", (double) point2.y);
    arguments.put("lat1", latLng1.getLatitude());
    arguments.put("lng1", latLng1.getLongitude());
    arguments.put("lat2", latLng2.getLatitude());
    arguments.put("lng2", latLng2.getLongitude());
    arguments.put("distance", distance);
    arguments.put("bearing", bearing);
    arguments.put("duration", (int) duration);
    methodChannel.invokeMethod(eventName, arguments);
  }

  private void setPolylineDeleteZoneVisible(boolean visible, boolean armed) {
    if (mapViewContainer == null) {
      return;
    }
    if (polylineDeleteZoneView == null && !visible) {
      return;
    }
    if (polylineDeleteZoneView == null) {
      polylineDeleteZoneView = new TextView(context);
      polylineDeleteZoneView.setText("Release to delete waypoint");
      polylineDeleteZoneView.setGravity(Gravity.CENTER);
      polylineDeleteZoneView.setTextColor(Color.WHITE);
      polylineDeleteZoneView.setTextSize(15f);
      polylineDeleteZoneView.setTypeface(Typeface.DEFAULT_BOLD);
      polylineDeleteZoneView.setClickable(false);
      polylineDeleteZoneView.setFocusable(false);
      polylineDeleteZoneView.setVisibility(View.GONE);

      FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
          FrameLayout.LayoutParams.MATCH_PARENT,
          (int) (72f * density),
          Gravity.TOP);
      int margin = (int) (16f * density);
      params.setMargins(margin, margin, margin, 0);
      mapViewContainer.addView(polylineDeleteZoneView, params);
    }

    polylineDeleteZoneView.setBackgroundColor(
        armed ? Color.argb(232, 211, 47, 47) : Color.argb(205, 15, 23, 42));
    polylineDeleteZoneView.setVisibility(visible ? View.VISIBLE : View.GONE);
    if (visible) {
      polylineDeleteZoneView.bringToFront();
    }
  }

  /**
   * Converts a list of LatLng objects to a list of coordinate arrays for Flutter.
   */
  private List<List<Double>> convertLatLngListToCoordinates(@NonNull List<LatLng> latLngs) {
    List<List<Double>> coordinates = new ArrayList<>();
    for (LatLng latLng : latLngs) {
      List<Double> coord = new ArrayList<>();
      coord.add(latLng.getLatitude());
      coord.add(latLng.getLongitude());
      coordinates.add(coord);
    }
    return coordinates;
  }

  // =====================================
  // Triangle Layer Hit-Testing Methods (TAS-8B)
  // =====================================
  
  /**
   * Checks if a layer ID corresponds to a triangle layer.
   * This could be based on naming convention or registry.
   */
  private boolean isTriangleLayer(String layerId) {
    // For now, use simple naming convention
    // This could be enhanced to check a registry of triangle layers
    return layerId != null && (layerId.contains("triangle") || layerId.endsWith("-triangles"));
  }
  
  /**
   * Performs manual hit-testing for triangle CustomLayers.
   * Since CustomLayers don't support queryRenderedFeatures, we need to manually
   * check if the click point intersects with any triangle geometries.
   * 
   * This is a limitation acknowledged in the task specification.
   */
  private Feature performTriangleHitTest(String layerId, RectF hitArea) {
    try {
      Log.d(TAG, "Performing triangle hit-test for layer: " + layerId);
      
      // Get the source data for this triangle layer
      FeatureCollection triangleFeatures = addedFeaturesByLayer.get(getTriangleSourceName(layerId));
      
      if (triangleFeatures == null || triangleFeatures.features() == null) {
        Log.v(TAG, "No triangle features found for layer: " + layerId);
        return null;
      }
      
      // Convert screen coordinates to geographic coordinates
      LatLng hitCenter = mapLibreMap.getProjection().fromScreenLocation(
          new PointF(hitArea.centerX(), hitArea.centerY())
      );
      
      // Check each triangle feature for intersection
      List<Feature> features = triangleFeatures.features();
      for (Feature feature : features) {
        if (feature.geometry() != null && isPointInTriangle(feature, hitCenter, hitArea)) {
          Log.d(TAG, "Triangle hit detected on feature: " + feature.id());
          return feature;
        }
      }
      
      Log.v(TAG, "No triangle hit detected for layer: " + layerId);
      return null;
      
    } catch (Exception e) {
      Log.e(TAG, "Error performing triangle hit-test: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Gets the source name for a triangle layer.
   * This follows the naming convention used when triangle layers are added.
   */
  private String getTriangleSourceName(String layerId) {
    // Triangle layers are typically added with a source that matches the layer name
    // or follows a naming pattern. This could be enhanced based on actual implementation.
    return layerId.replace("-layer", "-source").replace("-triangles", "-triangle-source");
  }
  
  /**
   * Determines if a geographic point intersects with a triangle feature.
   * This uses a simple distance-based approach for point features with triangle styling.
   */
  private boolean isPointInTriangle(Feature feature, LatLng hitPoint, RectF hitArea) {
    try {
      // For point-based triangle features, check distance from the feature center
      if (feature.geometry() instanceof org.maplibre.geojson.Point) {
        org.maplibre.geojson.Point point = (org.maplibre.geojson.Point) feature.geometry();
        LatLng featureLocation = new LatLng(point.latitude(), point.longitude());
        
        // Convert both points to screen coordinates for pixel-based distance calculation
        PointF featureScreen = mapLibreMap.getProjection().toScreenLocation(featureLocation);
        PointF hitScreen = mapLibreMap.getProjection().toScreenLocation(hitPoint);
        
        // Calculate the effective triangle radius in pixels
        // This should ideally come from triangle-size property, but we'll use a default
        float triangleRadiusPx = getTriangleRadiusInPixels(feature);
        
        // Check if the hit point is within the triangle's bounds
        float distance = (float) Math.sqrt(
            Math.pow(featureScreen.x - hitScreen.x, 2) + 
            Math.pow(featureScreen.y - hitScreen.y, 2)
        );
        
        boolean hit = distance <= triangleRadiusPx;
        if (hit) {
          Log.v(TAG, "Triangle hit: distance=" + distance + ", radius=" + triangleRadiusPx);
        }
        return hit;
      }
      
      // For other geometry types, implement appropriate hit-testing logic
      // This is a simplified implementation
      return false;
      
    } catch (Exception e) {
      Log.w(TAG, "Error checking triangle intersection: " + e.getMessage());
      return false;
    }
  }
  
  /**
   * Gets the effective triangle radius in pixels for hit-testing.
   * This should ideally read from the triangle layer properties.
   */
  private float getTriangleRadiusInPixels(Feature feature) {
    // Default triangle radius in pixels for hit-testing
    float defaultRadiusPx = 15.0f;
    
    try {
      // Try to get triangle-size from feature properties
      if (feature.hasProperty("triangle-size")) {
        Number size = feature.getNumberProperty("triangle-size");
        if (size != null) {
          return size.floatValue() * density; // Convert to pixels
        }
      }
      
      // Try to get from triangle-radius property
      if (feature.hasProperty("triangle-radius")) {
        Number radius = feature.getNumberProperty("triangle-radius");
        if (radius != null) {
          return radius.floatValue() * density; // Convert to pixels
        }
      }
    } catch (Exception e) {
      Log.v(TAG, "Could not read triangle size from feature properties: " + e.getMessage());
    }
    
    return defaultRadiusPx;
  }

  /**
   * Ensures that an ADSB arrow icon exists in the map style.
   * Creates a programmatic arrow bitmap if it doesn't exist.
   */
  private void ensureADSBArrowIconExists() {
    final String arrowIconId = "maplibre-adsb-arrow-icon";
    
    try {
      // Check if icon already exists
      if (style != null && style.getImage(arrowIconId) != null) {
        Log.v(TAG, "ADSB Arrow icon already exists: " + arrowIconId);
        return;
      }
      
      // Create ADSB arrow bitmap programmatically
      Bitmap arrowBitmap = createADSBArrowBitmap();
      
      if (style != null && arrowBitmap != null) {
        style.addImage(arrowIconId, arrowBitmap, false); // false = not SDF
        Log.d(TAG, "Added ADSB arrow icon to style: " + arrowIconId);
      } else {
        Log.e(TAG, "Failed to add ADSB arrow icon - style or bitmap is null");
        throw new RuntimeException("Cannot add ADSB arrow icon: style or bitmap is null");
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error ensuring ADSB arrow icon exists: " + e.getMessage(), e);
      throw new RuntimeException("Failed to create ADSB arrow icon", e);
    }
  }
  
  /**
   * Creates an ADSB traffic arrow bitmap programmatically.
   * Returns a bitmap containing a filled arrow shape like the attached screenshot.
   */
  private Bitmap createADSBArrowBitmap() {
    try {
      // Create a high-resolution bitmap to avoid pixelation when scaled
      int size = 64; // Fixed 64x64 pixels for crisp rendering at all scales
      
      // Create bitmap and canvas
      Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      // Create paint for ADSB arrow with anti-aliasing
      Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
      paint.setColor(0xFF4CAF50); // Green color like in screenshot
      paint.setStyle(Paint.Style.FILL);
      paint.setFilterBitmap(true); // Enable bitmap filtering for smoother scaling
      
      // Create ADSB arrow path (pointing right/east by default)
      Path arrowPath = new Path();
      float centerX = size / 2.0f;
      float centerY = size / 2.0f;
      float arrowLength = size * 0.6f; // Arrow length
      float arrowWidth = size * 0.3f;  // Arrow width
      float headLength = size * 0.25f; // Arrow head length
      float headWidth = size * 0.4f;   // Arrow head width
      
      // Calculate arrow points (pointing right)
      float bodyLeft = centerX - arrowLength/2;
      float bodyRight = centerX + arrowLength/2 - headLength;
      float bodyTop = centerY - arrowWidth/2;
      float bodyBottom = centerY + arrowWidth/2;
      
      float headLeft = bodyRight;
      float headRight = centerX + arrowLength/2;
      float headTop = centerY - headWidth/2;
      float headBottom = centerY + headWidth/2;
      float tipX = headRight;
      float tipY = centerY;
      
      // Build arrow path
      arrowPath.moveTo(bodyLeft, bodyTop);          // Start at body top-left
      arrowPath.lineTo(bodyRight, bodyTop);         // Body top edge
      arrowPath.lineTo(headLeft, headTop);          // Arrow head top-left
      arrowPath.lineTo(tipX, tipY);                 // Arrow tip
      arrowPath.lineTo(headLeft, headBottom);       // Arrow head bottom-left
      arrowPath.lineTo(bodyRight, bodyBottom);      // Body bottom edge
      arrowPath.lineTo(bodyLeft, bodyBottom);       // Body bottom-left
      arrowPath.close();
      
      canvas.drawPath(arrowPath, paint);
      
      // Add stroke for better visibility
      Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      strokePaint.setColor(0xFF2E7D32); // Darker green stroke
      strokePaint.setStyle(Paint.Style.STROKE);
      strokePaint.setStrokeWidth(1.5f); // Thinner stroke for arrow
      strokePaint.setFilterBitmap(true);
      canvas.drawPath(arrowPath, strokePaint);
      
      Log.d(TAG, "Created ADSB arrow bitmap: " + size + "x" + size + " pixels");
      return bitmap;
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating ADSB arrow bitmap: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Adds a symbol layer configured to render ADSB arrows using the arrow icon.
   */
  private void addADSBArrowSymbolLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    
    try {
      final String arrowIconId = "maplibre-adsb-arrow-icon";
      
      // Create symbol layer
      SymbolLayer symbolLayer = new SymbolLayer(layerName, sourceName);
      
      // Configure basic symbol properties for arrow rendering
      List<PropertyValue> symbolProperties = new ArrayList<>();
      
      // Set the arrow icon
      symbolProperties.add(PropertyFactory.iconImage(arrowIconId));
      
      // Default symbol properties for ADSB arrows
      symbolProperties.add(PropertyFactory.iconSize(0.5f)); // Medium size for traffic visibility
      symbolProperties.add(PropertyFactory.iconAllowOverlap(true));
      symbolProperties.add(PropertyFactory.iconIgnorePlacement(true));
      // Use viewport alignment to prevent scaling with zoom
      symbolProperties.add(PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_VIEWPORT));
      symbolProperties.add(PropertyFactory.iconPitchAlignment(Property.ICON_PITCH_ALIGNMENT_VIEWPORT));
      
      // Process input properties and map arrow-specific properties to symbol properties
      if (properties != null) {
        for (PropertyValue<?> prop : properties) {
          if (prop != null) {
            try {
              switch (prop.name) {
                case "arrow-size":
                case "adsb-size":
                  // Map arrow-size to icon-size
                  if (prop.value instanceof Number) {
                    float size = ((Number) prop.value).floatValue() / 32.0f; // Scale for arrows
                    symbolProperties.add(PropertyFactory.iconSize(size));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconSize((Expression) prop.value));
                  }
                  break;
                case "arrow-opacity":
                case "adsb-opacity":
                  // Map arrow-opacity to icon-opacity
                  if (prop.value instanceof Number) {
                    symbolProperties.add(PropertyFactory.iconOpacity(((Number) prop.value).floatValue()));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconOpacity((Expression) prop.value));
                  }
                  break;
                case "arrow-rotation":
                case "adsb-rotation":
                case "heading":
                  // Map rotation/heading to icon-rotate
                  if (prop.value instanceof Number) {
                    symbolProperties.add(PropertyFactory.iconRotate(((Number) prop.value).floatValue()));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconRotate((Expression) prop.value));
                  }
                  break;
                case "arrow-offset":
                case "adsb-offset":
                  // Map arrow-offset to icon-offset
                  if (prop.value instanceof float[] && ((float[]) prop.value).length >= 2) {
                    float[] offset = (float[]) prop.value;
                    symbolProperties.add(PropertyFactory.iconOffset(new Float[]{offset[0], offset[1]}));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconOffset((Expression) prop.value));
                  }
                  break;
                default:
                  Log.v(TAG, "ADSB Arrow property not mapped to symbol layer: " + prop.name);
                  break;
              }
            } catch (Exception e) {
              Log.w(TAG, "Failed to process ADSB arrow property: " + prop.name + ", error: " + e.getMessage());
            }
          }
        }
      }
      
      // Apply all collected properties to the symbol layer
      symbolLayer.setProperties(symbolProperties.toArray(new PropertyValue[0]));
      
      // Set other layer properties
      if (sourceLayer != null) {
        symbolLayer.setSourceLayer(sourceLayer);
      }
      if (minZoom != null) {
        symbolLayer.setMinZoom(minZoom);
      }
      if (maxZoom != null) {
        symbolLayer.setMaxZoom(maxZoom);
      }
      if (filter != null) {
        symbolLayer.setFilter(filter);
      }
      
      // Add layer to style
      if (style != null) {
        if (belowLayerId != null) {
          style.addLayerBelow(symbolLayer, belowLayerId);
        } else {
          style.addLayer(symbolLayer);
        }
        
        Log.d(TAG, "Added ADSB arrow symbol layer: " + layerName + " with source: " + sourceName);
        
        if (enableInteraction) {
          interactiveFeatureLayerIds.add(layerName);
        }
      } else {
        throw new RuntimeException("Cannot add ADSB arrow symbol layer: style is null");
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error adding ADSB arrow symbol layer: " + layerName, e);
      throw new RuntimeException("Failed to add ADSB arrow symbol layer: " + layerName, e);
    }
  }
  
  /**
   * Main method to add ADSB arrow layer
   */
  private void addADSBArrowLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    
    try {
      Log.d(TAG, "Adding ADSB arrow symbol layer: " + layerName);
      
      // Create ADSB arrow icon if it doesn't exist
      ensureADSBArrowIconExists();
      
      // Use symbol layer with ADSB arrow icon
      addADSBArrowSymbolLayer(layerName, sourceName, belowLayerId, sourceLayer, minZoom, maxZoom, properties, enableInteraction, filter);
      
    } catch (Exception e) {
      Log.e(TAG, "Failed to create ADSB arrow layer: " + e.getMessage(), e);
      // Could add fallback here
    }
  }

  /**
   * Ensures that arrow icons exist in the map style.
   * Creates up and down arrow bitmaps if they don't exist.
   */
  private void ensureArrowIconsExist() {
    final String upArrowIconId = "maplibre-arrow-up-icon";
    final String downArrowIconId = "maplibre-arrow-down-icon";
    
    try {
      // Check if icons already exist
      if (style != null && style.getImage(upArrowIconId) != null && style.getImage(downArrowIconId) != null) {
        Log.v(TAG, "Arrow icons already exist");
        return;
      }
      
      // Create arrow bitmaps programmatically
      Bitmap upArrowBitmap = createArrowBitmap(true);   // pointing up
      Bitmap downArrowBitmap = createArrowBitmap(false); // pointing down
      
      if (style != null && upArrowBitmap != null && downArrowBitmap != null) {
        style.addImage(upArrowIconId, upArrowBitmap, false);
        style.addImage(downArrowIconId, downArrowBitmap, false);
        Log.d(TAG, "Added arrow icons to style: " + upArrowIconId + ", " + downArrowIconId);
      } else {
        Log.e(TAG, "Failed to add arrow icons - style or bitmaps are null");
        throw new RuntimeException("Cannot add arrow icons: style or bitmaps are null");
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error ensuring arrow icons exist: " + e.getMessage(), e);
      throw new RuntimeException("Failed to create arrow icons", e);
    }
  }
  
  /**
   * Creates an arrow bitmap programmatically.
   * @param pointingUp true for up arrow, false for down arrow
   * @return bitmap containing arrow shape
   */
  private Bitmap createArrowBitmap(boolean pointingUp) {
    try {
      int size = 32; // Smaller size for arrows compared to triangle
      
      // Create bitmap and canvas
      Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      // Create paint for arrow with anti-aliasing
      Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
      paint.setColor(0xFF000000); // Black arrow
      paint.setStyle(Paint.Style.FILL);
      paint.setFilterBitmap(true);
      
      // Create arrow path
      Path arrowPath = new Path();
      float centerX = size / 2.0f;
      float centerY = size / 2.0f;
      float arrowHeight = size * 0.6f; // Arrow height
      float arrowWidth = size * 0.4f;  // Arrow width
      
      if (pointingUp) {
        // Up arrow: ▲
        float topX = centerX;
        float topY = centerY - arrowHeight / 2;
        float bottomLeftX = centerX - arrowWidth / 2;
        float bottomLeftY = centerY + arrowHeight / 2;
        float bottomRightX = centerX + arrowWidth / 2;
        float bottomRightY = centerY + arrowHeight / 2;
        
        arrowPath.moveTo(topX, topY);
        arrowPath.lineTo(bottomLeftX, bottomLeftY);
        arrowPath.lineTo(bottomRightX, bottomRightY);
        arrowPath.close();
      } else {
        // Down arrow: ▼
        float topLeftX = centerX - arrowWidth / 2;
        float topLeftY = centerY - arrowHeight / 2;
        float topRightX = centerX + arrowWidth / 2;
        float topRightY = centerY - arrowHeight / 2;
        float bottomX = centerX;
        float bottomY = centerY + arrowHeight / 2;
        
        arrowPath.moveTo(topLeftX, topLeftY);
        arrowPath.lineTo(topRightX, topRightY);
        arrowPath.lineTo(bottomX, bottomY);
        arrowPath.close();
      }
      
      canvas.drawPath(arrowPath, paint);
      
      // Add white stroke for better visibility
      Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      strokePaint.setColor(0xFFFFFFFF); // White stroke
      strokePaint.setStyle(Paint.Style.STROKE);
      strokePaint.setStrokeWidth(1.5f);
      strokePaint.setFilterBitmap(true);
      canvas.drawPath(arrowPath, strokePaint);
      
      Log.d(TAG, "Created arrow bitmap (pointing " + (pointingUp ? "up" : "down") + "): " + size + "x" + size + " pixels");
      return bitmap;
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating arrow bitmap: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Ensures the triangle icon exists in the map style.
   * Creates and adds the triangle icon if it doesn't exist.
   */
  private void ensureTriangleIconExists() {
    final String triangleIconId = "maplibre-triangle-icon";
    
    try {
      // Check if icon already exists
      if (style != null && style.getImage(triangleIconId) != null) {
        Log.v(TAG, "Triangle icon already exists: " + triangleIconId);
        return;
      }
      
      // Create triangle bitmap programmatically
      Bitmap triangleBitmap = createTriangleBitmap();
      
      if (style != null && triangleBitmap != null) {
        style.addImage(triangleIconId, triangleBitmap, false); // false = not SDF
        Log.d(TAG, "Added triangle icon to style: " + triangleIconId);
      } else {
        Log.e(TAG, "Failed to add triangle icon - style or bitmap is null");
        throw new RuntimeException("Cannot add triangle icon: style or bitmap is null");
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error ensuring triangle icon exists: " + e.getMessage(), e);
      throw new RuntimeException("Failed to create triangle icon", e);
    }
  }
  
  /**
   * Creates a triangle bitmap programmatically.
   * Returns a bitmap containing a filled triangle shape.
   */
  private Bitmap createTriangleBitmap() {
    try {
      // Create a high-resolution bitmap to avoid pixelation when scaled
      // Use a fixed size that works well across different densities
      int size = 64; // Fixed 64x64 pixels for crisp rendering at all scales
      
      // Create bitmap and canvas
      Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      // Create paint for triangle with anti-aliasing
      Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
      paint.setColor(0xFFFF6B35); // Orange color
      paint.setStyle(Paint.Style.FILL);
      paint.setFilterBitmap(true); // Enable bitmap filtering for smoother scaling
      
      // Create triangle path
      Path trianglePath = new Path();
      float centerX = size / 2.0f;
      float centerY = size / 2.0f;
      float radius = size * 0.35f; // Triangle radius
      
      // Calculate triangle points (equilateral triangle pointing up)
      float topX = centerX;
      float topY = centerY - radius;
      
      float bottomLeftX = centerX - (radius * 0.866f); // cos(30°) * radius
      float bottomLeftY = centerY + (radius * 0.5f);   // sin(30°) * radius
      
      float bottomRightX = centerX + (radius * 0.866f);
      float bottomRightY = centerY + (radius * 0.5f);
      
      // Draw triangle
      trianglePath.moveTo(topX, topY);
      trianglePath.lineTo(bottomLeftX, bottomLeftY);
      trianglePath.lineTo(bottomRightX, bottomRightY);
      trianglePath.close();
      
      canvas.drawPath(trianglePath, paint);
      
      // Add stroke for better visibility
      Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      strokePaint.setColor(0xFFFFFFFF); // White stroke
      strokePaint.setStyle(Paint.Style.STROKE);
      strokePaint.setStrokeWidth(2.0f); // Thicker stroke for 64x64 bitmap
      strokePaint.setFilterBitmap(true);
      canvas.drawPath(trianglePath, strokePaint);
      
      Log.d(TAG, "Created triangle bitmap: " + size + "x" + size + " pixels");
      return bitmap;
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating triangle bitmap: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Adds a symbol layer configured to render triangles using the triangle icon.
   */
  private void addTriangleSymbolLayer(
      String layerName,
      String sourceName,
      String belowLayerId,
      String sourceLayer,
      Float minZoom,
      Float maxZoom,
      PropertyValue[] properties,
      boolean enableInteraction,
      Expression filter) {
    
    try {
      final String triangleIconId = "maplibre-triangle-icon";
      
      // Create symbol layer
      SymbolLayer symbolLayer = new SymbolLayer(layerName, sourceName);
      
      // Configure basic symbol properties for triangle rendering
      List<PropertyValue> symbolProperties = new ArrayList<>();
      
      // Set the triangle icon
      symbolProperties.add(PropertyFactory.iconImage(triangleIconId));
      
      // Default symbol properties for triangles - make very small by default
      symbolProperties.add(PropertyFactory.iconSize(0.25f)); // Very small base size (1/4 of normal)
      symbolProperties.add(PropertyFactory.iconAllowOverlap(true));
      symbolProperties.add(PropertyFactory.iconIgnorePlacement(true));
      // Use viewport alignment to prevent scaling with zoom like circles do
      symbolProperties.add(PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_VIEWPORT));
      symbolProperties.add(PropertyFactory.iconPitchAlignment(Property.ICON_PITCH_ALIGNMENT_VIEWPORT));
      
      // Process input properties and map triangle-specific properties to symbol properties
      if (properties != null) {
        for (PropertyValue<?> prop : properties) {
          if (prop != null) {
            try {
              switch (prop.name) {
                case "triangle-size":
                  // Map triangle-size to icon-size
                  if (prop.value instanceof Number) {
                    float size = ((Number) prop.value).floatValue() / 64.0f; // Scale down even more aggressively
                    symbolProperties.add(PropertyFactory.iconSize(size));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconSize((Expression) prop.value));
                  }
                  break;
                case "triangle-color":
                  // Triangle color affects the icon tint (if supported)
                  if (prop.value instanceof String || prop.value instanceof Integer || prop.value instanceof Expression) {
                    // Note: Icon color tinting is not directly supported in MapLibre
                    // The icon bitmap would need to be white for tinting to work properly
                    Log.v(TAG, "Triangle color property noted but icon tinting not implemented: " + prop.value);
                  }
                  break;
                case "triangle-opacity":
                  // Map triangle-opacity to icon-opacity
                  if (prop.value instanceof Number) {
                    symbolProperties.add(PropertyFactory.iconOpacity(((Number) prop.value).floatValue()));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconOpacity((Expression) prop.value));
                  }
                  break;
                case "triangle-rotation":
                  // Map triangle-rotation to icon-rotate
                  if (prop.value instanceof Number) {
                    symbolProperties.add(PropertyFactory.iconRotate(((Number) prop.value).floatValue()));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconRotate((Expression) prop.value));
                  }
                  break;
                case "triangle-offset":
                  // Map triangle-offset to icon-offset
                  if (prop.value instanceof float[] && ((float[]) prop.value).length >= 2) {
                    float[] offset = (float[]) prop.value;
                    symbolProperties.add(PropertyFactory.iconOffset(new Float[]{offset[0], offset[1]}));
                  } else if (prop.value instanceof Expression) {
                    symbolProperties.add(PropertyFactory.iconOffset((Expression) prop.value));
                  }
                  break;
                default:
                  Log.v(TAG, "Triangle property not mapped to symbol layer: " + prop.name);
                  break;
              }
            } catch (Exception e) {
              Log.w(TAG, "Failed to process triangle property: " + prop.name + ", error: " + e.getMessage());
            }
          }
        }
      }
      
      // Apply all collected properties to the symbol layer
      symbolLayer.setProperties(symbolProperties.toArray(new PropertyValue[0]));
      
      // Set other layer properties
      if (sourceLayer != null) {
        symbolLayer.setSourceLayer(sourceLayer);
      }
      if (minZoom != null) {
        symbolLayer.setMinZoom(minZoom);
      }
      if (maxZoom != null) {
        symbolLayer.setMaxZoom(maxZoom);
      }
      if (filter != null) {
        symbolLayer.setFilter(filter);
      }
      
      // Add layer to style
      if (style != null) {
        if (belowLayerId != null) {
          style.addLayerBelow(symbolLayer, belowLayerId);
        } else {
          style.addLayer(symbolLayer);
        }
        
        Log.d(TAG, "Added triangle symbol layer: " + layerName + " with source: " + sourceName);
        
        if (enableInteraction) {
          interactiveFeatureLayerIds.add(layerName);
        }
      } else {
        throw new RuntimeException("Cannot add triangle symbol layer: style is null");
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error adding triangle symbol layer: " + layerName, e);
      throw new RuntimeException("Failed to add triangle symbol layer: " + layerName, e);
    }
  }
  
  /**
   * Adds a multi-layer rotatable symbol to the map using PNG assets.
   * Creates 4 synchronized layers: aircraft PNG, top label, bottom label, and side arrow PNG.
   * Similar to addRotatableSymbolLayers but uses PNG assets instead of programmatically created icons.
   * 
   * @param sourceId GeoJSON source containing the symbol data
   * @param baseLayerId Base layer ID (will append suffixes for each layer)
   * @param belowLayerId Optional layer to place below
   * @param properties Symbol properties including PNG paths, rotation, labels, etc.
   * @param enableInteraction Whether to enable tap interaction
   */
  public void addRotatableSymbolPngLayers(
      String sourceId,
      String baseLayerId,
      String belowLayerId,
      Map<String, Object> properties,
      boolean enableInteraction) {
    
    try {
      Log.d(TAG, "Adding rotatable symbol PNG layers with base ID: " + baseLayerId);
      
      // Extract PNG asset configuration from properties
      Map<String, Object> config = (Map<String, Object>) properties.get("config");
      if (config == null) {
        config = new HashMap<>();
      }
      
      // Extract PNG asset paths and sizes
      String aircraftIconPath = (String) config.get("aircraftIconPath");
      String arrowIconPath = (String) config.get("arrowIconPath");
      double aircraftIconSize = ((Number) config.getOrDefault("aircraftIconSize", 0.4)).doubleValue();
      double arrowIconSize = ((Number) config.getOrDefault("arrowIconSize", 0.3)).doubleValue();
      
      // Validate required PNG paths
      if (aircraftIconPath == null || aircraftIconPath.isEmpty()) {
        throw new RuntimeException("aircraftIconPath is required in config for PNG layers");
      }
      if (arrowIconPath == null || arrowIconPath.isEmpty()) {
        throw new RuntimeException("arrowIconPath is required in config for PNG layers");
      }
      
      // Load and register PNG assets
      String aircraftIconId = ensurePngAssetExists(aircraftIconPath, "aircraft");
      String upArrowIconId = ensurePngAssetExists(arrowIconPath, "arrow-up");
      String downArrowIconId = ensurePngAssetExists(arrowIconPath, "arrow-down");
      
      // Layer positioning configuration
      double topLabelOffset = ((Number) config.getOrDefault("topLabelOffset", -2.5)).doubleValue();
      double bottomLabelOffset = ((Number) config.getOrDefault("bottomLabelOffset", 2.5)).doubleValue();
      double arrowOffsetX = ((Number) config.getOrDefault("arrowOffsetX", 20.0)).doubleValue();
      
      // 1. Add aircraft PNG layer (rotatable with map)
      String aircraftLayerId = baseLayerId + "-aircraft";
      SymbolLayer aircraftLayer = new SymbolLayer(aircraftLayerId, sourceId);
      aircraftLayer.setProperties(
          PropertyFactory.iconImage(aircraftIconId),
          PropertyFactory.iconSize((float) aircraftIconSize),
          PropertyFactory.iconRotate(Expression.get("rotation")),
          PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP), // Rotates with map
          PropertyFactory.iconAllowOverlap(true),
          PropertyFactory.iconIgnorePlacement(true),
          PropertyFactory.iconOpacity(Expression.get("triangleOpacity")), // Reuse triangleOpacity property
          PropertyFactory.iconColor(Expression.get("aircraftIconColor")) // Dynamic color based on proximity
      );
      
      Log.d(TAG, "Aircraft layer configured with color property: aircraftIconColor");
      
      // 2. Add top label layer (viewport aligned, stays horizontal)
      String topLabelLayerId = baseLayerId + "-top-label";
      SymbolLayer topLabelLayer = new SymbolLayer(topLabelLayerId, sourceId);
      topLabelLayer.setProperties(
          PropertyFactory.textField(Expression.get("topLabel")),
          PropertyFactory.textFont(new String[]{"Open Sans Regular", "Arial Unicode MS Regular"}),
          PropertyFactory.textSize(Expression.get("labelSize")),
          PropertyFactory.textColor(Expression.get("labelColor")),
          PropertyFactory.textHaloColor("#FFFFFF"),
          PropertyFactory.textHaloWidth(2.0f),
          PropertyFactory.textOffset(new Float[]{0.0f, (float) topLabelOffset}),
          PropertyFactory.textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_VIEWPORT), // Always horizontal
          PropertyFactory.textAllowOverlap(true),
          PropertyFactory.textIgnorePlacement(true)
      );
      
      // 3. Add bottom label layer (viewport aligned, stays horizontal)
      String bottomLabelLayerId = baseLayerId + "-bottom-label";
      SymbolLayer bottomLabelLayer = new SymbolLayer(bottomLabelLayerId, sourceId);
      bottomLabelLayer.setProperties(
          PropertyFactory.textField(Expression.get("bottomLabel")),
          PropertyFactory.textFont(new String[]{"Open Sans Regular", "Arial Unicode MS Regular"}),
          PropertyFactory.textSize(Expression.get("labelSize")),
          PropertyFactory.textColor(Expression.get("labelColor")),
          PropertyFactory.textHaloColor("#FFFFFF"),
          PropertyFactory.textHaloWidth(2.0f),
          PropertyFactory.textOffset(new Float[]{0.0f, (float) bottomLabelOffset}),
          PropertyFactory.textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_VIEWPORT), // Always horizontal
          PropertyFactory.textAllowOverlap(true),
          PropertyFactory.textIgnorePlacement(true)
      );
      
      // 4. Add arrow PNG layer (viewport aligned, fixed to right side)
      String arrowLayerId = baseLayerId + "-arrow";
      SymbolLayer arrowLayer = new SymbolLayer(arrowLayerId, sourceId);
      arrowLayer.setProperties(
          PropertyFactory.iconImage(
              Expression.switchCase(
                  Expression.get("isClimbing"),
                  Expression.literal(upArrowIconId),
                  Expression.literal(downArrowIconId)
              )
          ),
          PropertyFactory.iconSize((float) arrowIconSize),
          PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_VIEWPORT), // Always upright
          PropertyFactory.iconOffset(new Float[]{(float) arrowOffsetX, 0.0f}), // Fixed to right side
          PropertyFactory.iconAllowOverlap(true),
          PropertyFactory.iconIgnorePlacement(true),
          PropertyFactory.iconOpacity(Expression.get("arrowOpacity")),
          PropertyFactory.iconColor(Expression.get("arrowIconColor")) // Dynamic arrow color
      );
      
      Log.d(TAG, "Arrow layer configured with color property: arrowIconColor");
      
      // Add layers to style in proper order (aircraft first, then text on top, arrow last)
      if (belowLayerId != null) {
        style.addLayerBelow(aircraftLayer, belowLayerId);
        style.addLayerAbove(topLabelLayer, aircraftLayerId);
        style.addLayerAbove(bottomLabelLayer, topLabelLayerId);
        style.addLayerAbove(arrowLayer, bottomLabelLayerId);
      } else {
        style.addLayer(aircraftLayer);
        style.addLayer(topLabelLayer);
        style.addLayer(bottomLabelLayer);
        style.addLayer(arrowLayer);
      }
      
      // Enable interaction if requested
      if (enableInteraction) {
        interactiveFeatureLayerIds.add(aircraftLayerId);
        interactiveFeatureLayerIds.add(topLabelLayerId);
        interactiveFeatureLayerIds.add(bottomLabelLayerId);
        interactiveFeatureLayerIds.add(arrowLayerId);
      }
      
      Log.d(TAG, "Successfully added rotatable symbol PNG layers: " + aircraftLayerId + ", " + topLabelLayerId + ", " + bottomLabelLayerId + ", " + arrowLayerId);
      
    } catch (Exception e) {
      String errorMessage = "Failed to add rotatable symbol PNG layers '" + baseLayerId + "': " + e.getMessage();
      Log.e(TAG, errorMessage, e);
      throw new RuntimeException(errorMessage, e);
    }
  }
  
  /**
   * Ensures a PNG asset exists in the map style.
   * Loads the PNG from assets and registers it with a unique name.
   * 
   * @param assetPath Path to the PNG asset
   * @param iconType Type identifier (e.g., "aircraft", "arrow-up", "arrow-down")
   * @return The registered icon identifier
   */
  private String ensurePngAssetExists(String assetPath, String iconType) {
    try {
      // Handle test color icon specially
      if ("test-color-icon".equals(assetPath)) {
        return createTestColorIcon();
      }
      
      // Create unique icon ID based on asset path and type
      String iconId = "maplibre-png-" + iconType + "-" + assetPath.replaceAll("[^a-zA-Z0-9]", "-");
      
      // Check if icon already exists
      if (style != null && style.getImage(iconId) != null) {
        Log.v(TAG, "PNG icon already exists: " + iconId);
        return iconId;
      }
      
      Log.d(TAG, "Loading PNG asset: " + assetPath + " for icon type: " + iconType);
      
      // Try to load PNG directly from assets using Flutter asset resolution
      Bitmap bitmap = loadAssetDirectly(assetPath);
      if (bitmap == null) {
        throw new RuntimeException("Failed to load PNG asset: " + assetPath);
      }
      
      Log.d(TAG, "Successfully loaded bitmap: " + bitmap.getWidth() + "x" + bitmap.getHeight() + " pixels");
      
      // For arrow icons, we might want to create rotated versions
      if (iconType.startsWith("arrow")) {
        if (iconType.equals("arrow-up")) {
          // Use bitmap as-is for up arrow
        } else if (iconType.equals("arrow-down")) {
          // Rotate bitmap 180 degrees for down arrow
          bitmap = rotateBitmap(bitmap, 180);
        }
      }
      
      // Register the PNG icon as SDF for color tinting support
      if (style != null) {
        style.addImage(iconId, bitmap, true); // true = SDF for color tinting
        Log.d(TAG, "Added PNG icon to style as SDF: " + iconId + " from " + assetPath);
      } else {
        throw new RuntimeException("Cannot add PNG icon: style is null");
      }
      
      return iconId;
      
    } catch (Exception e) {
      Log.e(TAG, "Error ensuring PNG asset exists: " + assetPath + ", error: " + e.getMessage(), e);
      throw new RuntimeException("Failed to load PNG asset: " + assetPath, e);
    }
  }
  
  /**
   * Creates a simple colored test icon for debugging color tinting
   */
  private String createTestColorIcon() {
    try {
      String iconId = "test-color-icon";
      
      // Create a simple white square bitmap for testing color tinting
      Bitmap bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      // Fill with white color (best for tinting)
      Paint paint = new Paint();
      paint.setColor(0xFFFFFFFF); // White
      paint.setAntiAlias(true);
      canvas.drawRect(8, 8, 56, 56, paint);
      
      // Add to style as SDF for color tinting
      if (style != null) {
        style.addImage(iconId, bitmap, true); // true = SDF for color tinting
        Log.d(TAG, "Created test color icon: " + iconId);
      }
      
      return iconId;
    } catch (Exception e) {
      Log.e(TAG, "Error creating test color icon: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Rotates a bitmap by the specified angle.
   * 
   * @param bitmap The bitmap to rotate
   * @param angle The rotation angle in degrees
   * @return The rotated bitmap
   */
  private Bitmap rotateBitmap(Bitmap bitmap, float angle) {
    try {
      android.graphics.Matrix matrix = new android.graphics.Matrix();
      matrix.postRotate(angle);
      return Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
    } catch (Exception e) {
      Log.e(TAG, "Error rotating bitmap: " + e.getMessage(), e);
      return bitmap; // Return original if rotation fails
    }
  }
  
  /**
   * Helper method to load a single PNG asset from Flutter assets.
   */
  private Bitmap loadPngAsset(String assetPath) {
    Log.d(TAG, "loadPngAsset: Loading PNG asset: " + assetPath);
    
    try {
      // Try different asset resolution strategies
      Bitmap bitmap = loadAssetDirectly(assetPath);
      
      if (bitmap != null) {
        Log.d(TAG, "loadPngAsset: Successfully loaded PNG asset: " + assetPath + " (" + bitmap.getWidth() + "x" + bitmap.getHeight() + ")");
        return bitmap;
      } else {
        Log.e(TAG, "loadPngAsset: Failed to load PNG asset: " + assetPath);
        // Try fallback: use single color bitmap for testing
        return createFallbackColorBitmap(assetPath);
      }
    } catch (Exception e) {
      Log.e(TAG, "loadPngAsset: Error loading PNG asset " + assetPath + ": " + e.getMessage(), e);
      // Try fallback: use single color bitmap for testing
      return createFallbackColorBitmap(assetPath);
    }
  }
  
  /**
   * Creates a fallback colored bitmap for testing when PNG assets fail to load
   */
  private Bitmap createFallbackColorBitmap(String assetPath) {
    try {
      int size = 32;
      Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
      
      // Choose color based on asset path
      if (assetPath.contains("red")) {
        paint.setColor(0xFFFF0000); // Red
      } else if (assetPath.contains("yellow")) {
        paint.setColor(0xFFFFFF00); // Yellow
      } else if (assetPath.contains("blue")) {
        paint.setColor(0xFF0000FF); // Blue
      } else if (assetPath.contains("green")) {
        paint.setColor(0xFF00FF00); // Green
      } else if (assetPath.contains("arrow")) {
        paint.setColor(0xFF808080); // Gray for arrow
      } else {
        paint.setColor(0xFFFF00FF); // Magenta for unknown
      }
      
      canvas.drawCircle(size/2f, size/2f, size/2f - 2, paint);
      
      Log.w(TAG, "createFallbackColorBitmap: Created fallback colored bitmap for: " + assetPath);
      return bitmap;
    } catch (Exception e) {
      Log.e(TAG, "createFallbackColorBitmap: Error creating fallback bitmap: " + e.getMessage(), e);
      return null;
    }
  }

  /**
   * Creates a pill/lozenge style label bitmap with rounded rectangle background.
   * This method generates a professional aviation-style label with:
   * - Rounded rectangle background (pill/lozenge shape)
   * - Custom background color
   * - Custom text color
   * - Configurable padding and corner radius
   * 
   * Use case: Airspace labels, airport labels, or any text that needs a unified background.
   * 
   * @param text The text to display in the label
   * @param backgroundColor Hex color string for background (e.g., "#0066FF")
   * @param textColor Hex color string for text (e.g., "#FFFFFF")
   * @param textSize Text size in pixels (e.g., 14.0f)
   * @param paddingHorizontal Horizontal padding in pixels (e.g., 12.0f)
   * @param paddingVertical Vertical padding in pixels (e.g., 6.0f)
   * @param cornerRadius Corner radius for rounded rectangle in pixels (e.g., 8.0f)
   * @return Bitmap of the pill/lozenge label
   */
  private Bitmap createPillLabelBitmap(
      String text,
      String backgroundColor,
      String textColor,
      float textSize,
      float paddingHorizontal,
      float paddingVertical,
      float cornerRadius) {
    
    try {
      // Create Paint for text measurement
      Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      textPaint.setTextSize(textSize * density);
      textPaint.setColor(android.graphics.Color.parseColor(textColor));
      textPaint.setTextAlign(Paint.Align.LEFT);
      textPaint.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
      
      // Measure text dimensions
      Paint.FontMetrics fontMetrics = textPaint.getFontMetrics();
      float textWidth = textPaint.measureText(text);
      float textHeight = fontMetrics.descent - fontMetrics.ascent;
      
      // Calculate bitmap dimensions with padding
      float densityFactor = density;
      float scaledPaddingH = paddingHorizontal * densityFactor;
      float scaledPaddingV = paddingVertical * densityFactor;
      float scaledCornerRadius = cornerRadius * densityFactor;
      
      int bitmapWidth = (int) Math.ceil(textWidth + (2 * scaledPaddingH));
      int bitmapHeight = (int) Math.ceil(textHeight + (2 * scaledPaddingV));
      
      // Create bitmap and canvas
      Bitmap bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      // Draw rounded rectangle background (pill/lozenge shape)
      Paint backgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      backgroundPaint.setColor(android.graphics.Color.parseColor(backgroundColor));
      backgroundPaint.setStyle(Paint.Style.FILL);
      
      RectF rect = new RectF(0, 0, bitmapWidth, bitmapHeight);
      canvas.drawRoundRect(rect, scaledCornerRadius, scaledCornerRadius, backgroundPaint);
      
      // Draw optional border/stroke for better visibility
      Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      borderPaint.setColor(android.graphics.Color.parseColor(backgroundColor));
      borderPaint.setStyle(Paint.Style.STROKE);
      borderPaint.setStrokeWidth(2.0f * densityFactor);
      canvas.drawRoundRect(rect, scaledCornerRadius, scaledCornerRadius, borderPaint);
      
      // Draw text centered in the pill
      float textX = scaledPaddingH;
      float textY = scaledPaddingV - fontMetrics.ascent;
      canvas.drawText(text, textX, textY, textPaint);
      
      Log.d(TAG, String.format("createPillLabelBitmap: Created pill label '%s' (%dx%d px)", 
          text, bitmapWidth, bitmapHeight));
      
      return bitmap;
    } catch (Exception e) {
      Log.e(TAG, "createPillLabelBitmap: Error creating pill label: " + e.getMessage(), e);
      // Return a simple fallback bitmap
      Bitmap fallback = Bitmap.createBitmap(100, 40, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(fallback);
      Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
      paint.setColor(0xFF0066FF);
      canvas.drawRect(0, 0, 100, 40, paint);
      return fallback;
    }
  }

  /**
   * Creates a circular label bitmap with text curved around the circle's circumference.
   * This method generates aviation-style circular labels with:
   * - Circle outline (customizable color and stroke width)
   * - Pill-shaped background arc following the circle contour
   * - Text curved along the pill background (top or bottom arc)
   * - Configurable radius and text size
   * 
   * Use case: Circular airspace boundaries with readable labels following the contour.
   * 
   * @param text The text to display along the circle
   * @param radius Circle radius in dp (e.g., 30.0f)
   * @param circleColor Hex color string for circle outline (e.g., "#0066FF")
   * @param circleStrokeWidth Circle stroke width in dp (e.g., 2.0f)
   * @param textColor Hex color string for text (e.g., "#FFFFFF")
   * @param textSize Text size in pixels (e.g., 14.0f)
   * @param topArc If true, text is on top arc; if false, text is on bottom arc
   * @param roundedEdges If true, pill edges are rounded; if false, edges are straight (butt cap)
   * @return Bitmap of the circular label with pill background
   */
  private Bitmap createCircleLabelBitmap(
      String text,
      float radius,
      String circleColor,
      float circleStrokeWidth,
      String textColor,
      float textSize,
      boolean topArc,
      boolean roundedEdges) {
    
    try {
      // Scale parameters by density first
      float scaledRadius = radius * density;
      float scaledStrokeWidth = circleStrokeWidth * density;
      float scaledTextSize = textSize * density;
      
      // Create Paint for text measurement
      Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      textPaint.setTextSize(scaledTextSize);
      textPaint.setColor(android.graphics.Color.parseColor(textColor));
      textPaint.setTextAlign(Paint.Align.CENTER);
      textPaint.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
      
      // Measure text height for pill background sizing
      Paint.FontMetrics fontMetrics = textPaint.getFontMetrics();
      float textHeight = fontMetrics.descent - fontMetrics.ascent;
      
      // Calculate pill background stroke width (text height + padding)
      float pillPadding = 8 * density; // 8dp padding
      float pillStrokeWidth = textHeight + (pillPadding * 2);
      
      // Calculate bitmap dimensions (circle diameter + padding for pill)
      int bitmapSize = (int) Math.ceil((scaledRadius * 2) + (pillStrokeWidth * 2) + 40 * density);
      
      // Create bitmap and canvas
      Bitmap bitmap = Bitmap.createBitmap(bitmapSize, bitmapSize, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(bitmap);
      
      // Calculate center point
      float centerX = bitmapSize / 2f;
      float centerY = bitmapSize / 2f;
      
      // Draw circle outline
      Paint circlePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      circlePaint.setColor(android.graphics.Color.parseColor(circleColor));
      circlePaint.setStyle(Paint.Style.STROKE);
      circlePaint.setStrokeWidth(scaledStrokeWidth);
      canvas.drawCircle(centerX, centerY, scaledRadius, circlePaint);
      
      // Calculate text radius (offset from circle)
      float textRadius = scaledRadius + scaledStrokeWidth + pillStrokeWidth / 2 + 5 * density;
      
      // Create path for the pill background arc
      Path pillPath = new Path();
      
      // Measure text width to calculate arc sweep angle
      float textWidth = textPaint.measureText(text);
      // Calculate arc length needed for text
      float arcLength = textWidth * 1.1f; // 10% extra for spacing
      // Convert arc length to degrees: arcLength = radius × angle_in_radians
      float sweepAngle = (float) Math.toDegrees(arcLength / textRadius);
      // Limit sweep angle to reasonable range
      sweepAngle = Math.min(sweepAngle, 160f);
      
      float startAngle;
      if (topArc) {
        // Center the arc on top (270° = top of circle)
        startAngle = 270f - (sweepAngle / 2f);
      } else {
        // Center the arc on bottom (90° = bottom of circle)
        startAngle = 90f - (sweepAngle / 2f);
      }
      
      pillPath.addArc(
          centerX - textRadius,
          centerY - textRadius,
          centerX + textRadius,
          centerY + textRadius,
          startAngle,
          sweepAngle
      );
      
      // Draw pill-shaped background (thick arc with configurable cap style)
      Paint pillBackgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      pillBackgroundPaint.setColor(android.graphics.Color.parseColor(circleColor));
      pillBackgroundPaint.setStyle(Paint.Style.STROKE);
      pillBackgroundPaint.setStrokeWidth(pillStrokeWidth);
      // Use ROUND for pill-shaped ends, BUTT for straight edges
      pillBackgroundPaint.setStrokeCap(roundedEdges ? Paint.Cap.ROUND : Paint.Cap.BUTT);
      canvas.drawPath(pillPath, pillBackgroundPaint);
      
      // Draw border/outline for pill (optional, for better definition)
      Paint pillBorderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
      pillBorderPaint.setColor(android.graphics.Color.parseColor(circleColor));
      pillBorderPaint.setStyle(Paint.Style.STROKE);
      pillBorderPaint.setStrokeWidth(2 * density);
      pillBorderPaint.setStrokeCap(roundedEdges ? Paint.Cap.ROUND : Paint.Cap.BUTT);
      canvas.drawPath(pillPath, pillBorderPaint);
      
      // Draw text along the same path
      canvas.drawTextOnPath(text, pillPath, 0, textHeight / 4, textPaint);
      
      Log.d(TAG, String.format("createCircleLabelBitmap: Created circle label with pill background '%s' (%dx%d px, radius=%.1f, pillWidth=%.1f)", 
          text, bitmapSize, bitmapSize, scaledRadius, pillStrokeWidth));
      
      return bitmap;
    } catch (Exception e) {
      Log.e(TAG, "createCircleLabelBitmap: Error creating circle label: " + e.getMessage(), e);
      // Return a simple fallback bitmap
      Bitmap fallback = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888);
      Canvas canvas = new Canvas(fallback);
      Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
      paint.setColor(0xFF0066FF);
      paint.setStyle(Paint.Style.STROKE);
      paint.setStrokeWidth(4);
      canvas.drawCircle(50, 50, 40, paint);
      return fallback;
    }
  }

  /**
   * Helper method to load all colored arrow PNG assets and create rotated variants.
   * Creates both up and down arrow versions for all proximity colors (red, yellow, blue, green).
   */
  private void loadColoredArrowPngAssets() {
  Log.d(TAG, "Loading colored arrow PNG assets for red, yellow, and green proximity colors");
    
  // Define supported arrow color variants
  String[] arrowColors = {"red", "yellow", "green"};
  String[] arrowAssetPaths = {
    "arrow_red.png",
    "arrow_yellow.png", 
    "arrow_green.png"
  };
    
    try {
      for (int i = 0; i < arrowColors.length; i++) {
        String color = arrowColors[i];
        String assetPath = arrowAssetPaths[i];
        
        // Load the base arrow bitmap for this color
        Bitmap baseBitmap = loadPngAsset(assetPath);
        
        if (baseBitmap != null) {
          // Create up arrow (use bitmap as-is)
          String upArrowId = "arrow-" + color + "-up";
          if (style != null && style.getImage(upArrowId) == null) {
            style.addImage(upArrowId, baseBitmap, false); // false = not SDF to preserve colors
            Log.d(TAG, "Added " + color + " up arrow icon: " + upArrowId);
          }
          
    // Create down arrow (rotate 180 degrees)
    String downArrowId = "arrow-" + color + "-down";
          if (style != null && style.getImage(downArrowId) == null) {
            Bitmap downBitmap = rotateBitmap(baseBitmap, 180);
            style.addImage(downArrowId, downBitmap, false); // false = not SDF to preserve colors
            Log.d(TAG, "Added " + color + " down arrow icon: " + downArrowId);
          }
        } else {
          Log.w(TAG, "Failed to load arrow asset: " + assetPath + ", skipping " + color + " arrows");
        }
      }
      
      Log.d(TAG, "Successfully loaded all colored arrow PNG assets with rotation");
    } catch (Exception e) {
      Log.e(TAG, "Error loading colored arrow PNG assets: " + e.getMessage(), e);
      throw new RuntimeException("Failed to load colored arrow PNG assets", e);
    }
  }

  /**
   * Helper method to load multiple PNG assets and register them with MapLibre style.
   */
  private void loadMultiplePngAssets(String[] assetPaths, String[] iconIds) {
    Log.d(TAG, "Loading multiple PNG assets: " + java.util.Arrays.toString(assetPaths));
    
    if (assetPaths.length != iconIds.length) {
      throw new IllegalArgumentException("Asset paths and icon IDs arrays must have the same length");
    }
    
    for (int i = 0; i < assetPaths.length; i++) {
      String assetPath = assetPaths[i];
      String iconId = iconIds[i];
      
      try {
        // Check if icon already exists
        if (style != null && style.getImage(iconId) != null) {
          Log.v(TAG, "PNG icon already exists: " + iconId);
          continue;
        }
        
        // Load PNG asset
        Bitmap bitmap = loadPngAsset(assetPath);
        
        if (bitmap != null && style != null) {
          // Register with MapLibre style (false = not SDF mode to preserve colors)
          style.addImage(iconId, bitmap, false);
          Log.d(TAG, "loadMultiplePngAssets: Successfully registered PNG icon: " + iconId + " from " + assetPath + " (" + bitmap.getWidth() + "x" + bitmap.getHeight() + ", SDF=false)");
          
          // Verify the icon was actually added
          android.graphics.Bitmap testImage = style.getImage(iconId);
          if (testImage != null) {
            Log.d(TAG, "loadMultiplePngAssets: Verified icon " + iconId + " is registered in style");
          } else {
            Log.e(TAG, "loadMultiplePngAssets: Failed to verify icon " + iconId + " in style!");
          }
        } else {
          Log.e(TAG, "Failed to register PNG icon: " + iconId + " from " + assetPath);
          throw new RuntimeException("Failed to load PNG asset: " + assetPath);
        }
      } catch (Exception e) {
        Log.e(TAG, "Error loading PNG asset " + assetPath + ": " + e.getMessage(), e);
        throw new RuntimeException("Failed to load PNG asset: " + assetPath, e);
      }
    }
    
    Log.d(TAG, "Successfully loaded all PNG assets");
  }

  /**
   * Adds rotatable symbol layers using PNG assets with dynamic swapping.
   * This method creates aviation symbols with:
  * - Dynamic PNG swapping based on proximity distance (for traffic icons)
  * - Center aircraft symbol that can rotate freely
  * - Right-side arrow symbol for altitude indication
  * 
  * Aviation TCAS color coding:
  * - Red: Critical (<2nm)
  * - Yellow: Warning (2-5nm)
  * - Green: Safe (>5nm)
   */
  public void addRotatableSymbolPngLayers(
      String sourceId,
      String baseLayerId,
      String belowLayerId,
      String aircraftIconPath,
      String arrowIconPath,
      double aircraftIconSize,
      double arrowIconSize,
      boolean enableInteraction,
      Map<String, Object> config) {
    
    try {
      Log.d(TAG, "Adding rotatable symbol PNG layers with base ID: " + baseLayerId);
      Log.d(TAG, "Aircraft icon: " + aircraftIconPath + ", Arrow icon: " + arrowIconPath);
      
      // Extract configuration
      if (config == null) {
        config = new HashMap<>();
      }
      
      // Layer positioning configuration
      double topLabelOffset = ((Number) config.getOrDefault("topLabelOffset", -2.5)).doubleValue();
      double bottomLabelOffset = ((Number) config.getOrDefault("bottomLabelOffset", 2.5)).doubleValue();
      double arrowOffsetX = ((Number) config.getOrDefault("arrowOffsetX", 25.0)).doubleValue();
      
      // Define PNG assets for traffic icons (4 colored variants)
    String[] trafficAssetPaths = {
      "traffic_red.png",
      "traffic_yellow.png",
      "traffic_green.png"
    };
      
    String[] trafficIconIds = {
      "aircraft-red",
      "aircraft-yellow",
      "aircraft-green"
    };
      
      // Load PNG assets for traffic icons
      loadMultiplePngAssets(trafficAssetPaths, trafficIconIds);
      
      // Load arrow PNG assets (all color variants for both up and down directions)
      loadColoredArrowPngAssets();
      
      // Load the primary aircraft icon (for fallback)
      String[] primaryAssetPaths = { aircraftIconPath };
      String[] primaryIconIds = { "aircraft-primary" };
      loadMultiplePngAssets(primaryAssetPaths, primaryIconIds);
      
      // 1. Add aircraft layer (center, rotatable) with dynamic PNG swapping
      String aircraftLayerId = baseLayerId + "-aircraft";
      SymbolLayer aircraftLayer = new SymbolLayer(aircraftLayerId, sourceId);
      aircraftLayer.setProperties(
          // Dynamic icon selection based on proximity distance
      PropertyFactory.iconImage(
        Expression.switchCase(
          Expression.lt(Expression.get("proximityDistance"), Expression.literal(2.0)),
          Expression.literal("aircraft-red"),
          Expression.lt(Expression.get("proximityDistance"), Expression.literal(5.0)),
          Expression.literal("aircraft-yellow"),
          Expression.literal("aircraft-green")
        )
      ),
          PropertyFactory.iconSize(((Number) aircraftIconSize).floatValue()),
          PropertyFactory.iconRotate(Expression.get("rotation")),
          PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP), // Rotates with map
          PropertyFactory.iconAllowOverlap(true),
          PropertyFactory.iconIgnorePlacement(true)
      );
      
      // 2. Add top label layer (viewport aligned, stays horizontal)
      String topLabelLayerId = baseLayerId + "-top-label";
      SymbolLayer topLabelLayer = new SymbolLayer(topLabelLayerId, sourceId);
      topLabelLayer.setProperties(
          PropertyFactory.textField(Expression.get("topLabel")),
          PropertyFactory.textFont(new String[]{"Open Sans Regular", "Arial Unicode MS Regular"}),
          PropertyFactory.textSize(Expression.get("labelSize")),
          PropertyFactory.textColor(Expression.get("labelColor")),
          PropertyFactory.textHaloColor("#FFFFFF"),
          PropertyFactory.textHaloWidth(2.0f),
          PropertyFactory.textOffset(new Float[]{0.0f, (float) topLabelOffset}),
          PropertyFactory.textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_VIEWPORT), // Always horizontal
          PropertyFactory.textAllowOverlap(true),
          PropertyFactory.textIgnorePlacement(true)
      );
      
      // 3. Add bottom label layer (viewport aligned, stays horizontal)
      String bottomLabelLayerId = baseLayerId + "-bottom-label";
      SymbolLayer bottomLabelLayer = new SymbolLayer(bottomLabelLayerId, sourceId);
      bottomLabelLayer.setProperties(
          PropertyFactory.textField(Expression.get("bottomLabel")),
          PropertyFactory.textFont(new String[]{"Open Sans Regular", "Arial Unicode MS Regular"}),
          PropertyFactory.textSize(Expression.get("labelSize")),
          PropertyFactory.textColor(Expression.get("labelColor")),
          PropertyFactory.textHaloColor("#FFFFFF"),
          PropertyFactory.textHaloWidth(2.0f),
          PropertyFactory.textOffset(new Float[]{0.0f, (float) bottomLabelOffset}),
          PropertyFactory.textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_VIEWPORT), // Always horizontal
          PropertyFactory.textAllowOverlap(true),
          PropertyFactory.textIgnorePlacement(true)
      );
      
      // 4. Add arrow layer (right side, viewport aligned) with dynamic color matching aircraft
      String arrowLayerId = baseLayerId + "-arrow";
      SymbolLayer arrowLayer = new SymbolLayer(arrowLayerId, sourceId);
      arrowLayer.setProperties(
          // Use conditional arrow color and direction based on proximity distance and climbing state
      PropertyFactory.iconImage(
        Expression.switchCase(
          // First determine color based on proximity (same logic as aircraft)
          Expression.lt(Expression.get("proximityDistance"), Expression.literal(2.0)),
          // Red arrows for critical proximity (<2nm)
          Expression.switchCase(
            Expression.get("isClimbing"),
            Expression.literal("arrow-red-up"),
            Expression.literal("arrow-red-down")
          ),
          Expression.lt(Expression.get("proximityDistance"), Expression.literal(5.0)),
          // Yellow arrows for warning proximity (2-5nm)
          Expression.switchCase(
            Expression.get("isClimbing"),
            Expression.literal("arrow-yellow-up"),
            Expression.literal("arrow-yellow-down")
          ),
          // Green arrows for safe distance (>5nm)
          Expression.switchCase(
            Expression.get("isClimbing"),
            Expression.literal("arrow-green-up"),
            Expression.literal("arrow-green-down")
          )
        )
      ),
          PropertyFactory.iconSize(((Number) arrowIconSize).floatValue()),
          PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_VIEWPORT), // Always upright
          PropertyFactory.iconOffset(new Float[]{(float) arrowOffsetX, 0.0f}), // Fixed to right side
          PropertyFactory.iconAllowOverlap(true),
          PropertyFactory.iconIgnorePlacement(true)
      );
      
      // Add layers to style in proper order (aircraft first, then text on top, arrow last)
      if (belowLayerId != null) {
        style.addLayerBelow(aircraftLayer, belowLayerId);
        style.addLayerAbove(topLabelLayer, aircraftLayerId);
        style.addLayerAbove(bottomLabelLayer, topLabelLayerId);
        style.addLayerAbove(arrowLayer, bottomLabelLayerId);
      } else {
        style.addLayer(aircraftLayer);
        style.addLayer(topLabelLayer);
        style.addLayer(bottomLabelLayer);
        style.addLayer(arrowLayer);
      }
      
      // Enable interaction if requested
      if (enableInteraction) {
        interactiveFeatureLayerIds.add(aircraftLayerId);
        interactiveFeatureLayerIds.add(topLabelLayerId);
        interactiveFeatureLayerIds.add(bottomLabelLayerId);
        interactiveFeatureLayerIds.add(arrowLayerId);
      }
      
      Log.d(TAG, "Successfully added rotatable symbol PNG layers: " + aircraftLayerId + ", " + topLabelLayerId + ", " + bottomLabelLayerId + ", " + arrowLayerId);
      Log.d(TAG, "Aircraft icon size: " + aircraftIconSize + ", Arrow icon size: " + arrowIconSize);
      Log.d(TAG, "Arrow offset X: " + arrowOffsetX);
      
    } catch (Exception e) {
      String errorMessage = "Failed to add rotatable symbol PNG layers '" + baseLayerId + "': " + e.getMessage();
      Log.e(TAG, errorMessage, e);
      throw new RuntimeException(errorMessage, e);
    }
  }

  /**
   * Adds a multi-layer rotatable symbol to the map.
   * Creates 4 synchronized layers: triangle, top label, bottom label, and side arrow.
   * 
   * @param sourceId GeoJSON source containing the symbol data
   * @param baseLayerId Base layer ID (will append suffixes for each layer)
   * @param belowLayerId Optional layer to place below
   * @param properties Symbol properties including rotation, labels, etc.
   * @param enableInteraction Whether to enable tap interaction
   */
  public void addRotatableSymbolLayers(
      String sourceId,
      String baseLayerId,
      String belowLayerId,
      Map<String, Object> properties,
      boolean enableInteraction) {
    
    try {
      Log.d(TAG, "Adding rotatable symbol layers with base ID: " + baseLayerId);
      
      // Ensure required icons exist
      ensureTriangleIconExists();
      ensureArrowIconsExist();
      
      // Extract configuration from properties
      Map<String, Object> config = (Map<String, Object>) properties.get("config");
      if (config == null) {
        config = new HashMap<>();
      }
      
      // Layer positioning configuration
      double topLabelOffset = ((Number) config.getOrDefault("topLabelOffset", -2.5)).doubleValue();
      double bottomLabelOffset = ((Number) config.getOrDefault("bottomLabelOffset", 2.5)).doubleValue();
      double arrowOffsetX = ((Number) config.getOrDefault("arrowOffsetX", 20.0)).doubleValue();
      
      // 1. Add triangle layer (rotatable with map)
      String triangleLayerId = baseLayerId + "-triangle";
      SymbolLayer triangleLayer = new SymbolLayer(triangleLayerId, sourceId);
      triangleLayer.setProperties(
          PropertyFactory.iconImage("maplibre-triangle-icon"),
          PropertyFactory.iconSize(Expression.get("triangleSize")),
          PropertyFactory.iconRotate(Expression.get("rotation")),
          PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP), // Rotates with map
          PropertyFactory.iconAllowOverlap(true),
          PropertyFactory.iconIgnorePlacement(true),
          PropertyFactory.iconOpacity(Expression.get("triangleOpacity"))
      );
      
      // 2. Add top label layer (viewport aligned, stays horizontal)
      String topLabelLayerId = baseLayerId + "-top-label";
      SymbolLayer topLabelLayer = new SymbolLayer(topLabelLayerId, sourceId);
      topLabelLayer.setProperties(
          PropertyFactory.textField(Expression.get("topLabel")),
          PropertyFactory.textFont(new String[]{"Open Sans Regular", "Arial Unicode MS Regular"}), // Changed to more basic fonts
          PropertyFactory.textSize(Expression.get("labelSize")),
          PropertyFactory.textColor(Expression.get("labelColor")),
          PropertyFactory.textHaloColor("#FFFFFF"),
          PropertyFactory.textHaloWidth(2.0f),
          PropertyFactory.textOffset(new Float[]{0.0f, (float) topLabelOffset}),
          PropertyFactory.textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_VIEWPORT), // Always horizontal
          PropertyFactory.textAllowOverlap(true),
          PropertyFactory.textIgnorePlacement(true)
      );
      
      // 3. Add bottom label layer (viewport aligned, stays horizontal)
      String bottomLabelLayerId = baseLayerId + "-bottom-label";
      SymbolLayer bottomLabelLayer = new SymbolLayer(bottomLabelLayerId, sourceId);
      bottomLabelLayer.setProperties(
          PropertyFactory.textField(Expression.get("bottomLabel")),
          PropertyFactory.textFont(new String[]{"Open Sans Regular", "Arial Unicode MS Regular"}), // Changed to more basic fonts
          PropertyFactory.textSize(Expression.get("labelSize")),
          PropertyFactory.textColor(Expression.get("labelColor")),
          PropertyFactory.textHaloColor("#FFFFFF"),
          PropertyFactory.textHaloWidth(2.0f),
          PropertyFactory.textOffset(new Float[]{0.0f, (float) bottomLabelOffset}),
          PropertyFactory.textRotationAlignment(Property.TEXT_ROTATION_ALIGNMENT_VIEWPORT), // Always horizontal
          PropertyFactory.textAllowOverlap(true),
          PropertyFactory.textIgnorePlacement(true)
      );
      
      // 4. Add arrow layer (viewport aligned, fixed to right side)
      String arrowLayerId = baseLayerId + "-arrow";
      SymbolLayer arrowLayer = new SymbolLayer(arrowLayerId, sourceId);
      arrowLayer.setProperties(
          PropertyFactory.iconImage(
              Expression.switchCase(
                  Expression.get("isClimbing"),
                  Expression.literal("maplibre-arrow-up-icon"),
                  Expression.literal("maplibre-arrow-down-icon")
              )
          ),
          PropertyFactory.iconSize(Expression.get("arrowSize")),
          PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_VIEWPORT), // Always upright
          PropertyFactory.iconOffset(new Float[]{(float) arrowOffsetX, 0.0f}), // Fixed to right side
          PropertyFactory.iconAllowOverlap(true),
          PropertyFactory.iconIgnorePlacement(true),
          PropertyFactory.iconOpacity(Expression.get("arrowOpacity"))
      );
      
      // Add layers to style in proper order (triangle first, then text on top, arrow last)
      if (belowLayerId != null) {
        style.addLayerBelow(triangleLayer, belowLayerId);
        style.addLayerAbove(topLabelLayer, triangleLayerId);
        style.addLayerAbove(bottomLabelLayer, topLabelLayerId);
        style.addLayerAbove(arrowLayer, bottomLabelLayerId);
      } else {
        style.addLayer(triangleLayer);
        style.addLayer(topLabelLayer);
        style.addLayer(bottomLabelLayer);
        style.addLayer(arrowLayer);
      }
      
      // Enable interaction if requested
      if (enableInteraction) {
        interactiveFeatureLayerIds.add(triangleLayerId);
        interactiveFeatureLayerIds.add(topLabelLayerId);
        interactiveFeatureLayerIds.add(bottomLabelLayerId);
        interactiveFeatureLayerIds.add(arrowLayerId);
      }
      
      Log.d(TAG, "Successfully added rotatable symbol layers: " + triangleLayerId + ", " + topLabelLayerId + ", " + bottomLabelLayerId + ", " + arrowLayerId);
      
    } catch (Exception e) {
      String errorMessage = "Failed to add rotatable symbol layers '" + baseLayerId + "': " + e.getMessage();
      Log.e(TAG, errorMessage, e);
      throw new RuntimeException(errorMessage, e);
    }
  }

  /**
   * Listener for polyline gesture events.
   */
  private class PolylineGestureListener implements PolylineGestureDetector.OnPolylineGestureListener {
    
    @Override
    public void onPolylineBroken(@NonNull String lineId, @NonNull LatLng breakPoint, 
                                @NonNull List<LatLng> segment1, @NonNull List<LatLng> segment2) {
      Log.d(TAG, "Polyline broken: " + lineId + " at " + breakPoint);
      
      try {
        // Show break point marker
            if (polylineRenderer != null) {
              polylineRenderer.showBreakPoint(
                  lineId, Math.max(1, segment1.size() - 1), breakPoint);
        }
        
        // Convert LatLng lists to coordinate arrays for Flutter
        List<List<Double>> segment1Coords = convertLatLngListToCoordinates(segment1);
        List<List<Double>> segment2Coords = convertLatLngListToCoordinates(segment2);
        
        // Send callback to Flutter
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("lineId", lineId);
        arguments.put("segment1", segment1Coords);
        arguments.put("segment2", segment2Coords);
        
        methodChannel.invokeMethod("polylineEditing#onBroken", arguments);
      } catch (Exception e) {
        Log.e(TAG, "Error in onPolylineBroken callback: " + e.getMessage(), e);
        // Send error callback instead
        onPolylineEditingError(lineId, "Failed to process polyline break: " + e.getMessage());
      }
    }
    
    @Override
    public void onPolylineModified(@NonNull String lineId, @NonNull List<LatLng> newCoordinates) {
      Log.d(TAG, "Polyline modified: " + lineId);
      
            if (polylineRenderer != null && polylineBreakPointSystem != null) {
              polylineRenderer.syncBreakPoints(
                  lineId,
                  newCoordinates,
                  polylineBreakPointSystem.getLockedPointIndices(lineId));
            }
      
      // Convert LatLng list to coordinate array for Flutter
      List<List<Double>> coordinates = convertLatLngListToCoordinates(newCoordinates);
      
      // Send callback to Flutter
      Map<String, Object> arguments = new HashMap<>();
      arguments.put("lineId", lineId);
      arguments.put("coordinates", coordinates);
      
      methodChannel.invokeMethod("polylineEditing#onModified", arguments);
    }

    @Override
    public void onPolylineEditCompleted(
        @NonNull String lineId,
        @NonNull List<LatLng> newCoordinates,
        int pointIndex,
        boolean inserted) {
      Map<String, Object> arguments = new HashMap<>();
      arguments.put("lineId", lineId);
      arguments.put("coordinates", convertLatLngListToCoordinates(newCoordinates));
      arguments.put("pointIndex", pointIndex);
      arguments.put("inserted", inserted);
      methodChannel.invokeMethod("polylineEditing#onCompleted", arguments);
    }

    @Override
    public void onPolylinePointDeleted(
        @NonNull String lineId,
        @NonNull List<LatLng> newCoordinates,
        int pointIndex,
        @NonNull LatLng deletedCoordinate) {
      Map<String, Object> arguments = new HashMap<>();
      arguments.put("lineId", lineId);
      arguments.put("coordinates", convertLatLngListToCoordinates(newCoordinates));
      arguments.put("pointIndex", pointIndex);
      arguments.put(
          "deletedCoordinate",
          Arrays.asList(deletedCoordinate.getLatitude(), deletedCoordinate.getLongitude()));
      methodChannel.invokeMethod("polylineEditing#onPointDeleted", arguments);
    }

    @Override
    public void onPolylineDeleteZoneChanged(boolean visible, boolean armed) {
      setPolylineDeleteZoneVisible(visible, armed);
    }
    
    @Override
    public void onPolylineEditingError(@NonNull String lineId, @NonNull String error) {
      Log.e(TAG, "Polyline editing error for " + lineId + ": " + error);
      
      // Hide visual feedback elements on error
      if (polylineRenderer != null) {
        polylineRenderer.hideBreakPoint(lineId);
      }
      
      // Send error callback to Flutter
      Map<String, Object> arguments = new HashMap<>();
      arguments.put("lineId", lineId);
      arguments.put("error", error);
      
      methodChannel.invokeMethod("polylineEditing#onError", arguments);
    }
  }

  // =====================================
  // Old native LERC terrain code removed - HTTP LERC and ArcGIS features are Dart-based
  // =====================================

}
