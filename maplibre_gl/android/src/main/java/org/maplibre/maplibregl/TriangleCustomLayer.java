package org.maplibre.maplibregl;

import android.util.Log;
import androidx.annotation.NonNull;

import java.util.Map;
import java.util.List;
import java.util.ArrayList;

/**
 * Native OpenGL ES triangle renderer that integrates with MapLibre CustomLayer.
 * This class provides high-performance triangle rendering using GPU shaders and vertex buffers.
 */
public class TriangleCustomLayer {
    private static final String TAG = "TriangleCustomLayer";
    
    static {
        try {
            System.loadLibrary("triangle_renderer");
            Log.d(TAG, "Successfully loaded triangle_renderer native library");
        } catch (UnsatisfiedLinkError e) {
            Log.e(TAG, "Failed to load triangle_renderer native library", e);
        }
    }
    
    private final String layerId;
    private final Map<String, Object> properties;
    private long nativeRendererId = 0;
    
    // Triangle properties
    private float triangleSize = 5.0f;
    private String triangleColor = "#000000";
    private float triangleOpacity = 1.0f;
    private float triangleRotation = 0.0f;
    private float triangleStrokeWidth = 0.0f;
    private String triangleStrokeColor = "#000000";
    private float triangleStrokeOpacity = 1.0f;
    
    // Triangle data
    private List<TriangleInstance> triangles = new ArrayList<>();
    
    // Native method declarations
    private native long createTriangleRenderer();
    private native void destroyTriangleRenderer(long rendererId);
    private native void updateTriangles(long rendererId, float[] triangleData, int count);
    private native void renderTriangles(long rendererId, float[] mvpMatrix);
    private native void setProperties(long rendererId, 
        float size, float[] color, float opacity, float[] translate,
        float rotation, float blur, float strokeWidth, float[] strokeColor, 
        float strokeOpacity);
    
    public TriangleCustomLayer(@NonNull String layerId, @NonNull Map<String, Object> properties) {
        this.layerId = layerId;
        this.properties = properties;
        parseProperties(properties);
        
        Log.d(TAG, "Created TriangleCustomLayer: " + layerId);
    }
    
    /**
     * Initialize the native renderer. This should be called when the OpenGL context is ready.
     * 
     * @return The native renderer pointer for use with CustomLayer
     */
    public long initialize() {
        if (nativeRendererId == 0) {
            try {
                nativeRendererId = createTriangleRenderer();
                Log.d(TAG, "Initialized native triangle renderer: " + nativeRendererId);
            } catch (UnsatisfiedLinkError e) {
                Log.e(TAG, "Failed to create native triangle renderer", e);
                return 0;
            }
        }
        return nativeRendererId;
    }
    
    /**
     * Render triangles with the given MVP matrix.
     */
    public void render(float[] mvpMatrix) {
        if (nativeRendererId != 0 && !triangles.isEmpty()) {
            try {
                // Convert triangles to native format
                float[] triangleData = convertTrianglesToNativeFormat();
                updateTriangles(nativeRendererId, triangleData, triangles.size());
                renderTriangles(nativeRendererId, mvpMatrix);
            } catch (UnsatisfiedLinkError e) {
                Log.e(TAG, "Failed to render triangles", e);
            }
        }
    }
    
    /**
     * Clean up native resources.
     */
    public void cleanup() {
        if (nativeRendererId != 0) {
            try {
                destroyTriangleRenderer(nativeRendererId);
                Log.d(TAG, "Cleaned up native triangle renderer: " + nativeRendererId);
            } catch (UnsatisfiedLinkError e) {
                Log.e(TAG, "Failed to destroy native triangle renderer", e);
            } finally {
                nativeRendererId = 0;
            }
        }
    }
    
    /**
     * Update triangle data from GeoJSON features.
     */
    public void updateFromGeoJsonSource(String sourceName) {
        // This would typically get data from the MapLibre source
        // For now, we'll use sample data
        createSampleTriangles();
        Log.d(TAG, "Updated triangle data from source: " + sourceName + ", triangles: " + triangles.size());
    }
    
    /**
     * Create sample triangle data for testing.
     */
    private void createSampleTriangles() {
        triangles.clear();
        
        // Create a few sample triangles
        float[] colors = parseColor(triangleColor);
        float[] strokeColors = parseColor(triangleStrokeColor);
        
        for (int i = 0; i < 3; i++) {
            TriangleInstance triangle = new TriangleInstance();
            triangle.centerX = -0.01f + (i * 0.01f);  // Spread them out slightly
            triangle.centerY = 0.0f;
            triangle.size = triangleSize * 0.001f;  // Convert to map units
            triangle.colorR = colors[0];
            triangle.colorG = colors[1]; 
            triangle.colorB = colors[2];
            triangle.opacity = triangleOpacity;
            triangle.rotation = triangleRotation + (i * 0.5f);  // Vary rotation
            triangle.strokeWidth = triangleStrokeWidth;
            triangle.strokeColorR = strokeColors[0];
            triangle.strokeColorG = strokeColors[1];
            triangle.strokeColorB = strokeColors[2];
            
            triangles.add(triangle);
        }
    }
    
    /**
     * Convert triangle instances to native format.
     * Each triangle needs 12 floats: centerX, centerY, size, colorR, colorG, colorB, 
     * opacity, rotation, strokeWidth, strokeColorR, strokeColorG, strokeColorB
     */
    private float[] convertTrianglesToNativeFormat() {
        float[] data = new float[triangles.size() * 12];
        
        for (int i = 0; i < triangles.size(); i++) {
            TriangleInstance triangle = triangles.get(i);
            int offset = i * 12;
            
            data[offset + 0] = triangle.centerX;
            data[offset + 1] = triangle.centerY;
            data[offset + 2] = triangle.size;
            data[offset + 3] = triangle.colorR;
            data[offset + 4] = triangle.colorG;
            data[offset + 5] = triangle.colorB;
            data[offset + 6] = triangle.opacity;
            data[offset + 7] = triangle.rotation;
            data[offset + 8] = triangle.strokeWidth;
            data[offset + 9] = triangle.strokeColorR;
            data[offset + 10] = triangle.strokeColorG;
            data[offset + 11] = triangle.strokeColorB;
        }
        
        return data;
    }
    
    private void parseProperties(Map<String, Object> properties) {
        if (properties == null) return;
        
        try {
            if (properties.containsKey("triangle-size")) {
                Object size = properties.get("triangle-size");
                if (size instanceof Number) {
                    triangleSize = ((Number) size).floatValue();
                }
            }
            
            if (properties.containsKey("triangle-color")) {
                Object color = properties.get("triangle-color");
                if (color instanceof String) {
                    triangleColor = (String) color;
                }
            }
            
            if (properties.containsKey("triangle-opacity")) {
                Object opacity = properties.get("triangle-opacity");
                if (opacity instanceof Number) {
                    triangleOpacity = ((Number) opacity).floatValue();
                }
            }
            
            if (properties.containsKey("triangle-rotation")) {
                Object rotation = properties.get("triangle-rotation");
                if (rotation instanceof Number) {
                    triangleRotation = ((Number) rotation).floatValue();
                }
            }
            
            if (properties.containsKey("triangle-stroke-width")) {
                Object strokeWidth = properties.get("triangle-stroke-width");
                if (strokeWidth instanceof Number) {
                    triangleStrokeWidth = ((Number) strokeWidth).floatValue();
                }
            }
            
            if (properties.containsKey("triangle-stroke-color")) {
                Object strokeColor = properties.get("triangle-stroke-color");
                if (strokeColor instanceof String) {
                    triangleStrokeColor = (String) strokeColor;
                }
            }
            
            if (properties.containsKey("triangle-stroke-opacity")) {
                Object strokeOpacity = properties.get("triangle-stroke-opacity");
                if (strokeOpacity instanceof Number) {
                    triangleStrokeOpacity = ((Number) strokeOpacity).floatValue();
                }
            }
            
        } catch (Exception e) {
            Log.e(TAG, "Error parsing triangle properties", e);
        }
    }
    
    private float[] parseColor(String colorStr) {
        if (colorStr == null) return new float[]{0.0f, 0.0f, 0.0f, 1.0f};
        
        try {
            if (colorStr.startsWith("#")) {
                int color = Integer.parseInt(colorStr.substring(1), 16);
                float r = ((color >> 16) & 0xFF) / 255.0f;
                float g = ((color >> 8) & 0xFF) / 255.0f;
                float b = (color & 0xFF) / 255.0f;
                return new float[]{r, g, b, 1.0f};
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to parse color: " + colorStr, e);
        }
        
        return new float[]{0.0f, 0.0f, 0.0f, 1.0f};
    }
    
    public String getLayerId() {
        return layerId;
    }
    
    public long getNativeRendererId() {
        return nativeRendererId;
    }
    
    // Triangle instance data structure
    private static class TriangleInstance {
        float centerX, centerY;
        float size;
        float colorR, colorG, colorB;
        float opacity;
        float rotation;
        float strokeWidth;
        float strokeColorR, strokeColorG, strokeColorB;
    }
}
