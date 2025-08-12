package org.maplibre.maplibregl;

import android.util.Log;
import java.util.Map;

/**
 * Host wrapper for native triangle custom layer integration.
 * This class manages the lifecycle and data flow between MapLibre CustomLayer API
 * and the native C++ triangle renderer through JNI.
 */
public class TriangleCustomLayerHost {
    private static final String TAG = "TriangleCustomLayerHost";
    
    private final String layerId;
    private final Map<String, Object> properties;
    private long nativeHandle = 0;
    private boolean initialized = false;
    
    public TriangleCustomLayerHost(String layerId, Map<String, Object> properties) {
        this.layerId = layerId;
        this.properties = properties;
        Log.d(TAG, "Created TriangleCustomLayerHost for layer: " + layerId);
    }
    
    /**
     * Called when the OpenGL context is ready and the layer should initialize.
     * This corresponds to the CustomLayer initialize callback from native code.
     */
    public void onInitialize() {
        Log.d(TAG, "Triangle layer initialized: " + layerId);
        initialized = true;
        
        // Load any initial triangle data from properties
        loadTriangleDataFromProperties();
    }
    
    /**
     * Called every frame to render the triangles.
     * This corresponds to the CustomLayer render callback from native code.
     * 
     * @param transformationMatrix The 4x4 transformation matrix from MapLibre
     */
    public void onRender(float[] transformationMatrix) {
        // Native rendering is handled in C++, this is just for logging/debugging
        if (Log.isLoggable(TAG, Log.VERBOSE)) {
            Log.v(TAG, "Rendering triangles for layer: " + layerId);
        }
    }
    
    /**
     * Called when the layer is being destroyed and should clean up resources.
     * This corresponds to the CustomLayer deinitialize callback from native code.
     */
    public void onDeinitialize() {
        Log.d(TAG, "Triangle layer deinitialized: " + layerId);
        initialized = false;
        
        // Native cleanup is handled automatically in C++
    }
    
    /**
     * Sets the native handle for JNI communication.
     * This should be called by the MapLibreMapController when creating the CustomLayer.
     */
    public void setNativeHandle(long handle) {
        this.nativeHandle = handle;
        Log.d(TAG, "Set native handle for layer " + layerId + ": " + handle);
    }
    
    /**
     * Updates triangle rendering data in the native renderer.
     */
    public void updateTriangles(float[] vertices, int[] indices) {
        if (nativeHandle != 0 && vertices != null && indices != null) {
            updateTriangleData(nativeHandle, vertices, indices);
            Log.d(TAG, "Updated triangle data for layer " + layerId + ": " + 
                  vertices.length + " vertices, " + indices.length + " indices");
        } else {
            Log.w(TAG, "Cannot update triangles - native handle: " + nativeHandle + 
                  ", vertices: " + (vertices != null) + ", indices: " + (indices != null));
        }
    }
    
    /**
     * Sets triangle rendering properties like color.
     */
    public void setTriangleColor(float red, float green, float blue, float alpha) {
        if (nativeHandle != 0) {
            setTriangleProperties(nativeHandle, red, green, blue, alpha);
            Log.d(TAG, "Set triangle color for layer " + layerId + ": (" + 
                  red + ", " + green + ", " + blue + ", " + alpha + ")");
        } else {
            Log.w(TAG, "Cannot set triangle color - native handle is 0");
        }
    }
    
    /**
     * Loads triangle data from the properties map and updates the native renderer.
     */
    private void loadTriangleDataFromProperties() {
        if (properties == null || nativeHandle == 0) {
            return;
        }
        
        try {
            // Example: Load color from properties
            Object colorObj = properties.get("triangle-color");
            if (colorObj instanceof String) {
                String colorStr = (String) colorObj;
                float[] rgba = parseColor(colorStr);
                setTriangleColor(rgba[0], rgba[1], rgba[2], rgba[3]);
            } else if (colorObj instanceof Integer) {
                int colorInt = (Integer) colorObj;
                float[] rgba = parseColor(colorInt);
                setTriangleColor(rgba[0], rgba[1], rgba[2], rgba[3]);
            }
            
            // Example: Load opacity from properties
            Object opacityObj = properties.get("triangle-opacity");
            if (opacityObj instanceof Number) {
                float opacity = ((Number) opacityObj).floatValue();
                // Update the alpha component of current color
                setTriangleColor(1.0f, 1.0f, 1.0f, opacity); // Default to white with specified opacity
            }
            
            // For actual triangle geometry, you would typically load from GeoJSON source
            // This is just an example of creating a simple triangle
            createDefaultTriangle();
            
        } catch (Exception e) {
            Log.e(TAG, "Error loading triangle data from properties: " + e.getMessage(), e);
        }
    }
    
    /**
     * Creates a default triangle for testing purposes.
     */
    private void createDefaultTriangle() {
        // Simple triangle vertices (x, y, z coordinates)
        float[] vertices = {
            -0.5f, -0.5f, 0.0f,  // Bottom left
             0.5f, -0.5f, 0.0f,  // Bottom right
             0.0f,  0.5f, 0.0f   // Top center
        };
        
        // Triangle indices
        int[] indices = {
            0, 1, 2  // Single triangle
        };
        
        updateTriangles(vertices, indices);
    }
    
    /**
     * Parses a color string (e.g., "#FF0000") to RGBA float array.
     */
    private float[] parseColor(String colorStr) {
        try {
            if (colorStr.startsWith("#") && colorStr.length() == 7) {
                int color = Integer.parseInt(colorStr.substring(1), 16);
                return parseColor(color | 0xFF000000); // Add full alpha
            } else if (colorStr.startsWith("#") && colorStr.length() == 9) {
                long color = Long.parseLong(colorStr.substring(1), 16);
                return parseColor((int) color);
            }
        } catch (NumberFormatException e) {
            Log.w(TAG, "Failed to parse color string: " + colorStr, e);
        }
        
        // Default to black
        return new float[]{0.0f, 0.0f, 0.0f, 1.0f};
    }
    
    /**
     * Parses a color integer to RGBA float array.
     */
    private float[] parseColor(int color) {
        float red = ((color >> 16) & 0xFF) / 255.0f;
        float green = ((color >> 8) & 0xFF) / 255.0f;
        float blue = (color & 0xFF) / 255.0f;
        float alpha = ((color >> 24) & 0xFF) / 255.0f;
        
        return new float[]{red, green, blue, alpha};
    }
    
    // Native method declarations - implemented in triangle_layer_jni.cpp
    private native void updateTriangleData(long nativeHandle, float[] vertices, int[] indices);
    private native void setTriangleProperties(long nativeHandle, float red, float green, float blue, float alpha);
    
    // Getters
    public String getLayerId() {
        return layerId;
    }
    
    public boolean isInitialized() {
        return initialized;
    }
    
    public long getNativeHandle() {
        return nativeHandle;
    }
}
