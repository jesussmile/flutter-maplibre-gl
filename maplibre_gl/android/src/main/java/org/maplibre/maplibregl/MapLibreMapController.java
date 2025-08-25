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
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PointF;
import android.graphics.RectF;
import android.location.Location;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.TextureView;
import android.view.View;
import android.widget.FrameLayout;
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

// Native LERC Canvas imports
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

  private LatLng dragOrigin;
  private LatLng dragPrevious;

  private Set<String> interactiveFeatureLayerIds;
  private Map<String, FeatureCollection> addedFeaturesByLayer;
  private Map<String, ImageOverlayControlsView> imageOverlayControls;

  private LatLngBounds bounds = null;
  private boolean twoFingerHoldGestureEnabled = false;
  private TwoFingerHoldGestureDetector twoFingerHoldGestureDetector;
  private NativeMeasurementDetector nativeMeasurementDetector;
  
  // NEW: High-performance terrain data manager with native buffering
  private NativeTerrainManagerIntegration terrainManagerIntegration;
  
  // Package-private accessors for terrain manager integration
  MapLibreMap getMapLibreMap() {
    return mapLibreMap;
  }
  
  Style getStyle() {
    return style;
  }
  
  // DEPRECATED: Legacy native LERC Canvas Layer fields (kept for backwards compatibility)
  private Map<String, Object> nativeLercCanvasLayers = new ConcurrentHashMap<>();
  private MethodChannel nativeLercMethodChannel;
  
  // DEPRECATED: Legacy performance optimization caches (superseded by NativeTerrainDataManager)
  private final Map<String, double[]> elevationTileCache = new ConcurrentHashMap<>();
  private final Map<String, Bitmap> coloredBitmapCache = new ConcurrentHashMap<>();
  private final Map<String, Integer> cacheBustingVersions = new ConcurrentHashMap<>();
  private final Map<String, android.os.Handler> debounceHandlers = new ConcurrentHashMap<>();
  
  // DEPRECATED: Pre-computed color lookup table (superseded by optimized bitmap creation)
  private static int[][] colorLUT = null;
  
  // DEPRECATED: Cache management constants (superseded by NativeTerrainDataManager constants)
  private static final int MAX_ELEVATION_CACHE_SIZE = 100;
  private static final int MAX_BITMAP_CACHE_SIZE = 50;
  private static final int DEBOUNCE_DELAY_MS = 25; // Short debounce for smooth updates
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
      boolean dragEnabled) {
    MapLibreUtils.getMapLibre(context);
    this.id = id;
    this.context = context;
    this.dragEnabled = dragEnabled;
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
    
    // NEW: Initialize high-performance terrain data manager integration
    terrainManagerIntegration = new NativeTerrainManagerIntegration(this);
    
    // DEPRECATED: Legacy native LERC canvas method channel (kept for backwards compatibility)
    nativeLercMethodChannel = new MethodChannel(messenger, "flight_canvas/native_lerc");
    nativeLercMethodChannel.setMethodCallHandler(new MethodChannel.MethodCallHandler() {
      @Override
      public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        // NEW: Route to high-performance terrain manager first
        if (terrainManagerIntegration != null) {
          switch (call.method) {
            case "initialize":
              terrainManagerIntegration.handleTerrainInitialize(call, result);
              return;
            case "updateAltitudes":
              terrainManagerIntegration.handleTerrainUpdateAltitudes(call, result);
              return;
            case "dispose":
              terrainManagerIntegration.handleTerrainDispose(call, result);
              return;
          }
        }
        
        // Fallback to legacy handler for backwards compatibility
        handleNativeLercMethodCall(call, result);
      }
    });
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

    // NEW: Initialize high-performance terrain data manager integration
    if (terrainManagerIntegration != null) {
      terrainManagerIntegration.initializeWithMap(mapLibreMap);
    }

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
              // Handle native measurement detection first - if it consumes the event, don't process other gestures
              if (nativeMeasurementDetector != null) {
                boolean measurementHandled = nativeMeasurementDetector.onTouchEvent(event);
                if (measurementHandled) {
                  return true; // Measurement detector consumed the event - prevent map interaction
                }
              }
              
              androidGesturesManager.onTouchEvent(event);
              
              // Handle two-finger hold gesture detection
              if (twoFingerHoldGestureDetector != null) {
                twoFingerHoldGestureDetector.onTouchEvent(event);
              }
              
              // Handle polyline editing gestures
              if (polylineGestureDetector != null) {
                boolean polylineHandled = polylineGestureDetector.onTouchEvent(event);
                if (polylineHandled) {
                  return true; // Polyline gesture consumed the event
                }
              }

              return draggedFeature != null;
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
    GeoJsonSource geoJsonSource = new GeoJsonSource(sourceName, featureCollection);
    addedFeaturesByLayer.put(sourceName, featureCollection);

    style.addSource(geoJsonSource);
  }

  private void setGeoJsonSource(String sourceName, String geojson) {
    FeatureCollection featureCollection = FeatureCollection.fromJson(geojson);
    GeoJsonSource geoJsonSource = style.getSourceAs(sourceName);
    addedFeaturesByLayer.put(sourceName, featureCollection);

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
    
    // Then check regular layers (symbols, etc.)
    for (Layer layer : layers) {
      if (layer instanceof SymbolLayer) {
        final List<Feature> features =
            mapLibreMap.queryRenderedFeatures(in, layer.getId());
        if (!features.isEmpty()) {
          String layerId = interactiveFeatureLayerIds.contains(layer.getId()) ? layer.getId() : null;
          return new Pair<>(features.get(0), layerId);
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
          }
          style.addImage(
              call.argument("name"),
              BitmapFactory.decodeByteArray(call.argument("bytes"), 0, call.argument("length")),
              call.argument("sdf"));
          result.success(null);
          break;
        }
      case "style#addImageSource":
        {
          if (style == null) {
            result.error(
                "STYLE IS NULL",
                "The style is null. Has onStyleLoaded() already been invoked?",
                null);
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
        case "style#getLayerIds":
        {
          if (style == null) {
            result.error(
                    "STYLE IS NULL",
                    "The style is null. Has onStyleLoaded() already been invoked?",
                    null);
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
      case "map#enableTwoFingerHoldGesture":
        {
          final boolean enabled = call.argument("enabled");
          enableTwoFingerHoldGestureDetection(enabled);
          result.success(null);
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
      // Native LERC Canvas Layer Methods
      case "nativeLercCanvas#initialize":
        {
          handleNativeLercCanvasInitialize(call, result);
          break;
        }
      case "nativeLercCanvas#updateAltitudes":
        {
          handleNativeLercCanvasUpdateAltitudes(call, result);
          break;
        }
      case "nativeLercCanvas#dispose":
        {
          handleNativeLercCanvasDispose(call, result);
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
    
    // NEW: Update high-performance terrain manager integration for viewport changes
    if (terrainManagerIntegration != null) {
      terrainManagerIntegration.updateViewport(mapLibreMap.getCameraPosition());
    }
    
    // DEPRECATED: Legacy native LERC terrain tiles optimization (kept for backwards compatibility)
    updateNativeLercTilesForCurrentViewOptimized();
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
    } else {
      methodChannel.invokeMethod("map#onMapClick", arguments);
    }
    return true;
  }

  @Override
  public boolean onMapLongClick(@NonNull LatLng point) {
    PointF pointf = mapLibreMap.getProjection().toScreenLocation(point);
    final Map<String, Object> arguments = new HashMap<>(5);
    arguments.put("x", pointf.x);
    arguments.put("y", pointf.y);
    arguments.put("lng", point.getLongitude());
    arguments.put("lat", point.getLatitude());
    methodChannel.invokeMethod("map#onMapLongClick", arguments);
    return true;
  }

  private void enableTwoFingerHoldGestureDetection(boolean enabled) {
    this.twoFingerHoldGestureEnabled = enabled;
    
    if (enabled) {
      if (twoFingerHoldGestureDetector == null && mapLibreMap != null) {
        twoFingerHoldGestureDetector = new TwoFingerHoldGestureDetector(
          mapLibreMap,
          new TwoFingerHoldGestureDetector.OnTwoFingerHoldGestureListener() {
            @Override
            public void onTwoFingerHoldGesture(PointF point, LatLng latLng, long duration) {
              final Map<String, Object> arguments = new HashMap<>();
              arguments.put("x", point.x);
              arguments.put("y", point.y);
              arguments.put("lng", latLng.getLongitude());
              arguments.put("lat", latLng.getLatitude());
              arguments.put("duration", duration);
              methodChannel.invokeMethod("map#onTwoFingerHoldGesture", arguments);
            }
          }
        );
      }
    } else {
      if (twoFingerHoldGestureDetector != null) {
        twoFingerHoldGestureDetector.cleanup();
        twoFingerHoldGestureDetector = null;
      }
    }
  }

  @Override
  public void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    
    // Clean up two-finger hold gesture detector
    if (twoFingerHoldGestureDetector != null) {
      twoFingerHoldGestureDetector.cleanup();
      twoFingerHoldGestureDetector = null;
    }
    
    // Clean up native measurement detector
    if (nativeMeasurementDetector != null) {
      nativeMeasurementDetector.cleanup();
      nativeMeasurementDetector = null;
    }
    
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

  // Native Measurement Methods

  private void enableNativeMeasurement(boolean enabled) {
    if (enabled) {
      if (nativeMeasurementDetector == null && mapLibreMap != null) {
        nativeMeasurementDetector = new NativeMeasurementDetector(mapLibreMap, new NativeMeasurementDetector.OnNativeMeasurementListener() {
          @Override
          public void onMeasurementStart(PointF point1, PointF point2, LatLng latLng1, LatLng latLng2, 
                                        double distance, double bearing, long duration) {
            sendNativeMeasurementEvent("measurement#onStart", point1, point2, latLng1, latLng2, distance, bearing, duration);
          }

          @Override
          public void onMeasurementUpdate(PointF point1, PointF point2, LatLng latLng1, LatLng latLng2, 
                                         double distance, double bearing, long duration) {
            sendNativeMeasurementEvent("measurement#onUpdate", point1, point2, latLng1, latLng2, distance, bearing, duration);
          }

          @Override
          public void onMeasurementEnd(PointF point1, PointF point2, LatLng latLng1, LatLng latLng2,
                                      double distance, double bearing, long duration) {
            sendNativeMeasurementEvent("measurement#onEnd", point1, point2, latLng1, latLng2, distance, bearing, duration);
          }
        });
      }
    } else {
      if (nativeMeasurementDetector != null) {
        nativeMeasurementDetector.disable();
        nativeMeasurementDetector = null;
      }
    }
  }

  private void setNativeMeasurementStyle(Object arguments) {
    if (nativeMeasurementDetector != null && arguments instanceof Map) {
      Map<String, Object> styleArgs = (Map<String, Object>) arguments;
      
      String lineColor = (String) styleArgs.get("lineColor");
      Double lineWidth = (Double) styleArgs.get("lineWidth");
      Double lineOpacity = (Double) styleArgs.get("lineOpacity");
      String endpointColor = (String) styleArgs.get("endpointColor");
      Double endpointRadius = (Double) styleArgs.get("endpointRadius");
      
      // Set defaults if null
      if (lineColor == null) lineColor = "#FF0000";
      if (lineWidth == null) lineWidth = 3.0;
      if (lineOpacity == null) lineOpacity = 0.8;
      if (endpointColor == null) endpointColor = "#FF0000";
      if (endpointRadius == null) endpointRadius = 8.0;
      
      nativeMeasurementDetector.setMeasurementStyle(lineColor, lineWidth, lineOpacity, endpointColor, endpointRadius);
    }
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

  private void sendNativeMeasurementEvent(String eventName, PointF point1, PointF point2, 
                                         LatLng latLng1, LatLng latLng2, double distance, 
                                         double bearing, long duration) {
    Map<String, Object> arguments = new HashMap<>();
    
    // Screen coordinates
    arguments.put("screenPoint1X", (double) point1.x);
    arguments.put("screenPoint1Y", (double) point1.y);
    arguments.put("screenPoint2X", (double) point2.x);
    arguments.put("screenPoint2Y", (double) point2.y);
    
    // Geographic coordinates
    arguments.put("latLng1Latitude", latLng1.getLatitude());
    arguments.put("latLng1Longitude", latLng1.getLongitude());
    arguments.put("latLng2Latitude", latLng2.getLatitude());
    arguments.put("latLng2Longitude", latLng2.getLongitude());
    
    // Measurement data
    arguments.put("distanceNauticalMiles", distance);
    arguments.put("bearingDegrees", bearing);
    arguments.put("durationMs", (double) duration);
    
    methodChannel.invokeMethod(eventName, arguments);
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
   * Helper method to load all colored arrow PNG assets and create rotated variants.
   * Creates both up and down arrow versions for all proximity colors (red, yellow, blue, green).
   */
  private void loadColoredArrowPngAssets() {
    Log.d(TAG, "Loading colored arrow PNG assets for all proximity colors");
    
    // Define all arrow color variants
    String[] arrowColors = {"red", "yellow", "blue", "green"};
    String[] arrowAssetPaths = {
        "arrow_red.png",
        "arrow_yellow.png", 
        "arrow_blue.png",
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
   * - Blue: Caution (5-10nm)
   * - Green: Safe (>10nm)
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
          "traffic_blue.png",
          "traffic_green.png"
      };
      
      String[] trafficIconIds = {
          "aircraft-red",
          "aircraft-yellow",
          "aircraft-blue", 
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
                  Expression.lt(Expression.get("proximityDistance"), Expression.literal(10.0)),
                  Expression.literal("aircraft-blue"),
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
                  Expression.lt(Expression.get("proximityDistance"), Expression.literal(10.0)),
                  // Blue arrows for caution proximity (5-10nm)
                  Expression.switchCase(
                      Expression.get("isClimbing"),
                      Expression.literal("arrow-blue-up"),
                      Expression.literal("arrow-blue-down")
                  ),
                  // Green arrows for safe distance (>10nm)
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
          polylineRenderer.showBreakPoint(lineId, breakPoint);
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
      
      // Hide visual feedback elements
      if (polylineRenderer != null) {
        polylineRenderer.hideBreakPoint(lineId);
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
  // Native LERC Canvas Handler Methods
  // =====================================
  
  /**
   * Handles method calls coming from the flight_canvas/native_lerc method channel.
   */
  private void handleNativeLercMethodCall(MethodCall call, MethodChannel.Result result) {
    try {
      switch (call.method) {
        case "initialize":
          handleNativeLercCanvasInitialize(call, result);
          break;
        case "updateAltitudes":
          handleNativeLercCanvasUpdateAltitudes(call, result);
          break;
        case "updateResolution":
          // TODO: Implement resolution update when needed
          result.success(null);
          break;
        case "dispose":
          handleNativeLercCanvasDispose(call, result);
          break;
        default:
          result.notImplemented();
      }
    } catch (Exception e) {
      Log.e(TAG, "Error handling native LERC method call: " + e.getMessage(), e);
      result.error("NATIVE_LERC_ERROR", "Error handling native LERC method call: " + e.getMessage(), null);
    }
  }
  
  /**
   * Handles native LERC canvas layer initialization.
   * This method creates a native LERC canvas layer with the specified parameters.
   */
  private void handleNativeLercCanvasInitialize(MethodCall call, MethodChannel.Result result) {
    try {
      Log.d(TAG, "handleNativeLercCanvasInitialize called");
      
      String layerId = call.argument("layerId");
      if (layerId == null || layerId.isEmpty()) {
        result.error("INVALID_ARGUMENTS", "layerId is required", null);
        return;
      }
      
      // Extract initialization parameters
      Object boundsObj = call.argument("bounds");
      List<Double> bounds = null;
      if (boundsObj instanceof double[]) {
        // Handle double[] from method channel
        double[] boundsArray = (double[]) boundsObj;
        bounds = new ArrayList<>();
        for (double d : boundsArray) {
          bounds.add(d);
        }
      } else if (boundsObj instanceof List) {
        // Handle List<Double> 
        bounds = (List<Double>) boundsObj;
      }
      
      Integer width = call.argument("width");
      Integer height = call.argument("height");
      Double referenceAltitude = call.argument("referenceAltitude");
      Double warningAltitude = call.argument("warningAltitude");
      
      // Store the elevation data as a raw double[] array instead of converting to List<Double>
      // This prevents OutOfMemoryError when dealing with large terrain datasets
      Object elevationDataObj = call.argument("elevationData");
      double[] elevationArray = null;
      
      if (elevationDataObj instanceof double[]) {
        // Already a double[] array, use directly
        elevationArray = (double[]) elevationDataObj;
      } else if (elevationDataObj instanceof List) {
        // Convert List<Double> to primitive double[] to save memory
        List<?> list = (List<?>) elevationDataObj;
        elevationArray = new double[list.size()];
        for (int i = 0; i < list.size(); i++) {
          Object item = list.get(i);
          if (item instanceof Number) {
            elevationArray[i] = ((Number) item).doubleValue();
          }
        }
      }
      
      Log.d(TAG, "Creating native LERC canvas layer: " + layerId);
      Log.d(TAG, "  Bounds: " + bounds);
      Log.d(TAG, "  Dimensions: " + width + "x" + height);
      Log.d(TAG, "  Reference altitude: " + referenceAltitude + "ft, Warning altitude: " + warningAltitude + "ft");
      Log.d(TAG, "  Elevation data size: " + (elevationArray != null ? elevationArray.length : "null"));
      
      // Create layer configuration
      Map<String, Object> layerConfig = new HashMap<>();
      layerConfig.put("layerId", layerId);
      layerConfig.put("bounds", bounds);
      layerConfig.put("width", width);
      layerConfig.put("height", height);
      layerConfig.put("referenceAltitude", referenceAltitude);
      layerConfig.put("warningAltitude", warningAltitude);
      layerConfig.put("elevationData", elevationArray);  // Store as primitive array instead of List
      layerConfig.put("initialized", true);
      layerConfig.put("disposed", false);
      
      // Store the layer configuration
      nativeLercCanvasLayers.put(layerId, layerConfig);
      
      Log.d(TAG, "Successfully initialized native LERC canvas layer: " + layerId);
      result.success(null);
      
    } catch (Exception e) {
      Log.e(TAG, "Error initializing native LERC canvas: " + e.getMessage(), e);
      result.error("NATIVE_LERC_ERROR", "Failed to initialize native LERC canvas: " + e.getMessage(), null);
    }
  }
  
  /**
   * Handles altitude data updates for native LERC canvas layers.
   */
  private void handleNativeLercCanvasUpdateAltitudes(MethodCall call, MethodChannel.Result result) {
    try {
      Log.d(TAG, "handleNativeLercCanvasUpdateAltitudes called");
      
      String layerId = call.argument("layerId");
      if (layerId == null || layerId.isEmpty()) {
        result.error("INVALID_ARGUMENTS", "layerId is required", null);
        return;
      }
      
      // Check if layer exists and is initialized
      Object layerObj = nativeLercCanvasLayers.get(layerId);
      if (layerObj == null) {
        result.error("LAYER_NOT_FOUND", "Native LERC canvas layer not found: " + layerId, null);
        return;
      }
      
      @SuppressWarnings("unchecked")
      Map<String, Object> layerConfig = (Map<String, Object>) layerObj;
      
      Boolean initialized = (Boolean) layerConfig.get("initialized");
      Boolean disposed = (Boolean) layerConfig.get("disposed");
      
      if (initialized == null || !initialized) {
        result.error("LAYER_NOT_INITIALIZED", "Native LERC canvas layer not initialized: " + layerId, null);
        return;
      }
      
      if (disposed != null && disposed) {
        result.error("LAYER_DISPOSED", "Native LERC canvas layer already disposed: " + layerId, null);
        return;
      }
      
      // Extract altitude update parameters
      Double referenceAltitude = call.argument("referenceAltitude");
      Double warningAltitude = call.argument("warningAltitude");
      
      if (referenceAltitude == null) {
        result.error("INVALID_ARGUMENTS", "referenceAltitude is required", null);
        return;
      }
      
      if (warningAltitude == null) {
        result.error("INVALID_ARGUMENTS", "warningAltitude is required", null);
        return;
      }
      
      // Get stored elevation data from initialization
      double[] elevationData = (double[]) layerConfig.get("elevationData");
      Integer width = (Integer) layerConfig.get("width");
      Integer height = (Integer) layerConfig.get("height");
      List<Double> bounds = (List<Double>) layerConfig.get("bounds");
      
      if (elevationData == null) {
        result.error("NO_ELEVATION_DATA", "No elevation data found for layer: " + layerId, null);
        return;
      }
      
      Log.d(TAG, "FAST altitude update - layer: " + layerId + " (ref=" + referenceAltitude + "ft, warn=" + warningAltitude + "ft)");
      
      // Update altitude thresholds in layer config
      layerConfig.put("referenceAltitude", referenceAltitude);
      layerConfig.put("warningAltitude", warningAltitude);
      layerConfig.put("lastUpdated", System.currentTimeMillis());
      
      // Direct fast update - no debouncing, no complex tile processing
      updateSimpleTerrainVisualization(layerId, layerConfig, elevationData, width, height, bounds, referenceAltitude, warningAltitude);
      
      result.success(null);
      
    } catch (Exception e) {
      Log.e(TAG, "Error updating native LERC canvas altitudes: " + e.getMessage(), e);
      result.error("NATIVE_LERC_ERROR", "Failed to update native LERC canvas altitudes: " + e.getMessage(), null);
    }
  }
  
  /**
   * Handles disposal of native LERC canvas layers.
   */
  private void handleNativeLercCanvasDispose(MethodCall call, MethodChannel.Result result) {
    try {
      Log.d(TAG, "handleNativeLercCanvasDispose called");
      
      String layerId = call.argument("layerId");
      if (layerId == null || layerId.isEmpty()) {
        result.error("INVALID_ARGUMENTS", "layerId is required", null);
        return;
      }
      
      // Check if layer exists
      Object layerObj = nativeLercCanvasLayers.get(layerId);
      if (layerObj == null) {
        // Layer doesn't exist, but that's okay for dispose
        Log.w(TAG, "Attempting to dispose non-existent native LERC canvas layer: " + layerId);
        result.success(null);
        return;
      }
      
      @SuppressWarnings("unchecked")
      Map<String, Object> layerConfig = (Map<String, Object>) layerObj;
      
      Boolean disposed = (Boolean) layerConfig.get("disposed");
      if (disposed != null && disposed) {
        Log.w(TAG, "Native LERC canvas layer already disposed: " + layerId);
        result.success(null);
        return;
      }
      
      Log.d(TAG, "Disposing native LERC canvas layer: " + layerId);
      
      // Remove visual layer from map style if it exists
      String visualLayerId = layerId + "-terrain";
      if (style != null && style.getLayer(visualLayerId) != null) {
        style.removeLayer(visualLayerId);
        Log.d(TAG, "Removed terrain visualization layer: " + visualLayerId);
      }
      
      // Remove source if it exists
      String sourceId = layerId + "-source";
      if (style != null && style.getSource(sourceId) != null) {
        style.removeSource(sourceId);
        Log.d(TAG, "Removed terrain visualization source: " + sourceId);
      }
      
      // Mark as disposed and clean up
      layerConfig.put("disposed", true);
      layerConfig.put("disposedAt", System.currentTimeMillis());
      
      // Clear large data objects to free memory
      layerConfig.remove("elevationData");
      
      Log.d(TAG, "Successfully disposed native LERC canvas layer: " + layerId);
      result.success(null);
      
    } catch (Exception e) {
      Log.e(TAG, "Error disposing native LERC canvas: " + e.getMessage(), e);
      result.error("NATIVE_LERC_ERROR", "Failed to dispose native LERC canvas: " + e.getMessage(), null);
    }
  }
  
  /**
   * Updates terrain visualization using tile-based approach like Leaflet for sharp rendering.
   * 
   * This implementation creates multiple tile-based ImageSources for the current viewport
   * instead of a single massive bitmap stretched across the entire world. This approach
   * matches the Leaflet LERC implementation's tile system for crisp rendering.
   * 
   * @param layerId The layer identifier
   * @param layerConfig The layer configuration
   * @param elevationData The elevation data array (full world data)
   * @param width Width of elevation data
   * @param height Height of elevation data  
   * @param bounds Geographic bounds [west, south, east, north]
   * @param referenceAltitude Reference altitude in feet
   * @param warningAltitude Warning altitude in feet
   */
  private void updateTerrainVisualization(String layerId, Map<String, Object> layerConfig, 
                                         double[] elevationData, Integer width, Integer height, 
                                         List<Double> bounds, Double referenceAltitude, Double warningAltitude) {
    try {
      if (style == null) {
        Log.w(TAG, "Cannot update terrain visualization - style is null");
        return;
      }
      
      if (elevationData == null || width == null || height == null || bounds == null || bounds.size() != 4) {
        Log.w(TAG, "Cannot update terrain visualization - missing required data");
        return;
      }
      
      // Get current map viewport and zoom level
      LatLngBounds viewportBounds = mapLibreMap.getProjection().getVisibleRegion().latLngBounds;
      double currentZoom = mapLibreMap.getCameraPosition().zoom;
      
      Log.d(TAG, "Updating terrain visualization with TILE-BASED approach for layer: " + layerId);
      Log.d(TAG, "  Current zoom: " + String.format("%.2f", currentZoom));
      Log.d(TAG, "  Viewport bounds: " + viewportBounds.toString());
      Log.d(TAG, "  Data dimensions: " + width + "x" + height + " (full world dataset)");
      
      // Determine appropriate tile size based on zoom level (like Leaflet)
      int tileSize = getTileSizeForZoom(currentZoom);
      
      if (currentZoom < 3.0) {
        // At very low zoom levels, still use legacy approach to avoid too many tiles
        Log.d(TAG, "Low zoom (" + String.format("%.1f", currentZoom) + ") - using legacy approach");
        updateLegacyTerrainVisualization(layerId, layerConfig, elevationData, width, height, bounds, referenceAltitude, warningAltitude);
        return;
      }
      
      // Create tiles for the current viewport
      createTerrainTilesForViewport(layerId, elevationData, width, height, bounds, 
                                   viewportBounds, tileSize, referenceAltitude, warningAltitude);
      
    } catch (Exception e) {
      Log.e(TAG, "Error updating terrain visualization: " + e.getMessage(), e);
      // Fallback to legacy approach on error
      updateLegacyTerrainVisualization(layerId, layerConfig, elevationData, width, height, bounds, referenceAltitude, warningAltitude);
    }
  }
  
  /**
   * Determines appropriate tile size based on zoom level.
   * Higher zoom = smaller tiles for more detail, lower zoom = larger tiles for performance.
   */
  private int getTileSizeForZoom(double zoom) {
    if (zoom >= 8.0) {
      return 256; // High detail - like Leaflet
    } else if (zoom >= 6.0) {
      return 512; // Medium detail
    } else if (zoom >= 4.0) {
      return 1024; // Low detail
    } else {
      return 2048; // Very low detail
    }
  }
  
  /**
   * Creates terrain tiles for the current viewport.
   * This method divides the viewport into tiles and creates individual ImageSources for each.
   */
  private void createTerrainTilesForViewport(String layerId, double[] elevationData, int width, int height, 
                                           List<Double> bounds, LatLngBounds viewportBounds, int tileSize, 
                                           double referenceAltitude, double warningAltitude) {
    try {
      // Clean up previous tiles
      cleanupPreviousTerrainTiles(layerId);
      
      // Expand viewport bounds slightly to ensure coverage when panning
      double expandFactor = 0.2; // 20% expansion
      double latSpan = viewportBounds.getLatNorth() - viewportBounds.getLatSouth();
      double lngSpan = viewportBounds.getLonEast() - viewportBounds.getLonWest();
      
      double expandedNorth = Math.min(90.0, viewportBounds.getLatNorth() + latSpan * expandFactor);
      double expandedSouth = Math.max(-90.0, viewportBounds.getLatSouth() - latSpan * expandFactor);
      double expandedEast = Math.min(180.0, viewportBounds.getLonEast() + lngSpan * expandFactor);
      double expandedWest = Math.max(-180.0, viewportBounds.getLonWest() - lngSpan * expandFactor);
      
      Log.d(TAG, "Expanded viewport bounds: W=" + String.format("%.2f", expandedWest) + 
               ", S=" + String.format("%.2f", expandedSouth) + 
               ", E=" + String.format("%.2f", expandedEast) + 
               ", N=" + String.format("%.2f", expandedNorth));
      
      // Calculate tile grid dimensions based on tile size in degrees
      double tileDegreesLat = latSpan / 3.0; // ~3 tiles vertically
      double tileDegreesLng = lngSpan / 4.0; // ~4 tiles horizontally
      
      // Ensure minimum tile size to avoid too many tiny tiles
      tileDegreesLat = Math.max(tileDegreesLat, 0.5); // Minimum 0.5° latitude
      tileDegreesLng = Math.max(tileDegreesLng, 0.5); // Minimum 0.5° longitude
      
      Log.d(TAG, "Tile size: " + String.format("%.2f", tileDegreesLat) + "° lat × " + 
               String.format("%.2f", tileDegreesLng) + "° lng");
      
      // Create tiles to cover the expanded viewport
      int tileCount = 0;
      double currentLat = expandedSouth;
      
      while (currentLat < expandedNorth && tileCount < 50) { // Limit max tiles for performance
        double currentLng = expandedWest;
        
        while (currentLng < expandedEast && tileCount < 50) {
          // Calculate tile bounds
          double tileSouth = currentLat;
          double tileNorth = Math.min(expandedNorth, currentLat + tileDegreesLat);
          double tileWest = currentLng;
          double tileEast = Math.min(expandedEast, currentLng + tileDegreesLng);
          
          // Create tile
          createSingleTerrainTile(layerId, elevationData, width, height, bounds, 
                                 tileWest, tileSouth, tileEast, tileNorth, 
                                 tileSize, referenceAltitude, warningAltitude, tileCount);
          
          tileCount++;
          currentLng += tileDegreesLng;
        }
        
        currentLat += tileDegreesLat;
      }
      
      Log.d(TAG, "Created " + tileCount + " terrain tiles for sharp rendering");
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating terrain tiles: " + e.getMessage(), e);
    }
  }
  
  /**
   * Creates a single terrain tile as an ImageSource.
   */
  private void createSingleTerrainTile(String layerId, double[] elevationData, int dataWidth, int dataHeight, 
                                      List<Double> dataBounds, double tileWest, double tileSouth, 
                                      double tileEast, double tileNorth, int tilePixelSize, 
                                      double referenceAltitude, double warningAltitude, int tileIndex) {
    try {
      // Extract elevation data for this tile area
      double[] tileElevationData = extractTileElevationData(elevationData, dataWidth, dataHeight, 
                                                           dataBounds, tileWest, tileSouth, 
                                                           tileEast, tileNorth, tilePixelSize);
      
      if (tileElevationData == null) {
        Log.w(TAG, "No elevation data for tile " + tileIndex);
        return;
      }
      
      // Create terrain bitmap for this tile at fixed resolution
      Bitmap tileBitmap = createTerrainBitmap(tileElevationData, tilePixelSize, tilePixelSize, 
                                             referenceAltitude, warningAltitude);
      
      if (tileBitmap == null) {
        Log.w(TAG, "Failed to create bitmap for tile " + tileIndex);
        return;
      }
      
      // Create unique IDs for this tile
      String tileLayerId = layerId + "-tile-" + tileIndex;
      String tileSourceId = layerId + "-tile-source-" + tileIndex;
      
      // Create LatLng corners for the tile
      LatLng nw = new LatLng(tileNorth, tileWest); // northwest
      LatLng ne = new LatLng(tileNorth, tileEast); // northeast
      LatLng se = new LatLng(tileSouth, tileEast); // southeast
      LatLng sw = new LatLng(tileSouth, tileWest); // southwest
      
      // Create ImageSource for this tile
      ImageSource tileSource = new ImageSource(tileSourceId, new LatLngQuad(nw, ne, se, sw), tileBitmap);
      style.addSource(tileSource);
      
      // Create RasterLayer for this tile
      RasterLayer tileLayer = new RasterLayer(tileLayerId, tileSourceId);
      tileLayer.setProperties(
          PropertyFactory.rasterOpacity(0.6f), // Semi-transparent overlay
          PropertyFactory.rasterFadeDuration(0.0f) // No fade for immediate updates
      );
      
      // Add the tile layer
      style.addLayer(tileLayer);
      
      Log.v(TAG, "Created tile " + tileIndex + ": " + tilePixelSize + "x" + tilePixelSize + 
               " pixels covering " + String.format("%.3f", tileEast-tileWest) + "° × " + 
               String.format("%.3f", tileNorth-tileSouth) + "°");
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating terrain tile " + tileIndex + ": " + e.getMessage(), e);
    }
  }
  
  /**
   * Extracts elevation data for a specific tile area from the full world dataset.
   */
  private double[] extractTileElevationData(double[] fullElevationData, int fullWidth, int fullHeight, 
                                          List<Double> fullBounds, double tileWest, double tileSouth, 
                                          double tileEast, double tileNorth, int tilePixelSize) {
    try {
      double fullWest = fullBounds.get(0);
      double fullSouth = fullBounds.get(1);
      double fullEast = fullBounds.get(2);
      double fullNorth = fullBounds.get(3);
      
      // Calculate sampling parameters
      double fullLngSpan = fullEast - fullWest;
      double fullLatSpan = fullNorth - fullSouth;
      double tileLngSpan = tileEast - tileWest;
      double tileLatSpan = tileNorth - tileSouth;
      
      double[] tileData = new double[tilePixelSize * tilePixelSize];
      
      // Sample elevation data for this tile
      for (int tileY = 0; tileY < tilePixelSize; tileY++) {
        for (int tileX = 0; tileX < tilePixelSize; tileX++) {
          // Convert tile pixel coordinates to geographic coordinates
          double tileLng = tileWest + (tileX / (double) tilePixelSize) * tileLngSpan;
          double tileLat = tileNorth - (tileY / (double) tilePixelSize) * tileLatSpan; // Flip Y
          
          // Convert geographic coordinates to full data array indices
          double fullX = ((tileLng - fullWest) / fullLngSpan) * fullWidth;
          double fullY = ((fullNorth - tileLat) / fullLatSpan) * fullHeight; // Flip Y
          
          // Clamp to valid indices
          int fullXIndex = Math.max(0, Math.min(fullWidth - 1, (int) Math.round(fullX)));
          int fullYIndex = Math.max(0, Math.min(fullHeight - 1, (int) Math.round(fullY)));
          
          // Get elevation value from full dataset
          int fullDataIndex = fullYIndex * fullWidth + fullXIndex;
          if (fullDataIndex >= 0 && fullDataIndex < fullElevationData.length) {
            tileData[tileY * tilePixelSize + tileX] = fullElevationData[fullDataIndex];
          } else {
            tileData[tileY * tilePixelSize + tileX] = 0.0; // Default elevation
          }
        }
      }
      
      Log.v(TAG, "Extracted " + tileData.length + " elevation points for tile covering " + 
               String.format("%.3f", tileLngSpan) + "° × " + String.format("%.3f", tileLatSpan) + "°");
      
      return tileData;
      
    } catch (Exception e) {
      Log.e(TAG, "Error extracting tile elevation data: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Cleans up previous terrain tiles for a layer.
   */
  private void cleanupPreviousTerrainTiles(String layerId) {
    try {
      if (style == null) return;
      
      // Remove all existing tile layers and sources for this layer
      List<Layer> layersToRemove = new ArrayList<>();
      List<Source> sourcesToRemove = new ArrayList<>();
      
      String tileLayerPrefix = layerId + "-tile-";
      String tileSourcePrefix = layerId + "-tile-source-";
      
      // Find layers and sources to remove
      for (Layer layer : style.getLayers()) {
        if (layer.getId().startsWith(tileLayerPrefix)) {
          layersToRemove.add(layer);
        }
      }
      
      for (Source source : style.getSources()) {
        if (source.getId().startsWith(tileSourcePrefix)) {
          sourcesToRemove.add(source);
        }
      }
      
      // Remove layers first, then sources
      for (Layer layer : layersToRemove) {
        style.removeLayer(layer.getId());
        Log.v(TAG, "Removed previous tile layer: " + layer.getId());
      }
      
      for (Source source : sourcesToRemove) {
        style.removeSource(source.getId());
        Log.v(TAG, "Removed previous tile source: " + source.getId());
      }
      
      if (!layersToRemove.isEmpty() || !sourcesToRemove.isEmpty()) {
        Log.d(TAG, "Cleaned up " + layersToRemove.size() + " tile layers and " + 
                   sourcesToRemove.size() + " tile sources for layer: " + layerId);
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error cleaning up previous terrain tiles: " + e.getMessage(), e);
    }
  }
  
  /**
   * Updates native LERC terrain tiles for the current map view.
   * This method is called after camera movements to ensure terrain tiles
   * are refreshed for the new viewport, providing continuous sharp rendering.
   */
  private void updateNativeLercTilesForCurrentView() {
    try {
      if (style == null || mapLibreMap == null) {
        return;
      }
      
      // Iterate through all active native LERC layers
      for (Map.Entry<String, Object> entry : nativeLercCanvasLayers.entrySet()) {
        String layerId = entry.getKey();
        Object layerObj = entry.getValue();
        
        if (!(layerObj instanceof Map)) {
          continue;
        }
        
        @SuppressWarnings("unchecked")
        Map<String, Object> layerConfig = (Map<String, Object>) layerObj;
        
        // Check if layer is initialized and not disposed
        Boolean initialized = (Boolean) layerConfig.get("initialized");
        Boolean disposed = (Boolean) layerConfig.get("disposed");
        
        if (initialized == null || !initialized || (disposed != null && disposed)) {
          continue;
        }
        
        // Get layer data
        double[] elevationData = (double[]) layerConfig.get("elevationData");
        Integer width = (Integer) layerConfig.get("width");
        Integer height = (Integer) layerConfig.get("height");
        List<Double> bounds = (List<Double>) layerConfig.get("bounds");
        Double referenceAltitude = (Double) layerConfig.get("referenceAltitude");
        Double warningAltitude = (Double) layerConfig.get("warningAltitude");
        
        if (elevationData == null || width == null || height == null || 
            bounds == null || referenceAltitude == null || warningAltitude == null) {
          continue;
        }
        
        Log.d(TAG, "Updating terrain tiles for camera movement - layer: " + layerId);
        
        // Update terrain visualization with new viewport
        updateTerrainVisualization(layerId, layerConfig, elevationData, width, height, 
                                  bounds, referenceAltitude, warningAltitude);
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error updating native LERC tiles for current view: " + e.getMessage(), e);
    }
  }
  
  /**
   * Legacy terrain visualization approach - creates blurry results.
   * This is the old approach that creates a single massive bitmap.
   */
  private void updateLegacyTerrainVisualization(String layerId, Map<String, Object> layerConfig, 
                                               double[] elevationData, Integer width, Integer height, 
                                               List<Double> bounds, Double referenceAltitude, Double warningAltitude) {
    try {
      Log.d(TAG, "Updating LEGACY terrain visualization for layer: " + layerId);
      Log.d(TAG, "  Data dimensions: " + width + "x" + height + " (WILL BE BLURRY when stretched!)");
      Log.d(TAG, "  Reference: " + referenceAltitude + "ft, Warning: " + warningAltitude + "ft");
      Log.d(TAG, "  Bounds: " + bounds + " (entire world coverage causes blur)");
      
      // Create terrain visualization bitmap - this will be blurry when stretched
      Bitmap terrainBitmap = createTerrainBitmap(elevationData, width, height, referenceAltitude, warningAltitude);
      
      if (terrainBitmap == null) {
        Log.e(TAG, "Failed to create terrain bitmap");
        return;
      }
      
      // Create unique IDs for the terrain layer and source
      String visualLayerId = layerId + "-terrain";
      String sourceId = layerId + "-source";
      
      // Remove existing layer and source if they exist
      if (style.getLayer(visualLayerId) != null) {
        style.removeLayer(visualLayerId);
      }
      if (style.getSource(sourceId) != null) {
        style.removeSource(sourceId);
      }
      
      // Create geographic bounds for the image
      // bounds format: [west, south, east, north]
      double west = bounds.get(0);
      double south = bounds.get(1);
      double east = bounds.get(2);
      double north = bounds.get(3);
      
      Log.d(TAG, "PROBLEM: Stretching " + width + "x" + height + " bitmap across " + 
               (east-west) + "° longitude × " + (north-south) + "° latitude");
      Log.d(TAG, "Each pixel covers ~" + String.format("%.2f", (east-west)/width) + "° longitude × " + 
               String.format("%.2f", (north-south)/height) + "° latitude - TOO LARGE!");
      
      // Validate bounds values (skip extensive validation for brevity)
      if (north <= south || east <= west || north > 90 || south < -90 || east > 180 || west < -180) {
        Log.e(TAG, "Invalid bounds - skipping terrain update");
        return;
      }
      
      // Create LatLng objects with validated coordinates
      LatLng nw = new LatLng(north, west); // northwest (top-left)
      LatLng ne = new LatLng(north, east); // northeast (top-right)
      LatLng se = new LatLng(south, east); // southeast (bottom-right)
      LatLng sw = new LatLng(south, west); // southwest (bottom-left)
      
      // Create image source with terrain bitmap - THIS CAUSES THE BLUR!
      ImageSource imageSource = new ImageSource(sourceId, new LatLngQuad(nw, ne, se, sw), terrainBitmap);
      style.addSource(imageSource);
      
      // Create raster layer to display the terrain
      RasterLayer terrainLayer = new RasterLayer(visualLayerId, sourceId);
      terrainLayer.setProperties(
          PropertyFactory.rasterOpacity(0.5f), // Reduce opacity to see blur issue better
          PropertyFactory.rasterFadeDuration(0.0f) // No fade for immediate updates
      );
      
      // Add the terrain layer
      style.addLayer(terrainLayer);
      
      Log.d(TAG, "Created BLURRY terrain layer (legacy approach): " + visualLayerId);
      Log.d(TAG, "To fix blur: Implement tile-based rendering like Leaflet with 256x256 tiles");
      
    } catch (Exception e) {
      Log.e(TAG, "Error updating legacy terrain visualization: " + e.getMessage(), e);
    }
  }
  
  /**
   * Creates a color-coded terrain bitmap from elevation data with caching and optimization.
   * This method implements the performance patterns from the HTTP LERC layer:
   * - Pre-computed color lookup table (LUT) for ultra-fast pixel coloring
   * - Tile-wise bitmap caching to avoid regeneration
   * - Cache-busting version management for altitude changes
   * 
   * @param elevationData Array of elevation values in meters
   * @param width Width of the elevation grid
   * @param height Height of the elevation grid
   * @param referenceAltitude Reference altitude in feet
   * @param warningAltitude Warning altitude in feet
   * @return Bitmap with color-coded terrain visualization
   */
  private Bitmap createTerrainBitmap(double[] elevationData, int width, int height, 
                                    double referenceAltitude, double warningAltitude) {
    try {
      // Generate cache key including altitude thresholds for invalidation
      String cacheKey = generateBitmapCacheKey(elevationData, width, height, referenceAltitude, warningAltitude);
      
      // Check if cached bitmap exists
      Bitmap cachedBitmap = coloredBitmapCache.get(cacheKey);
      if (cachedBitmap != null && !cachedBitmap.isRecycled()) {
        Log.v(TAG, "Using cached terrain bitmap: " + width + "x" + height + " pixels");
        return cachedBitmap;
      }
      
      Log.d(TAG, "Creating new terrain bitmap with optimized color LUT: " + width + "x" + height + " pixels");
      
      // Initialize pre-computed color LUT if needed
      if (colorLUT == null) {
        initializeColorLUT();
      }
      
      // Convert altitudes from feet to meters
      double referenceAltitudeM = referenceAltitude * 0.3048;
      double warningAltitudeM = warningAltitude * 0.3048;
      
      // Create bitmap with optimized pixel processing
      Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
      int[] pixels = new int[width * height];
      
      // Process each pixel using pre-computed color LUT for ultra-fast coloring
      for (int i = 0; i < elevationData.length && i < pixels.length; i++) {
        double elevation = elevationData[i];
        pixels[i] = getColorFromLUT(elevation, referenceAltitudeM, warningAltitudeM);
      }
      
      // Set pixels to bitmap
      bitmap.setPixels(pixels, 0, width, 0, 0, width, height);
      
      // Cache the bitmap with size management
      cacheBitmapWithSizeManagement(cacheKey, bitmap);
      
      Log.d(TAG, "Successfully created and cached terrain bitmap with " + elevationData.length + " elevation points");
      return bitmap;
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating terrain bitmap: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Initializes the pre-computed color lookup table (LUT) for ultra-fast terrain coloring.
   * This pattern is inspired by the HTTP LERC layer's color LUT optimization.
   */
  private void initializeColorLUT() {
    try {
      Log.d(TAG, "Initializing color lookup table (LUT) for ultra-fast terrain coloring");
      
      // Create color LUT with sufficient resolution (256 levels per zone)
      int lutSize = 768; // 256 * 3 zones (red, yellow, green)
      colorLUT = new int[3][256]; // [zone][intensity]
      
      // Pre-compute red zone colors (dangerous terrain)
      for (int i = 0; i < 256; i++) {
        int alpha = 0x80 + (i * 0x7F / 255); // Variable transparency based on intensity
        colorLUT[0][i] = (alpha << 24) | 0x00FF0000; // Semi-transparent red
      }
      
      // Pre-compute yellow zone colors (caution terrain)
      for (int i = 0; i < 256; i++) {
        int alpha = 0x60 + (i * 0x9F / 255); // Variable transparency
        colorLUT[1][i] = (alpha << 24) | 0x00FFFF00; // Semi-transparent yellow
      }
      
      // Pre-compute green zone colors (safe terrain)
      for (int i = 0; i < 256; i++) {
        int alpha = 0x40 + (i * 0x7F / 255); // Variable transparency
        colorLUT[2][i] = (alpha << 24) | 0x0000FF00; // Semi-transparent green
      }
      
      Log.d(TAG, "Color LUT initialized with " + lutSize + " pre-computed color values");
      
    } catch (Exception e) {
      Log.e(TAG, "Error initializing color LUT: " + e.getMessage(), e);
      // Fallback to simple color computation
      colorLUT = null;
    }
  }
  
  /**
   * Gets color from the pre-computed lookup table for ultra-fast pixel coloring.
   * This eliminates repeated color calculations during bitmap generation.
   */
  private int getColorFromLUT(double elevation, double referenceAltitudeM, double warningAltitudeM) {
    if (colorLUT == null) {
      // Fallback to direct color computation if LUT is not available
      return getColorDirect(elevation, referenceAltitudeM, warningAltitudeM);
    }
    
    try {
      int zone;
      int intensity;
      
      if (elevation < warningAltitudeM) {
        // Red zone - below warning altitude (dangerous)
        zone = 0;
        // Calculate intensity based on how far below warning altitude
        double ratio = Math.max(0.0, 1.0 - (warningAltitudeM - elevation) / 1000.0); // 1000m range
        intensity = (int) (ratio * 255);
      } else if (elevation < referenceAltitudeM) {
        // Yellow zone - below reference altitude (caution)
        zone = 1;
        // Calculate intensity based on position between warning and reference
        double range = referenceAltitudeM - warningAltitudeM;
        double ratio = range > 0 ? (elevation - warningAltitudeM) / range : 0.5;
        intensity = (int) (ratio * 255);
      } else {
        // Green zone - above reference altitude (safe)
        zone = 2;
        // Calculate intensity based on how far above reference altitude
        double ratio = Math.min(1.0, (elevation - referenceAltitudeM) / 1000.0); // 1000m range
        intensity = (int) (ratio * 255);
      }
      
      // Clamp intensity to valid range
      intensity = Math.max(0, Math.min(255, intensity));
      
      return colorLUT[zone][intensity];
      
    } catch (Exception e) {
      // Fallback to direct computation
      return getColorDirect(elevation, referenceAltitudeM, warningAltitudeM);
    }
  }
  
  /**
   * Direct color computation fallback when LUT is not available.
   */
  private int getColorDirect(double elevation, double referenceAltitudeM, double warningAltitudeM) {
    if (elevation < warningAltitudeM) {
      return 0x80FF0000; // Semi-transparent red
    } else if (elevation < referenceAltitudeM) {
      return 0x80FFFF00; // Semi-transparent yellow
    } else {
      return 0x8000FF00; // Semi-transparent green
    }
  }
  
  /**
   * Generates a cache key for bitmap caching based on data and altitude thresholds.
   * This enables cache-busting when altitude settings change while preserving cached bitmaps.
   */
  private String generateBitmapCacheKey(double[] elevationData, int width, int height, 
                                       double referenceAltitude, double warningAltitude) {
    try {
      // Generate a content hash for the elevation data (sample-based for performance)
      int dataHash = generateElevationDataHash(elevationData, width, height);
      
      // Include altitude thresholds in the key for cache invalidation
      String altitudeKey = String.format("%.1f_%.1f", referenceAltitude, warningAltitude);
      
      return String.format("terrain_%d_%dx%d_%s", dataHash, width, height, altitudeKey);
      
    } catch (Exception e) {
      Log.w(TAG, "Error generating bitmap cache key: " + e.getMessage());
      // Fallback to simple key based on dimensions and altitude
      return String.format("terrain_%dx%d_%.1f_%.1f", width, height, referenceAltitude, warningAltitude);
    }
  }
  
  /**
   * Generates a fast hash of elevation data for caching purposes.
   * Uses sampling to avoid processing the entire dataset for large terrain data.
   */
  private int generateElevationDataHash(double[] elevationData, int width, int height) {
    try {
      int hash = 1;
      int sampleRate = Math.max(1, elevationData.length / 1000); // Sample ~1000 points
      
      for (int i = 0; i < elevationData.length; i += sampleRate) {
        // Use a simple but effective hash combining method
        long bits = Double.doubleToLongBits(elevationData[i]);
        hash = 31 * hash + (int) (bits ^ (bits >>> 32));
      }
      
      return hash;
      
    } catch (Exception e) {
      Log.w(TAG, "Error generating elevation data hash: " + e.getMessage());
      return elevationData.length; // Fallback to length-based hash
    }
  }
  
  /**
   * Caches a bitmap with automatic size management to prevent memory issues.
   * Implements LRU-style eviction when cache size limits are exceeded.
   */
  private void cacheBitmapWithSizeManagement(String cacheKey, Bitmap bitmap) {
    try {
      // Check cache size and evict old entries if needed
      if (coloredBitmapCache.size() >= MAX_BITMAP_CACHE_SIZE) {
        evictOldestBitmapCacheEntries();
      }
      
      // Store the bitmap in cache
      coloredBitmapCache.put(cacheKey, bitmap);
      
      Log.v(TAG, "Cached terrain bitmap: " + cacheKey + " (cache size: " + coloredBitmapCache.size() + ")");
      
    } catch (Exception e) {
      Log.w(TAG, "Error caching bitmap: " + e.getMessage());
      // Continue without caching on error
    }
  }
  
  /**
   * Evicts the oldest bitmap cache entries to free memory.
   * This implements a simple LRU-style eviction policy.
   */
  private void evictOldestBitmapCacheEntries() {
    try {
      int entriesToRemove = coloredBitmapCache.size() - MAX_BITMAP_CACHE_SIZE + 10; // Remove extra entries
      
      if (entriesToRemove <= 0) {
        return;
      }
      
      List<String> keysToRemove = new ArrayList<>();
      int count = 0;
      
      // Remove oldest entries (this is a simplification - in production might use LRU)
      for (String key : coloredBitmapCache.keySet()) {
        if (count >= entriesToRemove) {
          break;
        }
        keysToRemove.add(key);
        count++;
      }
      
      // Remove the selected entries and recycle bitmaps
      for (String key : keysToRemove) {
        Bitmap bitmap = coloredBitmapCache.remove(key);
        if (bitmap != null && !bitmap.isRecycled()) {
          bitmap.recycle();
        }
      }
      
      Log.d(TAG, "Evicted " + keysToRemove.size() + " old bitmap cache entries");
      
    } catch (Exception e) {
      Log.w(TAG, "Error evicting bitmap cache entries: " + e.getMessage());
    }
  }
  
  /**
   * Pre-decodes and caches elevation data per tile for ultra-fast access.
   * This mirrors the HTTP LERC layer's elevation caching strategy.
   */
  private void preDecodeAndCacheElevationData(String layerId, double[] elevationData, 
                                            int width, int height, List<Double> bounds) {
    try {
      Log.d(TAG, "Pre-decoding and caching elevation data for layer: " + layerId);
      
      // Check cache size and evict if needed
      if (elevationTileCache.size() >= MAX_ELEVATION_CACHE_SIZE) {
        evictOldestElevationCacheEntries();
      }
      
      // Calculate tile grid parameters (similar to HTTP layer's tiling)
      int tileSize = 256; // Standard tile size
      int tilesX = (int) Math.ceil((double) width / tileSize);
      int tilesY = (int) Math.ceil((double) height / tileSize);
      
      Log.d(TAG, "Pre-caching elevation data in " + tilesX + "x" + tilesY + " tiles of " + tileSize + "x" + tileSize + " each");
      
      // Pre-decode elevation data per tile
      for (int tileY = 0; tileY < tilesY; tileY++) {
        for (int tileX = 0; tileX < tilesX; tileX++) {
          String tileKey = generateElevationTileKey(layerId, tileX, tileY);
          
          // Extract elevation data for this tile
          double[] tileElevationData = extractElevationTileData(elevationData, width, height, 
                                                                tileX, tileY, tileSize);
          
          if (tileElevationData != null) {
            elevationTileCache.put(tileKey, tileElevationData);
          }
        }
      }
      
      Log.d(TAG, "Pre-cached " + (tilesX * tilesY) + " elevation tiles for layer: " + layerId);
      
    } catch (Exception e) {
      Log.e(TAG, "Error pre-decoding elevation data: " + e.getMessage(), e);
    }
  }
  
  /**
   * Extracts elevation data for a specific tile from the full dataset.
   */
  private double[] extractElevationTileData(double[] fullData, int fullWidth, int fullHeight, 
                                          int tileX, int tileY, int tileSize) {
    try {
      int startX = tileX * tileSize;
      int startY = tileY * tileSize;
      int endX = Math.min(startX + tileSize, fullWidth);
      int endY = Math.min(startY + tileSize, fullHeight);
      
      int tileWidth = endX - startX;
      int tileHeight = endY - startY;
      
      if (tileWidth <= 0 || tileHeight <= 0) {
        return null;
      }
      
      double[] tileData = new double[tileWidth * tileHeight];
      
      for (int y = 0; y < tileHeight; y++) {
        for (int x = 0; x < tileWidth; x++) {
          int fullIndex = (startY + y) * fullWidth + (startX + x);
          int tileIndex = y * tileWidth + x;
          
          if (fullIndex < fullData.length && tileIndex < tileData.length) {
            tileData[tileIndex] = fullData[fullIndex];
          }
        }
      }
      
      return tileData;
      
    } catch (Exception e) {
      Log.e(TAG, "Error extracting elevation tile data: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Generates a cache key for elevation tile data.
   */
  private String generateElevationTileKey(String layerId, int tileX, int tileY) {
    return String.format("%s_tile_%d_%d", layerId, tileX, tileY);
  }
  
  /**
   * Evicts oldest elevation cache entries to manage memory usage.
   */
  private void evictOldestElevationCacheEntries() {
    try {
      int entriesToRemove = elevationTileCache.size() - MAX_ELEVATION_CACHE_SIZE + 10;
      
      if (entriesToRemove <= 0) {
        return;
      }
      
      List<String> keysToRemove = new ArrayList<>();
      int count = 0;
      
      for (String key : elevationTileCache.keySet()) {
        if (count >= entriesToRemove) {
          break;
        }
        keysToRemove.add(key);
        count++;
      }
      
      for (String key : keysToRemove) {
        elevationTileCache.remove(key);
      }
      
      Log.d(TAG, "Evicted " + keysToRemove.size() + " old elevation cache entries");
      
    } catch (Exception e) {
      Log.w(TAG, "Error evicting elevation cache entries: " + e.getMessage());
    }
  }
  
  /**
   * Fast zoom-aware tile-based terrain visualization.
   * Creates different resolution tiles based on zoom level for sharp rendering at all scales.
   * Properly cleans up previous layers to prevent overlaying issues.
   */
  private void updateSimpleTerrainVisualization(String layerId, Map<String, Object> layerConfig, 
                                               double[] elevationData, Integer width, Integer height, 
                                               List<Double> bounds, Double referenceAltitude, Double warningAltitude) {
    try {
      double currentZoom = mapLibreMap.getCameraPosition().zoom;
      Log.d(TAG, "FAST TILE-BASED terrain update - layer: " + layerId + " zoom: " + String.format("%.1f", currentZoom));
      
      // CRITICAL: Clean up ALL previous terrain layers first to prevent overlaying
      cleanupAllTerrainLayers(layerId);
      
      // Determine tile strategy based on zoom level for optimal performance
      if (currentZoom < 4.0) {
        // Very low zoom - single coarse tile for max speed
        createSingleCoarseTile(layerId, elevationData, width, height, bounds, referenceAltitude, warningAltitude);
      } else if (currentZoom < 7.0) {
        // Medium zoom - 4 medium-resolution tiles for balanced performance
        createMediumZoomTiles(layerId, elevationData, width, height, bounds, referenceAltitude, warningAltitude, currentZoom);
      } else {
        // High zoom - sharp detailed tiles for current viewport only
        createHighZoomDetailTiles(layerId, elevationData, width, height, bounds, referenceAltitude, warningAltitude, currentZoom);
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error in fast tile-based terrain visualization: " + e.getMessage(), e);
    }
  }
  
  /**
   * CRITICAL: Removes ALL terrain-related layers and sources to prevent layer stacking.
   * This fixes the multiple overlaid layers issue.
   */
  private void cleanupAllTerrainLayers(String layerId) {
    try {
      if (style == null) return;
      
      List<String> layersToRemove = new ArrayList<>();
      List<String> sourcesToRemove = new ArrayList<>();
      
      // Find ALL terrain-related layers and sources for this layerId
      String basePattern = layerId;
      
      // Check for various terrain layer naming patterns
      for (Layer layer : style.getLayers()) {
        String id = layer.getId();
        if (id.startsWith(basePattern + "-terrain") || 
            id.startsWith(basePattern + "-tile") || 
            id.startsWith(basePattern + "-coarse") ||
            id.startsWith(basePattern + "-medium") ||
            id.startsWith(basePattern + "-detail")) {
          layersToRemove.add(id);
        }
      }
      
      // Check for terrain sources
      for (Source source : style.getSources()) {
        String id = source.getId();
        if (id.startsWith(basePattern + "-source") || 
            id.startsWith(basePattern + "-tile") ||
            id.startsWith(basePattern + "-coarse") ||
            id.startsWith(basePattern + "-medium") ||
            id.startsWith(basePattern + "-detail")) {
          sourcesToRemove.add(id);
        }
      }
      
      // Remove layers first, then sources
      for (String layerIdToRemove : layersToRemove) {
        style.removeLayer(layerIdToRemove);
      }
      
      for (String sourceIdToRemove : sourcesToRemove) {
        style.removeSource(sourceIdToRemove);
      }
      
      if (!layersToRemove.isEmpty() || !sourcesToRemove.isEmpty()) {
        Log.d(TAG, "Cleaned up " + layersToRemove.size() + " layers and " + sourcesToRemove.size() + " sources for " + layerId);
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error cleaning up terrain layers: " + e.getMessage(), e);
    }
  }
  
  /**
   * Creates a single coarse tile for very low zoom levels (zoom < 4).
   * Maximum performance with acceptable quality at world view.
   */
  private void createSingleCoarseTile(String layerId, double[] elevationData, int width, int height, 
                                     List<Double> bounds, double referenceAltitude, double warningAltitude) {
    try {
      Log.d(TAG, "Creating single coarse tile for max speed");
      
      // Create a lower-resolution bitmap for speed (quarter resolution)
      int coarseWidth = Math.max(64, width / 4);
      int coarseHeight = Math.max(64, height / 4);
      
      // Downsample elevation data for speed
      double[] coarseElevationData = downsampleElevationData(elevationData, width, height, coarseWidth, coarseHeight);
      
      // Create bitmap
      Bitmap coarseBitmap = createSimpleBitmap(coarseElevationData, coarseWidth, coarseHeight, referenceAltitude, warningAltitude);
      
      if (coarseBitmap == null) {
        Log.e(TAG, "Failed to create coarse bitmap");
        return;
      }
      
      // Create single layer covering full bounds
      String coarseLayerId = layerId + "-coarse";
      String coarseSourceId = layerId + "-coarse-source";
      
      double west = bounds.get(0);
      double south = bounds.get(1);
      double east = bounds.get(2);
      double north = bounds.get(3);
      
      LatLng nw = new LatLng(north, west);
      LatLng ne = new LatLng(north, east);
      LatLng se = new LatLng(south, east);
      LatLng sw = new LatLng(south, west);
      
      ImageSource coarseSource = new ImageSource(coarseSourceId, new LatLngQuad(nw, ne, se, sw), coarseBitmap);
      style.addSource(coarseSource);
      
      RasterLayer coarseLayer = new RasterLayer(coarseLayerId, coarseSourceId);
      coarseLayer.setProperties(
          PropertyFactory.rasterOpacity(0.6f),
          PropertyFactory.rasterFadeDuration(0.0f)
      );
      
      style.addLayer(coarseLayer);
      
      Log.d(TAG, "Created coarse tile: " + coarseWidth + "x" + coarseHeight + " pixels");
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating coarse tile: " + e.getMessage(), e);
    }
  }
  
  /**
   * Creates 4 medium-resolution tiles for balanced performance at medium zoom (4-7).
   */
  private void createMediumZoomTiles(String layerId, double[] elevationData, int width, int height, 
                                    List<Double> bounds, double referenceAltitude, double warningAltitude, double zoom) {
    try {
      Log.d(TAG, "Creating 4 medium-resolution tiles for zoom " + String.format("%.1f", zoom));
      
      double west = bounds.get(0);
      double south = bounds.get(1);
      double east = bounds.get(2);
      double north = bounds.get(3);
      
      double midLng = (west + east) / 2.0;
      double midLat = (south + north) / 2.0;
      
      // Define 4 tile areas
      double[][][] tileAreas = {
          {{west, midLat, midLng, north}}, // NW
          {{midLng, midLat, east, north}}, // NE  
          {{west, south, midLng, midLat}}, // SW
          {{midLng, south, east, midLat}}  // SE
      };
      
      String[] tileNames = {"nw", "ne", "sw", "se"};
      
      // Medium resolution (half of original)
      int mediumWidth = Math.max(128, width / 2);
      int mediumHeight = Math.max(128, height / 2);
      
      for (int i = 0; i < 4; i++) {
        double tileWest = tileAreas[i][0][0];
        double tileSouth = tileAreas[i][0][1];
        double tileEast = tileAreas[i][0][2];
        double tileNorth = tileAreas[i][0][3];
        
        // Extract elevation data for this tile area
        double[] tileElevationData = extractElevationForArea(elevationData, width, height, bounds, 
                                                           tileWest, tileSouth, tileEast, tileNorth, 
                                                           mediumWidth, mediumHeight);
        
        if (tileElevationData != null) {
          // Create bitmap for this tile
          Bitmap tileBitmap = createSimpleBitmap(tileElevationData, mediumWidth, mediumHeight, referenceAltitude, warningAltitude);
          
          if (tileBitmap != null) {
            // Create layer for this tile
            String tileLayerId = layerId + "-medium-" + tileNames[i];
            String tileSourceId = layerId + "-medium-source-" + tileNames[i];
            
            LatLng nw = new LatLng(tileNorth, tileWest);
            LatLng ne = new LatLng(tileNorth, tileEast);
            LatLng se = new LatLng(tileSouth, tileEast);
            LatLng sw = new LatLng(tileSouth, tileWest);
            
            ImageSource tileSource = new ImageSource(tileSourceId, new LatLngQuad(nw, ne, se, sw), tileBitmap);
            style.addSource(tileSource);
            
            RasterLayer tileLayer = new RasterLayer(tileLayerId, tileSourceId);
            tileLayer.setProperties(
                PropertyFactory.rasterOpacity(0.6f),
                PropertyFactory.rasterFadeDuration(0.0f)
            );
            
            style.addLayer(tileLayer);
          }
        }
      }
      
      Log.d(TAG, "Created 4 medium tiles at " + mediumWidth + "x" + mediumHeight + " pixels each");
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating medium zoom tiles: " + e.getMessage(), e);
    }
  }
  
  /**
   * Creates high-detail tiles for current viewport only at high zoom (7+).
   * Maximum sharpness where needed, ignoring areas outside viewport for performance.
   */
  private void createHighZoomDetailTiles(String layerId, double[] elevationData, int width, int height, 
                                        List<Double> bounds, double referenceAltitude, double warningAltitude, double zoom) {
    try {
      Log.d(TAG, "Creating high-detail viewport tiles for zoom " + String.format("%.1f", zoom));
      
      // Get current viewport bounds
      LatLngBounds viewportBounds = mapLibreMap.getProjection().getVisibleRegion().latLngBounds;
      
      // Expand viewport slightly for smooth panning
      double latSpan = viewportBounds.getLatNorth() - viewportBounds.getLatSouth();
      double lngSpan = viewportBounds.getLonEast() - viewportBounds.getLonWest();
      
      double expandedNorth = Math.min(90.0, viewportBounds.getLatNorth() + latSpan * 0.1);
      double expandedSouth = Math.max(-90.0, viewportBounds.getLatSouth() - latSpan * 0.1);
      double expandedEast = Math.min(180.0, viewportBounds.getLonEast() + lngSpan * 0.1);
      double expandedWest = Math.max(-180.0, viewportBounds.getLonWest() - lngSpan * 0.1);
      
      // High resolution for sharp detail
      int detailTileSize = 512; // Fixed high-resolution tile size
      
      // Create 2x2 grid of detail tiles covering expanded viewport
      double tileLngSpan = (expandedEast - expandedWest) / 2.0;
      double tileLatSpan = (expandedNorth - expandedSouth) / 2.0;
      
      int tileIndex = 0;
      for (int row = 0; row < 2; row++) {
        for (int col = 0; col < 2; col++) {
          double tileWest = expandedWest + col * tileLngSpan;
          double tileEast = expandedWest + (col + 1) * tileLngSpan;
          double tileSouth = expandedSouth + row * tileLatSpan;
          double tileNorth = expandedSouth + (row + 1) * tileLatSpan;
          
          // Extract high-resolution elevation data for this tile
          double[] tileElevationData = extractElevationForArea(elevationData, width, height, bounds, 
                                                             tileWest, tileSouth, tileEast, tileNorth, 
                                                             detailTileSize, detailTileSize);
          
          if (tileElevationData != null) {
            // Create high-resolution bitmap
            Bitmap detailBitmap = createSimpleBitmap(tileElevationData, detailTileSize, detailTileSize, referenceAltitude, warningAltitude);
            
            if (detailBitmap != null) {
              // Create detail layer
              String detailLayerId = layerId + "-detail-" + tileIndex;
              String detailSourceId = layerId + "-detail-source-" + tileIndex;
              
              LatLng nw = new LatLng(tileNorth, tileWest);
              LatLng ne = new LatLng(tileNorth, tileEast);
              LatLng se = new LatLng(tileSouth, tileEast);
              LatLng sw = new LatLng(tileSouth, tileWest);
              
              ImageSource detailSource = new ImageSource(detailSourceId, new LatLngQuad(nw, ne, se, sw), detailBitmap);
              style.addSource(detailSource);
              
              RasterLayer detailLayer = new RasterLayer(detailLayerId, detailSourceId);
              detailLayer.setProperties(
                  PropertyFactory.rasterOpacity(0.6f),
                  PropertyFactory.rasterFadeDuration(0.0f)
              );
              
              style.addLayer(detailLayer);
              
              tileIndex++;
            }
          }
        }
      }
      
      Log.d(TAG, "Created " + tileIndex + " high-detail viewport tiles at " + detailTileSize + "x" + detailTileSize + " pixels each");
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating high zoom detail tiles: " + e.getMessage(), e);
    }
  }
  
  /**
   * Downsamples elevation data for performance at low zoom levels.
   */
  private double[] downsampleElevationData(double[] originalData, int originalWidth, int originalHeight, 
                                          int newWidth, int newHeight) {
    try {
      double[] downsampled = new double[newWidth * newHeight];
      
      double xRatio = (double) originalWidth / newWidth;
      double yRatio = (double) originalHeight / newHeight;
      
      for (int y = 0; y < newHeight; y++) {
        for (int x = 0; x < newWidth; x++) {
          int origX = Math.min(originalWidth - 1, (int) (x * xRatio));
          int origY = Math.min(originalHeight - 1, (int) (y * yRatio));
          int origIndex = origY * originalWidth + origX;
          
          if (origIndex < originalData.length) {
            downsampled[y * newWidth + x] = originalData[origIndex];
          }
        }
      }
      
      return downsampled;
      
    } catch (Exception e) {
      Log.e(TAG, "Error downsampling elevation data: " + e.getMessage(), e);
      return originalData;
    }
  }
  
  /**
   * Extracts elevation data for a specific geographic area.
   */
  private double[] extractElevationForArea(double[] fullElevationData, int fullWidth, int fullHeight, 
                                          List<Double> fullBounds, double areaWest, double areaSouth, 
                                          double areaEast, double areaNorth, int targetWidth, int targetHeight) {
    try {
      double fullWest = fullBounds.get(0);
      double fullSouth = fullBounds.get(1);
      double fullEast = fullBounds.get(2);
      double fullNorth = fullBounds.get(3);
      
      double fullLngSpan = fullEast - fullWest;
      double fullLatSpan = fullNorth - fullSouth;
      double areaLngSpan = areaEast - areaWest;
      double areaLatSpan = areaNorth - areaSouth;
      
      double[] areaData = new double[targetWidth * targetHeight];
      
      // Sample elevation data for the target area
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          // Convert area pixel to geographic coordinate
          double lng = areaWest + (x / (double) targetWidth) * areaLngSpan;
          double lat = areaNorth - (y / (double) targetHeight) * areaLatSpan; // Flip Y
          
          // Convert geographic coordinate to full data index
          double fullX = ((lng - fullWest) / fullLngSpan) * fullWidth;
          double fullY = ((fullNorth - lat) / fullLatSpan) * fullHeight; // Flip Y
          
          // Clamp to valid indices
          int fullXIndex = Math.max(0, Math.min(fullWidth - 1, (int) Math.round(fullX)));
          int fullYIndex = Math.max(0, Math.min(fullHeight - 1, (int) Math.round(fullY)));
          
          // Get elevation value
          int fullIndex = fullYIndex * fullWidth + fullXIndex;
          if (fullIndex >= 0 && fullIndex < fullElevationData.length) {
            areaData[y * targetWidth + x] = fullElevationData[fullIndex];
          }
        }
      }
      
      return areaData;
      
    } catch (Exception e) {
      Log.e(TAG, "Error extracting elevation for area: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Creates a simple terrain bitmap with basic coloring - no LUT, no caching.
   */
  private Bitmap createSimpleBitmap(double[] elevationData, int width, int height, 
                                   double referenceAltitude, double warningAltitude) {
    try {
      // Convert altitudes from feet to meters
      double refAltM = referenceAltitude * 0.3048;
      double warnAltM = warningAltitude * 0.3048;
      
      // Create bitmap
      Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
      int[] pixels = new int[width * height];
      
      // Simple color mapping - no LUT
      for (int i = 0; i < Math.min(elevationData.length, pixels.length); i++) {
        double elev = elevationData[i];
        if (elev < warnAltM) {
          pixels[i] = 0x80FF0000; // Red
        } else if (elev < refAltM) {
          pixels[i] = 0x80FFFF00; // Yellow
        } else {
          pixels[i] = 0x8000FF00; // Green
        }
      }
      
      bitmap.setPixels(pixels, 0, width, 0, 0, width, height);
      return bitmap;
      
    } catch (Exception e) {
      Log.e(TAG, "Error creating simple bitmap: " + e.getMessage(), e);
      return null;
    }
  }
  
  /**
   * Implements debounced altitude updates to batch changes and minimize redundant work.
   * This mirrors the HTTP LERC layer's debouncing strategy for smooth altitude slider updates.
   */
  private void debouncedAltitudeUpdate(String layerId, double referenceAltitude, double warningAltitude) {
    try {
      // Get or create debounce handler for this layer
      android.os.Handler handler = debounceHandlers.get(layerId);
      if (handler == null) {
        handler = new android.os.Handler(android.os.Looper.getMainLooper());
        debounceHandlers.put(layerId, handler);
      }
      
      // Remove any pending update for this layer
      handler.removeCallbacksAndMessages(null);
      
      // Schedule new debounced update
      handler.postDelayed(new Runnable() {
        @Override
        public void run() {
          try {
            Log.d(TAG, "Executing debounced altitude update for layer: " + layerId);
            
            // Get layer configuration
            Object layerObj = nativeLercCanvasLayers.get(layerId);
            if (layerObj instanceof Map) {
              @SuppressWarnings("unchecked")
              Map<String, Object> layerConfig = (Map<String, Object>) layerObj;
              
              // Update altitude thresholds
              layerConfig.put("referenceAltitude", referenceAltitude);
              layerConfig.put("warningAltitude", warningAltitude);
              
              // Increment cache-busting version
              Integer version = cacheBustingVersions.get(layerId);
              if (version == null) {
                version = 0;
              }
              version++;
              cacheBustingVersions.put(layerId, version);
              
              Log.d(TAG, "Incremented cache-busting version to " + version + " for layer: " + layerId);
              
              // Perform the actual terrain update
              double[] elevationData = (double[]) layerConfig.get("elevationData");
              Integer width = (Integer) layerConfig.get("width");
              Integer height = (Integer) layerConfig.get("height");
              List<Double> bounds = (List<Double>) layerConfig.get("bounds");
              
              if (elevationData != null && width != null && height != null && bounds != null) {
                updateTerrainVisualization(layerId, layerConfig, elevationData, width, height, 
                                          bounds, referenceAltitude, warningAltitude);
              }
            }
            
          } catch (Exception e) {
            Log.e(TAG, "Error in debounced altitude update: " + e.getMessage(), e);
          }
        }
      }, DEBOUNCE_DELAY_MS);
      
      Log.v(TAG, "Scheduled debounced altitude update for layer: " + layerId + " (delay: " + DEBOUNCE_DELAY_MS + "ms)");
      
    } catch (Exception e) {
      Log.e(TAG, "Error scheduling debounced altitude update: " + e.getMessage(), e);
    }
  }
  
  // Zoom-level caching for native terrain updates (like HTTP tiles)
  private final Map<String, Integer> lastTerrainUpdateZoom = new ConcurrentHashMap<>();
  private final Map<String, Long> lastTerrainUpdateTime = new ConcurrentHashMap<>();
  
  /**
   * OPTIMIZED: Updates native LERC terrain tiles only on significant zoom changes.
   * This eliminates the lag during smooth zoom animations by implementing zoom-level-based
   * caching similar to HTTP tile behavior. Terrain tiles are only regenerated when:
   * 1. Discrete zoom level changes (floor of zoom changes)
   * 2. Sufficient time has passed since last update (prevents spam)
   * 3. Altitude thresholds have changed
   * 
   * This matches the efficient tile reuse behavior of HTTP-based terrain layers.
   */
  private void updateNativeLercTilesForCurrentViewOptimized() {
    try {
      if (style == null || mapLibreMap == null) {
        return;
      }
      
      CameraPosition currentCamera = mapLibreMap.getCameraPosition();
      if (currentCamera == null) {
        return;
      }
      
      double currentZoom = currentCamera.zoom;
      int discreteZoom = (int) Math.floor(currentZoom); // Use discrete zoom level like HTTP tiles
      long currentTime = System.currentTimeMillis();
      
      // Process each native LERC layer
      for (Map.Entry<String, Object> entry : nativeLercCanvasLayers.entrySet()) {
        String layerId = entry.getKey();
        Object layerObj = entry.getValue();
        
        if (!(layerObj instanceof Map)) {
          continue;
        }
        
        @SuppressWarnings("unchecked")
        Map<String, Object> layerConfig = (Map<String, Object>) layerObj;
        
        // Check if layer is initialized and not disposed
        Boolean initialized = (Boolean) layerConfig.get("initialized");
        Boolean disposed = (Boolean) layerConfig.get("disposed");
        
        if (initialized == null || !initialized || (disposed != null && disposed)) {
          continue;
        }
        
        // OPTIMIZATION: Check if update is needed based on zoom level caching
        Integer lastZoom = lastTerrainUpdateZoom.get(layerId);
        Long lastUpdateTime = lastTerrainUpdateTime.get(layerId);
        
        boolean shouldUpdate = false;
        String updateReason = "";
        
        if (lastZoom == null) {
          // First update for this layer
          shouldUpdate = true;
          updateReason = "initial";
        } else if (discreteZoom != lastZoom) {
          // Discrete zoom level changed (like HTTP tile zoom levels)
          shouldUpdate = true;
          updateReason = "zoom change (" + lastZoom + " → " + discreteZoom + ")";
        } else if (lastUpdateTime == null || (currentTime - lastUpdateTime) > 5000) {
          // Force update if more than 5 seconds since last update (for altitude changes)
          shouldUpdate = true;
          updateReason = "time threshold (>5s since last update)";
        }
        
        if (!shouldUpdate) {
          // Skip update - reuse cached terrain tiles like HTTP tiles do
          Log.v(TAG, "SKIPPING terrain update for " + layerId + " - reusing tiles at zoom " + discreteZoom + " (smooth zoom from " + String.format("%.1f", currentZoom) + ")");
          continue;
        }
        
        Log.d(TAG, "UPDATING terrain tiles for " + layerId + " - reason: " + updateReason + " (zoom: " + String.format("%.1f", currentZoom) + " → discrete: " + discreteZoom + ")");
        
        // Update tracking variables
        lastTerrainUpdateZoom.put(layerId, discreteZoom);
        lastTerrainUpdateTime.put(layerId, currentTime);
        
        // Get layer data
        double[] elevationData = (double[]) layerConfig.get("elevationData");
        Integer width = (Integer) layerConfig.get("width");
        Integer height = (Integer) layerConfig.get("height");
        List<Double> bounds = (List<Double>) layerConfig.get("bounds");
        Double referenceAltitude = (Double) layerConfig.get("referenceAltitude");
        Double warningAltitude = (Double) layerConfig.get("warningAltitude");
        
        if (elevationData == null || width == null || height == null || 
            bounds == null || referenceAltitude == null || warningAltitude == null) {
          Log.w(TAG, "Skipping terrain update - missing data for layer: " + layerId);
          continue;
        }
        
        // Perform the optimized terrain visualization update
        updateTerrainVisualization(layerId, layerConfig, elevationData, width, height, 
                                  bounds, referenceAltitude, warningAltitude);
      }
      
    } catch (Exception e) {
      Log.e(TAG, "Error in optimized native LERC tiles update: " + e.getMessage(), e);
    }
  }
}
