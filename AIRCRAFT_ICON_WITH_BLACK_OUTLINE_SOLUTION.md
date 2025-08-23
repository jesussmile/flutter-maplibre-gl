# Aircraft Icon with Black Outline Solution

## Problem
When using SDF (Signed Distance Field) color tinting on PNG aircraft icons, the **entire icon** changes color uniformly, including the black outline. This makes light colors (yellow, white, green) difficult to see because the black outline also becomes light.

## Solutions

### Solution 1: Two-Layer Approach (Recommended) ⭐

Create **two separate PNG files** and layer them:

#### Step 1: Split Your Aircraft Icon

**File 1: `traffic-outline.png`**
- Contains ONLY the black outline/border
- Transparent interior
- Used as a fixed black overlay (no SDF tinting)

**File 2: `traffic-fill.png`** 
- Contains ONLY the inner aircraft shape
- No outline/border
- White or light gray interior for optimal tinting
- Used with SDF tinting for color changes

#### Step 2: Implementation

```dart
// Add both icons to MapLibre
await controller!.addRotatableSymbolPngLayers(
  sourceId: 'aircraft-source',
  baseLayerId: 'aircraft-symbols',
  aircraftIconPath: 'traffic-fill.png',      // Tintable inner area
  aircraftOutlinePath: 'traffic-outline.png', // Fixed black outline
  arrowIconPath: 'arrow.png',
  aircraftIconSize: 0.15,
  arrowIconSize: 0.12,
  enableInteraction: true,
  config: {
    'topLabelOffset': -2.5,
    'bottomLabelOffset': 2.5,
    'arrowOffsetX': 80.0,
    'useOutlineLayer': true, // Enable outline overlay
  },
);
```

#### Step 3: Layer Structure (Bottom to Top)
1. **Tintable Fill Layer** - Changes color based on proximity
2. **Fixed Outline Layer** - Always black for visibility
3. **Arrow Layer** - Color-coded status indicator
4. **Text Labels** - Altitude and callsign

### Solution 2: Pre-Generated Color Variants

Create multiple PNG files with different colored interiors but fixed black outlines:

#### Asset Structure
```
assets/
├── aircraft-red.png      # Red interior, black outline
├── aircraft-orange.png   # Orange interior, black outline  
├── aircraft-yellow.png   # Yellow interior, black outline
├── aircraft-green.png    # Green interior, black outline
└── arrow.png            # Reusable arrow
```

#### Implementation
```dart
String getAircraftIcon(double proximityDistance) {
  if (proximityDistance < 2.0) {
    return 'aircraft-red.png';     // Critical - Red
  } else if (proximityDistance < 5.0) {
    return 'aircraft-orange.png';  // Warning - Orange
  } else if (proximityDistance < 10.0) {
    return 'aircraft-yellow.png';  // Caution - Yellow
  } else {
    return 'aircraft-green.png';   // Safe - Green
  }
}

// Update aircraft with appropriate icon
'properties': {
  'aircraftIconPath': getAircraftIcon(_proximityDistance),
  'rotation': _currentRotation,
  // ... other properties
}
```

### Solution 3: Advanced SDF Masking (Complex)

Use SDF with custom shader masking to preserve certain areas:

#### Implementation Notes
- Requires custom MapLibre shader modifications
- Most complex solution
- Best visual quality but significant development effort
- Beyond scope of current implementation

## Recommended Implementation: Two-Layer Approach

### Advantages ✅
- **Perfect outline preservation**: Black outline always visible
- **Full color range**: Any interior color possible
- **Performance**: Native MapLibre rendering
- **Flexibility**: Easy to modify colors or outlines
- **Compatibility**: Works with existing codebase

### Creating the Split Icons

#### Using Image Editor (Photoshop/GIMP)
1. **Open your current `traffic.png`**
2. **Create outline version:**
   - Duplicate layer
   - Delete interior (keep only outline)
   - Save as `traffic-outline.png`
3. **Create fill version:**
   - Start with original
   - Delete outline/border
   - Fill interior with white (#FFFFFF)
   - Save as `traffic-fill.png`

#### Using Command Line (ImageMagick)
```bash
# Extract outline only
convert traffic.png -alpha extract -morphology EdgeOut Octagon traffic-outline.png

# Create white interior fill
convert traffic.png -fill white -colorize 100% traffic-fill.png
```

### Modified Native Implementation

The native code would need updates to support dual-layer rendering:

```java
// Add both icons to style
style.addImage(aircraftFillId, fillBitmap, true);    // SDF for tinting
style.addImage(aircraftOutlineId, outlineBitmap, false); // No SDF for fixed black

// Create fill layer (tintable)
SymbolLayer aircraftFillLayer = new SymbolLayer(fillLayerId, sourceId);
aircraftFillLayer.withProperties(
    PropertyFactory.iconImage(aircraftFillId),
    PropertyFactory.iconSize(aircraftIconSize),
    PropertyFactory.iconRotate(Expression.get("rotation")),
    PropertyFactory.iconColor(Expression.get("aircraftIconColor")) // Tinting
);

// Create outline layer (fixed black)
SymbolLayer aircraftOutlineLayer = new SymbolLayer(outlineLayerId, sourceId);
aircraftOutlineLayer.withProperties(
    PropertyFactory.iconImage(aircraftOutlineId),
    PropertyFactory.iconSize(aircraftIconSize),
    PropertyFactory.iconRotate(Expression.get("rotation"))
    // No icon color - remains black
);

// Add layers in correct order
style.addLayer(aircraftFillLayer);    // Bottom
style.addLayer(aircraftOutlineLayer); // Top
```

## Quick Test Implementation

For immediate testing, try **Solution 2** with pre-generated color variants:

1. **Create 4 versions of your `traffic.png`**:
   - Manually change interior colors in image editor
   - Keep black outline identical in all versions

2. **Test with existing code**:
   ```dart
   'properties': {
     'aircraftIconPath': _getAircraftIcon(_proximityDistance),
     'rotation': _currentRotation,
     // ... other properties
   }
   ```

3. **Switch based on proximity**:
   - No SDF tinting needed
   - Use different PNG files
   - Black outline preserved in all variants

## Benefits Summary

✅ **Perfect Visibility**: Black outline always visible regardless of interior color
✅ **Full Color Range**: Any interior color (red, orange, yellow, green, blue, etc.)  
✅ **Aviation Standards**: Maintains professional appearance
✅ **Easy Implementation**: Minimal code changes required
✅ **Performance**: Native MapLibre rendering efficiency

Choose **Solution 1 (Two-Layer)** for maximum flexibility or **Solution 2 (Pre-Generated)** for quick implementation!