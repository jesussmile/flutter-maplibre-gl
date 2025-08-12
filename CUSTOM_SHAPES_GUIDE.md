# Custom Shapes Implementation Guide

## 🎯 Overview

You can create any custom shape following the triangle implementation pattern. The approach uses **symbol layers with programmatically generated bitmap icons** for GPU-accelerated rendering.

## 🔧 Implementation Pattern

### Step 1: Android Native Implementation (MapLibreMapController.java)

Add these methods for each new shape (using Square as an example):

```java
// 1. Create bitmap method
private Bitmap createSquareBitmap() {
  try {
    int size = 64; // 64x64 pixels for crisp rendering
    Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
    Canvas canvas = new Canvas(bitmap);
    
    // Create paint with anti-aliasing
    Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    paint.setColor(0xFF4A90E2); // Blue color
    paint.setStyle(Paint.Style.FILL);
    paint.setFilterBitmap(true);
    
    // Draw square (centered, with padding)
    float centerX = size / 2.0f;
    float centerY = size / 2.0f;
    float halfSize = size * 0.35f; // Same as triangle radius for consistency
    
    RectF squareRect = new RectF(
        centerX - halfSize,
        centerY - halfSize,
        centerX + halfSize,
        centerY + halfSize
    );
    
    canvas.drawRect(squareRect, paint);
    
    // Add stroke
    Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    strokePaint.setColor(0xFFFFFFFF); // White stroke
    strokePaint.setStyle(Paint.Style.STROKE);
    strokePaint.setStrokeWidth(2.0f);
    strokePaint.setFilterBitmap(true);
    canvas.drawRect(squareRect, strokePaint);
    
    Log.d(TAG, "Created square bitmap: " + size + "x" + size + " pixels");
    return bitmap;
  } catch (Exception e) {
    Log.e(TAG, "Error creating square bitmap: " + e.getMessage(), e);
    return null;
  }
}

// 2. Ensure icon exists method
private void ensureSquareIconExists() {
  final String squareIconId = "maplibre-square-icon";
  
  try {
    if (style != null && style.getImage(squareIconId) != null) {
      Log.v(TAG, "Square icon already exists: " + squareIconId);
      return;
    }
    
    Bitmap squareBitmap = createSquareBitmap();
    
    if (style != null && squareBitmap != null) {
      style.addImage(squareIconId, squareBitmap, false);
      Log.d(TAG, "Added square icon to style: " + squareIconId);
    } else {
      throw new RuntimeException("Cannot add square icon: style or bitmap is null");
    }
  } catch (Exception e) {
    Log.e(TAG, "Error ensuring square icon exists: " + e.getMessage(), e);
    throw new RuntimeException("Failed to create square icon", e);
  }
}

// 3. Add symbol layer method
private void addSquareSymbolLayer(
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
    final String squareIconId = "maplibre-square-icon";
    
    SymbolLayer symbolLayer = new SymbolLayer(layerName, sourceName);
    List<PropertyValue> symbolProperties = new ArrayList<>();
    
    // Set the square icon
    symbolProperties.add(PropertyFactory.iconImage(squareIconId));
    
    // Default symbol properties
    symbolProperties.add(PropertyFactory.iconSize(0.25f));
    symbolProperties.add(PropertyFactory.iconAllowOverlap(true));
    symbolProperties.add(PropertyFactory.iconIgnorePlacement(true));
    symbolProperties.add(PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_VIEWPORT));
    symbolProperties.add(PropertyFactory.iconPitchAlignment(Property.ICON_PITCH_ALIGNMENT_VIEWPORT));
    
    // Process square-specific properties
    if (properties != null) {
      for (PropertyValue<?> prop : properties) {
        if (prop != null) {
          try {
            switch (prop.name) {
              case "square-size":
                if (prop.value instanceof Number) {
                  float size = ((Number) prop.value).floatValue() / 64.0f;
                  symbolProperties.add(PropertyFactory.iconSize(size));
                }
                break;
              case "square-opacity":
                if (prop.value instanceof Number) {
                  symbolProperties.add(PropertyFactory.iconOpacity(((Number) prop.value).floatValue()));
                }
                break;
              case "square-rotation":
                if (prop.value instanceof Number) {
                  symbolProperties.add(PropertyFactory.iconRotate(((Number) prop.value).floatValue()));
                }
                break;
              // Add more properties as needed
            }
          } catch (Exception e) {
            Log.w(TAG, "Failed to process square property: " + prop.name + ", error: " + e.getMessage());
          }
        }
      }
    }
    
    symbolLayer.setProperties(symbolProperties.toArray(new PropertyValue[0]));
    
    // Set other layer properties
    if (sourceLayer != null) symbolLayer.setSourceLayer(sourceLayer);
    if (minZoom != null) symbolLayer.setMinZoom(minZoom);
    if (maxZoom != null) symbolLayer.setMaxZoom(maxZoom);
    if (filter != null) symbolLayer.setFilter(filter);
    
    // Add layer to style
    if (style != null) {
      if (belowLayerId != null) {
        style.addLayerBelow(symbolLayer, belowLayerId);
      } else {
        style.addLayer(symbolLayer);
      }
      
      Log.d(TAG, "Added square symbol layer: " + layerName + " with source: " + sourceName);
      
      if (enableInteraction) {
        interactiveFeatureLayerIds.add(layerName);
      }
    } else {
      throw new RuntimeException("Cannot add square symbol layer: style is null");
    }
  } catch (Exception e) {
    Log.e(TAG, "Error adding square symbol layer: " + layerName, e);
    throw new RuntimeException("Failed to add square symbol layer: " + layerName, e);
  }
}

// 4. Main layer method (add to onMethodCall switch statement)
private void addSquareLayer(
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
    Log.d(TAG, "Adding square symbol layer: " + layerName);
    
    // Create square icon if it doesn't exist
    ensureSquareIconExists();
    
    // Use symbol layer with square icon
    addSquareSymbolLayer(layerName, sourceName, belowLayerId, sourceLayer, minZoom, maxZoom, properties, enableInteraction, filter);
    
  } catch (Exception e) {
    Log.e(TAG, "Failed to create square layer: " + e.getMessage(), e);
    // Could add fallback here
  }
}
```

### Step 2: Add Method Channel Handler

Add this to the `onMethodCall` switch statement:

```java
case "squareLayer#add":
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
        LayerPropertyConverter.interpretSquareLayerProperties(call.argument("properties"));

    Expression filterExpression = parseFilter(filter);

    addSquareLayer(
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
```

## 🎨 Shape Examples

### Diamond Shape
```java
// Diamond bitmap creation
private Bitmap createDiamondBitmap() {
  // ... same setup as square
  
  Path diamondPath = new Path();
  float centerX = size / 2.0f;
  float centerY = size / 2.0f;
  float radius = size * 0.35f;
  
  // Diamond points
  diamondPath.moveTo(centerX, centerY - radius);        // Top
  diamondPath.lineTo(centerX + radius, centerY);        // Right
  diamondPath.lineTo(centerX, centerY + radius);        // Bottom
  diamondPath.lineTo(centerX - radius, centerY);        // Left
  diamondPath.close();
  
  canvas.drawPath(diamondPath, paint);
  // ... stroke code
}
```

### Pentagon Shape
```java
// Pentagon bitmap creation
private Bitmap createPentagonBitmap() {
  // ... same setup
  
  Path pentagonPath = new Path();
  float centerX = size / 2.0f;
  float centerY = size / 2.0f;
  float radius = size * 0.35f;
  
  // Pentagon points (5 vertices)
  for (int i = 0; i < 5; i++) {
    double angle = (i * 2 * Math.PI / 5) - (Math.PI / 2); // Start from top
    float x = centerX + (float)(radius * Math.cos(angle));
    float y = centerY + (float)(radius * Math.sin(angle));
    
    if (i == 0) {
      pentagonPath.moveTo(x, y);
    } else {
      pentagonPath.lineTo(x, y);
    }
  }
  pentagonPath.close();
  
  canvas.drawPath(pentagonPath, paint);
  // ... stroke code
}
```

### Star Shape
```java
// Star bitmap creation
private Bitmap createStarBitmap() {
  // ... same setup
  
  Path starPath = new Path();
  float centerX = size / 2.0f;
  float centerY = size / 2.0f;
  float outerRadius = size * 0.35f;
  float innerRadius = outerRadius * 0.4f;
  
  // 5-pointed star
  for (int i = 0; i < 10; i++) {
    double angle = (i * Math.PI / 5) - (Math.PI / 2);
    float radius = (i % 2 == 0) ? outerRadius : innerRadius;
    float x = centerX + (float)(radius * Math.cos(angle));
    float y = centerY + (float)(radius * Math.sin(angle));
    
    if (i == 0) {
      starPath.moveTo(x, y);
    } else {
      starPath.lineTo(x, y);
    }
  }
  starPath.close();
  
  canvas.drawPath(starPath, paint);
  // ... stroke code
}
```

### Arrow Shape
```java
// Arrow bitmap creation
private Bitmap createArrowBitmap() {
  // ... same setup
  
  Path arrowPath = new Path();
  float centerX = size / 2.0f;
  float centerY = size / 2.0f;
  float radius = size * 0.35f;
  
  // Arrow pointing up
  arrowPath.moveTo(centerX, centerY - radius);                    // Tip
  arrowPath.lineTo(centerX + radius * 0.6f, centerY - radius * 0.3f); // Right wing
  arrowPath.lineTo(centerX + radius * 0.3f, centerY - radius * 0.3f); // Right shoulder
  arrowPath.lineTo(centerX + radius * 0.3f, centerY + radius);     // Right tail
  arrowPath.lineTo(centerX - radius * 0.3f, centerY + radius);     // Left tail
  arrowPath.lineTo(centerX - radius * 0.3f, centerY - radius * 0.3f); // Left shoulder
  arrowPath.lineTo(centerX - radius * 0.6f, centerY - radius * 0.3f); // Left wing
  arrowPath.close();
  
  canvas.drawPath(arrowPath, paint);
  // ... stroke code
}
```

## 🚀 Usage Examples

### Flutter Implementation

```dart
// Add squares to your map
await controller.addLayer(
  'square-layer',
  'square-source', 
  SquareLayerProperties(
    squareSize: 2.0,
    squareColor: '#4A90E2',
    squareOpacity: 0.8,
  ),
);

// Add source with square features
await controller.addSource(
  'square-source',
  GeojsonSourceProperties(
    data: {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [-122.4194, 37.7749]
          },
          "properties": {
            "square-size": 3.0,
            "square-color": "#FF5722"
          }
        }
      ]
    },
  ),
);
```

## ✨ Advanced Features

### Color Variations
Create different colored versions of the same shape:

```java
private Bitmap createSquareBitmap(int color) {
  // ... same setup
  paint.setColor(color); // Use passed color instead of hardcoded
  // ... rest of implementation
}

// Usage
private void ensureSquareIconExists(String color) {
  final String squareIconId = "maplibre-square-icon-" + color;
  // ... check and create with specific color
}
```

### Dynamic Properties
Support data-driven styling:

```java
// In property processing
case "square-color":
  // Create different colored icons on demand
  if (prop.value instanceof String) {
    String colorHex = (String) prop.value;
    ensureSquareIconExists(colorHex);
    symbolProperties.add(PropertyFactory.iconImage("maplibre-square-icon-" + colorHex));
  }
  break;
```

## 📊 Performance Tips

1. **Reuse Bitmaps**: Create bitmaps once and reuse across features
2. **Batch Operations**: Add multiple shapes at once like triangles
3. **Fixed Size**: Keep all shape bitmaps at 64x64 for consistency
4. **Anti-aliasing**: Always use anti-aliasing for smooth edges
5. **Viewport Alignment**: Use viewport alignment to prevent zoom scaling

## 🔧 Complete Implementation Checklist

For each new shape:

- [ ] Create bitmap generation method
- [ ] Create icon existence check method  
- [ ] Create symbol layer method
- [ ] Create main layer method
- [ ] Add method channel handler
- [ ] Add property converter support
- [ ] Add Flutter layer properties class
- [ ] Create example usage
- [ ] Test with batch operations
- [ ] Document the new shape

This approach gives you unlimited flexibility to create any custom shape while maintaining excellent performance through MapLibre's optimized symbol rendering pipeline! 🎨
