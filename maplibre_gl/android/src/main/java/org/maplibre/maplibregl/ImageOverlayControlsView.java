package org.maplibre.maplibregl;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PointF;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;
import android.util.Log;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.ArrayList;
import android.view.ViewGroup;

import org.maplibre.android.geometry.LatLng;
import org.maplibre.android.maps.MapLibreMap;
import io.flutter.plugin.common.MethodChannel;

/**
 * Native Android view for rendering interactive image overlay controls
 * directly on the MapLibre map surface. Provides dragging, scaling, and 
 * stretching capabilities with native performance.
 */
public class ImageOverlayControlsView extends View {
    private static final String TAG = "ImageOverlayControls";
    
    // Control dimensions (dp converted to pixels)
    private float triangleSize;
    private float circleRadius;
    private float rectWidth;
    private float rectHeight;
    
    // Paint objects for rendering
    private Paint controlPaint;
    private Paint borderPaint;
    private Paint activePaint;
    
    // Coordinates and screen positions
    private List<LatLng> coordinates;
    private PointF[] screenPositions = new PointF[4]; // TL, TR, BR, BL
    private PointF centerPoint = new PointF();
    
    // Control areas for hit testing
    private Map<String, RectF> controlAreas = new HashMap<>();
    private String selectedControl = null;
    
    // Map and interaction state
    private MapLibreMap mapLibreMap;
    private String overlayId;
    private MethodChannel methodChannel;
    private float density;
    
    // Touch handling
    private float lastTouchX, lastTouchY;
    private boolean isDragging = false;
    
    // Movement sensitivity
    private double geoScale = 0.00005; // Default sensitivity

    public ImageOverlayControlsView(Context context, MapLibreMap mapLibreMap, 
                                  List<LatLng> coordinates, float density, 
                                  String overlayId, MethodChannel methodChannel) {
        super(context);
        this.mapLibreMap = mapLibreMap;
        this.coordinates = coordinates;
        this.density = density;
        this.overlayId = overlayId;
        this.methodChannel = methodChannel;
        
        initializePaints();
        initializeControlSizes();
        updateScreenPositions();
        
        // Make view fill the entire map
        setLayoutParams(new ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 
            ViewGroup.LayoutParams.MATCH_PARENT
        ));
        
        // Make view transparent except for controls
        setBackgroundColor(Color.TRANSPARENT);
        setWillNotDraw(false);
        
        // Listen to map changes for real-time position updates
        if (mapLibreMap != null) {
            mapLibreMap.addOnCameraMoveListener(new MapLibreMap.OnCameraMoveListener() {
                @Override
                public void onCameraMove() {
                    updateScreenPositions();
                    invalidate(); // Trigger redraw
                }
            });
            
            mapLibreMap.addOnCameraIdleListener(new MapLibreMap.OnCameraIdleListener() {
                @Override
                public void onCameraIdle() {
                    updateScreenPositions();
                    invalidate(); // Trigger redraw
                }
            });
        }
        
        Log.d(TAG, "ImageOverlayControlsView created for overlay: " + overlayId);
    }
    
    private void initializePaints() {
        // Main control paint (blue with transparency)
        controlPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        controlPaint.setColor(Color.argb(45, 25, 118, 210)); // #1976D2 with 18% opacity
        controlPaint.setStyle(Paint.Style.FILL);
        
        // Border paint (white with transparency)
        borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        borderPaint.setColor(Color.argb(179, 255, 255, 255)); // White with 70% opacity
        borderPaint.setStyle(Paint.Style.STROKE);
        borderPaint.setStrokeWidth(2f * density);
        
        // Active control paint (cyan)
        activePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        activePaint.setColor(Color.argb(115, 0, 255, 255)); // Cyan with 45% opacity
        activePaint.setStyle(Paint.Style.FILL);
    }
    
    private void initializeControlSizes() {
        // Calculate sizes based on image dimensions (similar to Flutter implementation)
        float avgDimension = 100f; // Default, will be updated when coordinates change
        triangleSize = Math.max(40f * density, Math.min(80f * density, avgDimension * 0.15f));
        circleRadius = triangleSize * 1.2f;
        rectWidth = triangleSize * 0.6f;
        rectHeight = triangleSize * 1.8f;
        
        Log.d(TAG, "Control sizes - triangle: " + triangleSize + ", circle: " + circleRadius);
    }
    
    public void updateCoordinates(List<LatLng> newCoordinates) {
        this.coordinates = newCoordinates;
        updateScreenPositions();
        updateControlSizes();
        invalidate(); // Trigger redraw
    }
    
    private void updateScreenPositions() {
        if (mapLibreMap == null || coordinates == null || coordinates.size() != 4) {
            return;
        }
        
        try {
            // Convert LatLng to screen coordinates
            for (int i = 0; i < 4; i++) {
                PointF screenPoint = mapLibreMap.getProjection().toScreenLocation(coordinates.get(i));
                screenPositions[i] = screenPoint;
            }
            
            // Calculate center point
            centerPoint.x = (screenPositions[0].x + screenPositions[2].x) / 2f;
            centerPoint.y = (screenPositions[0].y + screenPositions[2].y) / 2f;
            
            updateControlAreas();
            
        } catch (Exception e) {
            Log.e(TAG, "Error updating screen positions: " + e.getMessage());
        }
    }
    
    private void updateControlSizes() {
        if (screenPositions[0] != null && screenPositions[2] != null) {
            float width = Math.abs(screenPositions[1].x - screenPositions[0].x);
            float height = Math.abs(screenPositions[2].y - screenPositions[0].y);
            float avgDimension = (width + height) / 2f;
            
            triangleSize = Math.max(40f * density, Math.min(80f * density, avgDimension * 0.15f));
            circleRadius = triangleSize * 1.2f;
            rectWidth = triangleSize * 0.6f;
            rectHeight = triangleSize * 1.8f;
        }
    }
    
    private void updateControlAreas() {
        controlAreas.clear();
        
        if (screenPositions[0] == null) return;
        
        // Center circle (move control)
        controlAreas.put("center", new RectF(
            centerPoint.x - circleRadius,
            centerPoint.y - circleRadius,
            centerPoint.x + circleRadius,
            centerPoint.y + circleRadius
        ));
        
        // Corner triangles (scale controls)
        for (int i = 0; i < 4; i++) {
            String key = getCornerKey(i);
            PointF pos = screenPositions[i];
            controlAreas.put(key, new RectF(
                pos.x - triangleSize,
                pos.y - triangleSize,
                pos.x + triangleSize,
                pos.y + triangleSize
            ));
        }
        
        // Edge rectangles (stretch controls)
        addEdgeControls();
    }
    
    private void addEdgeControls() {
        // Top edge
        PointF topMid = new PointF(
            (screenPositions[0].x + screenPositions[1].x) / 2f,
            (screenPositions[0].y + screenPositions[1].y) / 2f
        );
        controlAreas.put("top", new RectF(
            topMid.x - rectWidth, topMid.y - rectHeight/2,
            topMid.x + rectWidth, topMid.y + rectHeight/2
        ));
        
        // Right edge
        PointF rightMid = new PointF(
            (screenPositions[1].x + screenPositions[2].x) / 2f,
            (screenPositions[1].y + screenPositions[2].y) / 2f
        );
        controlAreas.put("right", new RectF(
            rightMid.x - rectHeight/2, rightMid.y - rectWidth,
            rightMid.x + rectHeight/2, rightMid.y + rectWidth
        ));
        
        // Bottom edge
        PointF bottomMid = new PointF(
            (screenPositions[2].x + screenPositions[3].x) / 2f,
            (screenPositions[2].y + screenPositions[3].y) / 2f
        );
        controlAreas.put("bottom", new RectF(
            bottomMid.x - rectWidth, bottomMid.y - rectHeight/2,
            bottomMid.x + rectWidth, bottomMid.y + rectHeight/2
        ));
        
        // Left edge
        PointF leftMid = new PointF(
            (screenPositions[3].x + screenPositions[0].x) / 2f,
            (screenPositions[3].y + screenPositions[0].y) / 2f
        );
        controlAreas.put("left", new RectF(
            leftMid.x - rectHeight/2, leftMid.y - rectWidth,
            leftMid.x + rectHeight/2, leftMid.y + rectWidth
        ));
    }
    
    private String getCornerKey(int index) {
        switch(index) {
            case 0: return "topLeft";
            case 1: return "topRight";
            case 2: return "bottomRight";
            case 3: return "bottomLeft";
            default: return "unknown";
        }
    }
    
    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        
        if (screenPositions[0] == null) return;
        
        // Draw corner triangles
        for (int i = 0; i < 4; i++) {
            String key = getCornerKey(i);
            Paint paint = key.equals(selectedControl) ? activePaint : controlPaint;
            drawTriangle(canvas, screenPositions[i], paint);
        }
        
        // Draw center circle
        Paint centerPaint = "center".equals(selectedControl) ? activePaint : controlPaint;
        canvas.drawCircle(centerPoint.x, centerPoint.y, circleRadius, centerPaint);
        canvas.drawCircle(centerPoint.x, centerPoint.y, circleRadius, borderPaint);
        
        // Draw edge rectangles
        drawEdgeControls(canvas);
    }
    
    private void drawTriangle(Canvas canvas, PointF center, Paint paint) {
        float half = triangleSize;
        
        // Simple square for now (can be enhanced to actual triangle)
        canvas.drawRect(
            center.x - half, center.y - half,
            center.x + half, center.y + half,
            paint
        );
        canvas.drawRect(
            center.x - half, center.y - half,
            center.x + half, center.y + half,
            borderPaint
        );
    }
    
    private void drawEdgeControls(Canvas canvas) {
        String[] edges = {"top", "right", "bottom", "left"};
        for (String edge : edges) {
            RectF area = controlAreas.get(edge);
            if (area != null) {
                Paint paint = edge.equals(selectedControl) ? activePaint : controlPaint;
                canvas.drawRect(area, paint);
                canvas.drawRect(area, borderPaint);
            }
        }
    }
    
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        float x = event.getX();
        float y = event.getY();
        
        switch (event.getAction()) {
            case MotionEvent.ACTION_DOWN:
                selectedControl = getControlAtPoint(x, y);
                if (selectedControl != null) {
                    isDragging = true;
                    lastTouchX = x;
                    lastTouchY = y;
                    
                    // Send control selection to Flutter
                    Map<String, Object> selectionData = new HashMap<>();
                    selectionData.put("overlayId", overlayId);
                    selectionData.put("controlType", selectedControl);
                    selectionData.put("selected", true);
                    
                    try {
                        methodChannel.invokeMethod("imageOverlay#controlSelected", selectionData);
                    } catch (Exception e) {
                        Log.e(TAG, "Error sending control selection to Flutter: " + e.getMessage());
                    }
                    
                    invalidate();
                    return true;
                }
                break;
                
            case MotionEvent.ACTION_MOVE:
                if (isDragging && selectedControl != null) {
                    float deltaX = x - lastTouchX;
                    float deltaY = y - lastTouchY;
                    
                    handleControlMovement(selectedControl, deltaX, deltaY);
                    
                    lastTouchX = x;
                    lastTouchY = y;
                    return true;
                }
                break;
                
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (isDragging) {
                    isDragging = false;
                    selectedControl = null;
                    invalidate();
                    
                    // Send final coordinates to Flutter
                    sendCoordinatesToFlutter();
                    return true;
                }
                break;
        }
        
        return super.onTouchEvent(event);
    }
    
    private String getControlAtPoint(float x, float y) {
        for (Map.Entry<String, RectF> entry : controlAreas.entrySet()) {
            if (entry.getValue().contains(x, y)) {
                return entry.getKey();
            }
        }
        return null;
    }
    
    private void handleControlMovement(String control, float deltaX, float deltaY) {
        // Convert screen delta to geo coordinates
        double geoScale = getGeoScale(); // Use configurable sensitivity
        double deltaLng = deltaX * geoScale;
        double deltaLat = -deltaY * geoScale; // Y is inverted
        
        Log.d(TAG, "Control movement: " + control + " deltaX=" + deltaX + " deltaY=" + deltaY);
        
        List<LatLng> newCoordinates = new ArrayList<>(coordinates);
        
        switch (control) {
            case "center":
                // Move entire image
                for (LatLng coord : newCoordinates) {
                    coord.setLatitude(coord.getLatitude() + deltaLat);
                    coord.setLongitude(coord.getLongitude() + deltaLng);
                }
                break;
                
            case "topLeft":
            case "topRight":
            case "bottomRight":
            case "bottomLeft":
                // Use center-based scaling to maintain aspect ratio (no distortion)
                // Calculate center point
                double centerLat = (newCoordinates.get(0).getLatitude() + newCoordinates.get(2).getLatitude()) / 2.0;
                double centerLng = (newCoordinates.get(0).getLongitude() + newCoordinates.get(2).getLongitude()) / 2.0;
                
                // Calculate scale factor based on drag distance and direction
                double distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
                double scaleFactor = 1.0;
                
                // Determine scaling direction based on corner and drag direction
                switch (control) {
                    case "topLeft":
                        // Drag away from center (up-left) = grow, toward center (down-right) = shrink
                        scaleFactor = 1.0 + ((-deltaX - deltaY) * geoScale * 0.5);
                        break;
                    case "topRight":
                        // Drag away from center (up-right) = grow, toward center (down-left) = shrink
                        scaleFactor = 1.0 + ((deltaX - deltaY) * geoScale * 0.5);
                        break;
                    case "bottomRight":
                        // Drag away from center (down-right) = grow, toward center (up-left) = shrink
                        scaleFactor = 1.0 + ((deltaX + deltaY) * geoScale * 0.5);
                        break;
                    case "bottomLeft":
                        // Drag away from center (down-left) = grow, toward center (up-right) = shrink
                        scaleFactor = 1.0 + ((-deltaX + deltaY) * geoScale * 0.5);
                        break;
                }
                
                // Clamp scale factor to prevent extreme scaling
                scaleFactor = Math.max(0.1, Math.min(5.0, scaleFactor));
                
                // Apply uniform scaling from center to all corners (maintains aspect ratio)
                for (LatLng coord : newCoordinates) {
                    double latOffset = (coord.getLatitude() - centerLat) * scaleFactor;
                    double lngOffset = (coord.getLongitude() - centerLng) * scaleFactor;
                    coord.setLatitude(centerLat + latOffset);
                    coord.setLongitude(centerLng + lngOffset);
                }
                break;
                
            case "top":
                // Stretch top edge
                newCoordinates.get(0).setLatitude(newCoordinates.get(0).getLatitude() + deltaLat);
                newCoordinates.get(1).setLatitude(newCoordinates.get(1).getLatitude() + deltaLat);
                break;
                
            case "bottom":
                // Stretch bottom edge
                newCoordinates.get(2).setLatitude(newCoordinates.get(2).getLatitude() + deltaLat);
                newCoordinates.get(3).setLatitude(newCoordinates.get(3).getLatitude() + deltaLat);
                break;
                
            case "left":
                // Stretch left edge
                newCoordinates.get(0).setLongitude(newCoordinates.get(0).getLongitude() + deltaLng);
                newCoordinates.get(3).setLongitude(newCoordinates.get(3).getLongitude() + deltaLng);
                break;
                
            case "right":
                // Stretch right edge
                newCoordinates.get(1).setLongitude(newCoordinates.get(1).getLongitude() + deltaLng);
                newCoordinates.get(2).setLongitude(newCoordinates.get(2).getLongitude() + deltaLng);
                break;
        }
        
        // Update coordinates
        coordinates = newCoordinates;
        updateScreenPositions();
        invalidate();
        
        // Directly update the MapLibre image source with new coordinates
        updateMapLibreImageSource();
        
        // Send updated coordinates to Flutter to update the image overlay
        sendCoordinatesToFlutter();
    }
    
    private void sendCoordinatesToFlutter() {
        try {
            Map<String, Object> args = new HashMap<>();
            args.put("overlayId", overlayId);
            args.put("coordinates", coordinatesToList());
            
            Log.d(TAG, "Sending coordinates to Flutter: " + coordinatesToList());
            methodChannel.invokeMethod("imageOverlay#coordinatesChanged", args);
        } catch (Exception e) {
            Log.e(TAG, "Error sending coordinates to Flutter: " + e.getMessage());
        }
    }
    
    private List<List<Double>> coordinatesToList() {
        return coordinates.stream()
            .map(coord -> List.of(coord.getLongitude(), coord.getLatitude()))
            .collect(java.util.stream.Collectors.toList());
    }
    
    private void updateMapLibreImageSource() {
        if (mapLibreMap == null || coordinates.size() != 4) {
            return;
        }
        
        try {
            // Get the map style and update the image source
            org.maplibre.android.style.sources.ImageSource imageSource = 
                mapLibreMap.getStyle().getSourceAs(overlayId + "_source");
            
            if (imageSource != null) {
                // Create new LatLngQuad with updated coordinates
                org.maplibre.android.geometry.LatLngQuad newQuad = 
                    new org.maplibre.android.geometry.LatLngQuad(
                        coordinates.get(0), // topLeft
                        coordinates.get(1), // topRight
                        coordinates.get(2), // bottomRight
                        coordinates.get(3)  // bottomLeft
                    );
                
                // Update the image source coordinates
                imageSource.setCoordinates(newQuad);
                
                Log.d(TAG, "Updated MapLibre image source coordinates");
            } else {
                Log.w(TAG, "Image source not found: " + overlayId + "_source");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error updating MapLibre image source: " + e.getMessage());
        }
    }

    public void handleGesture(String gestureType, float screenX, float screenY, float deltaX, float deltaY) {
        // Handle gestures
    }
    
    private double getGeoScale() {
        return geoScale;
    }
    
    public void setSensitivity(double sensitivity) {
        this.geoScale = sensitivity;
        Log.d(TAG, "Updated movement sensitivity to: " + sensitivity);
    }
} 